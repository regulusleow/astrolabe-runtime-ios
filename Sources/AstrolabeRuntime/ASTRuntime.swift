//
//  ASTRuntime.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/11.
//

#if canImport(UIKit)
import Foundation
import OSLog

/// Provides the Objective-C entry point for controlling Astrolabe Runtime.
///
/// Calls are serialized on the main actor and may be made from any thread.
@objc(ASTRuntime)
public final class ASTRuntime: NSObject {
    private static let logger = Logger(
        subsystem: "com.astrolabe.runtime",
        category: "Lifecycle"
    )

    private override init() {
        super.init()
    }

    /// Starts the runtime using the SDK version advertised during handshake.
    ///
    /// Failures are logged. Use ``start(completion:)`` when the host
    /// application needs to handle startup errors.
    @objc public static func start() {
        Task { @MainActor in
            ASTRuntimeCoordinator.shared.start { error in
                guard let error else {
                    return
                }
                logger.error(
                    "Astrolabe Runtime failed to start: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Starts the runtime and reports the result on the main actor.
    ///
    /// Repeated calls complete successfully when the runtime is already
    /// running. Calls made during a lifecycle transition report an error.
    ///
    /// - Parameter completion: Receives `nil` after startup or an error on
    ///   failure.
    @objc(startWithCompletion:)
    public static func start(
        completion: (@MainActor @Sendable (NSError?) -> Void)?
    ) {
        Task { @MainActor in
            ASTRuntimeCoordinator.shared.start(completion: completion)
        }
    }

    /// Stops the runtime and releases its listener and active connections.
    @objc public static func stop() {
        Task { @MainActor in
            ASTRuntimeCoordinator.shared.stop(completion: nil)
        }
    }

    /// Stops the runtime and invokes the completion on the main actor.
    ///
    /// Repeated calls complete successfully when no runtime is active.
    ///
    /// - Parameter completion: Invoked after the runtime has stopped.
    @objc(stopWithCompletion:)
    public static func stop(
        completion: (@MainActor @Sendable () -> Void)?
    ) {
        Task { @MainActor in
            ASTRuntimeCoordinator.shared.stop(completion: completion)
        }
    }

    /// Reports whether the runtime is accepting inspection requests.
    ///
    /// - Parameter completion: Receives the current running state on the main
    ///   actor.
    @objc(isRunningWithCompletion:)
    public static func isRunning(
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        Task { @MainActor in
            completion(ASTRuntimeCoordinator.shared.isRunning)
        }
    }
}

private enum ASTRuntimeFacadeState: Equatable {
    case stopped
    case starting
    case running
    case stopping
}

@MainActor
private final class ASTRuntimeCoordinator {
    static let shared = ASTRuntimeCoordinator()

    var isRunning: Bool {
        state == .running
    }

    private var state: ASTRuntimeFacadeState = .stopped
    private var lifecycle: UIKitRuntimeLifecycle?
    private var stopCompletions = [@MainActor @Sendable () -> Void]()

    private init() {}

    func start(
        completion: (@MainActor @Sendable (NSError?) -> Void)?
    ) {
        switch state {
        case .running:
            completion?(nil)
            return
        case .starting, .stopping:
            completion?(
                UIKitRuntimeLifecycleError.invalidState as NSError
            )
            return
        case .stopped:
            break
        }

        do {
            let lifecycle = try UIKitRuntimeLifecycle(
                configuration: RuntimeServerConfiguration(
                    runtimeVersion: AstrolabeRuntimeSDK.runtimeVersion
                )
            )
            self.lifecycle = lifecycle
            state = .starting
            Task { @MainActor [weak self] in
                do {
                    _ = try await lifecycle.start()
                    guard self?.lifecycle === lifecycle,
                          self?.state == .starting else {
                        completion?(
                            UIKitRuntimeLifecycleError.invalidState as NSError
                        )
                        return
                    }
                    self?.state = .running
                    completion?(nil)
                } catch {
                    if self?.lifecycle === lifecycle {
                        let wasStopping = self?.state == .stopping
                        self?.lifecycle = nil
                        self?.state = .stopped
                        if wasStopping {
                            self?.completeStop()
                        }
                    }
                    completion?(error as NSError)
                }
            }
        } catch {
            state = .stopped
            completion?(error as NSError)
        }
    }

    func stop(completion: (@MainActor @Sendable () -> Void)?) {
        if let completion {
            stopCompletions.append(completion)
        }

        switch state {
        case .stopped:
            completeStop()
            return
        case .stopping:
            return
        case .starting, .running:
            break
        }

        guard let lifecycle else {
            state = .stopped
            completeStop()
            return
        }
        state = .stopping

        Task { @MainActor [weak self] in
            await lifecycle.stop()
            guard self?.lifecycle === lifecycle else {
                return
            }
            self?.lifecycle = nil
            self?.state = .stopped
            self?.completeStop()
        }
    }

    private func completeStop() {
        let completions = stopCompletions
        stopCompletions.removeAll()
        completions.forEach { completion in
            completion()
        }
    }
}
#endif
