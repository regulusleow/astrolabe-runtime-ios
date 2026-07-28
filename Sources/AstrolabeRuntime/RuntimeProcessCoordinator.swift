//
//  RuntimeProcessCoordinator.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
import AstrolabeRuntimeCore
import Foundation

@MainActor
package protocol RuntimeProcessLifecycle: AnyObject {
    func start() async throws -> RuntimeTransportEndpoint
    func stop() async
}

package enum RuntimeProcessState: Equatable {
    case notInstalled
    case waitingForApplication
    case starting
    case running
    case failed(retryAvailable: Bool)
}

@MainActor
package final class RuntimeProcessCoordinator {
    package typealias LifecycleFactory =
        @MainActor () throws -> any RuntimeProcessLifecycle
    package typealias FailureReporter =
        @MainActor @Sendable (Error) -> Void

    package private(set) var state: RuntimeProcessState = .notInstalled

    private let applicationLifecycleSource:
        any RuntimeApplicationLifecycleSource
    private let lifecycleFactory: LifecycleFactory
    private let failureReporter: FailureReporter
    private var runtimeLifecycle: (any RuntimeProcessLifecycle)?
    private var startupTask: Task<Void, Never>?

    package init(
        applicationLifecycleSource:
            any RuntimeApplicationLifecycleSource,
        lifecycleFactory: @escaping LifecycleFactory,
        failureReporter: @escaping FailureReporter
    ) {
        self.applicationLifecycleSource = applicationLifecycleSource
        self.lifecycleFactory = lifecycleFactory
        self.failureReporter = failureReporter
    }

    package func install() {
        guard state == .notInstalled else {
            return
        }
        state = .waitingForApplication
        applicationLifecycleSource.installHandlers(
            didFinishLaunching: { [weak self] in
                self?.startInitialAttemptIfNeeded()
            },
            didBecomeActive: { [weak self] in
                self?.handleDidBecomeActive()
            }
        )
        if applicationLifecycleSource.isApplicationActive {
            startInitialAttemptIfNeeded()
        }
    }

    package func waitForStartupForTesting() async {
        await startupTask?.value
    }

    package func shutdownForTesting() async {
        applicationLifecycleSource.invalidate()
        let lifecycle = runtimeLifecycle
        runtimeLifecycle = nil
        startupTask?.cancel()
        startupTask = nil
        state = .notInstalled
        await lifecycle?.stop()
    }

    private func startInitialAttemptIfNeeded() {
        guard state == .waitingForApplication else {
            return
        }
        start(.initial)
    }

    private func handleDidBecomeActive() {
        switch state {
        case .waitingForApplication:
            start(.initial)
        case .failed(retryAvailable: true):
            start(.retry)
        case .notInstalled,
             .starting,
             .running,
             .failed(retryAvailable: false):
            return
        }
    }

    private func start(_ attempt: StartupAttempt) {
        let lifecycle: any RuntimeProcessLifecycle
        do {
            lifecycle = try lifecycleFactory()
        } catch {
            failureReporter(error)
            state = .failed(retryAvailable: attempt == .initial)
            return
        }

        runtimeLifecycle = lifecycle
        state = .starting
        startupTask = Task { [weak self, lifecycle] in
            let result: Result<RuntimeTransportEndpoint, Error>
            do {
                result = .success(try await lifecycle.start())
            } catch {
                result = .failure(error)
            }
            self?.completeStart(
                lifecycle: lifecycle,
                attempt: attempt,
                result: result
            )
        }
    }

    private func completeStart(
        lifecycle: any RuntimeProcessLifecycle,
        attempt: StartupAttempt,
        result: Result<RuntimeTransportEndpoint, Error>
    ) {
        guard runtimeLifecycle === lifecycle, state == .starting else {
            return
        }
        startupTask = nil

        switch result {
        case .success:
            state = .running
        case let .failure(error):
            runtimeLifecycle = nil
            failureReporter(error)
            state = .failed(retryAvailable: attempt == .initial)
        }
    }
}

private enum StartupAttempt {
    case initial
    case retry
}
#endif
