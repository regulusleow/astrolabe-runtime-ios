//
//  RuntimeProcessTestDoubles.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
@testable import AstrolabeRuntime
import AstrolabeRuntimeCore

@MainActor
final class TestApplicationLifecycleSource:
    RuntimeApplicationLifecycleSource
{
    var isApplicationActive = false
    private(set) var installCount = 0
    private(set) var invalidateCount = 0
    private var launchHandler: (@MainActor @Sendable () -> Void)?
    private var activeHandler: (@MainActor @Sendable () -> Void)?

    func installHandlers(
        didFinishLaunching: @escaping @MainActor @Sendable () -> Void,
        didBecomeActive: @escaping @MainActor @Sendable () -> Void
    ) {
        installCount += 1
        launchHandler = didFinishLaunching
        activeHandler = didBecomeActive
    }

    func invalidate() {
        invalidateCount += 1
        launchHandler = nil
        activeHandler = nil
    }

    func sendDidFinishLaunching() {
        launchHandler?()
    }

    func sendDidBecomeActive() {
        activeHandler?()
    }
}

@MainActor
final class TestRuntimeProcessLifecycle: RuntimeProcessLifecycle {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var startupErrors = [Error]()
    var shouldSuspendStartup = false

    private var startupContinuation:
        CheckedContinuation<Void, Never>?
    private var startupSuspensionWaiter:
        CheckedContinuation<Void, Never>?
    private var isStartupSuspended = false

    func start() async throws -> RuntimeTransportEndpoint {
        startCount += 1
        if shouldSuspendStartup {
            isStartupSuspended = true
            startupSuspensionWaiter?.resume()
            startupSuspensionWaiter = nil
            await withCheckedContinuation { continuation in
                startupContinuation = continuation
            }
        }
        if !startupErrors.isEmpty {
            throw startupErrors.removeFirst()
        }
        return RuntimeTransportEndpoint(host: "127.0.0.1", port: 47_164)
    }

    func stop() async {
        stopCount += 1
    }

    func waitUntilStartupSuspends() async {
        guard !isStartupSuspended else {
            return
        }
        await withCheckedContinuation { continuation in
            startupSuspensionWaiter = continuation
        }
    }

    func resumeStartup() {
        shouldSuspendStartup = false
        isStartupSuspended = false
        startupContinuation?.resume()
        startupContinuation = nil
    }
}

enum TestRuntimeFailure: Error {
    case startup
}
#endif
