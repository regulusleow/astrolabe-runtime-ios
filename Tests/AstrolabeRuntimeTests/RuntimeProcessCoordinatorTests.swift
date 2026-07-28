//
//  RuntimeProcessCoordinatorTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
@testable import AstrolabeRuntime
import XCTest

@MainActor
final class RuntimeProcessCoordinatorTests: XCTestCase {
    func testInstallIsIdempotent() {
        let harness = makeHarness()

        harness.coordinator.install()
        harness.coordinator.install()

        XCTAssertEqual(harness.source.installCount, 1)
        XCTAssertEqual(harness.coordinator.state, .waitingForApplication)
    }

    func testColdLaunchStartsAfterDidFinishLaunching() async {
        let harness = makeHarness()

        harness.coordinator.install()
        XCTAssertEqual(harness.lifecycle.startCount, 0)

        harness.source.sendDidFinishLaunching()
        await harness.coordinator.waitForStartupForTesting()

        XCTAssertEqual(harness.lifecycle.startCount, 1)
        XCTAssertEqual(harness.coordinator.state, .running)
    }

    func testAlreadyActiveApplicationStartsImmediately() async {
        let harness = makeHarness(applicationIsActive: true)

        harness.coordinator.install()
        await harness.coordinator.waitForStartupForTesting()

        XCTAssertEqual(harness.lifecycle.startCount, 1)
        XCTAssertEqual(harness.coordinator.state, .running)
    }

    func testStartingAndRunningIgnoreDuplicateEvents() async {
        let harness = makeHarness()
        harness.coordinator.install()

        harness.source.sendDidFinishLaunching()
        harness.source.sendDidBecomeActive()
        await harness.coordinator.waitForStartupForTesting()
        harness.source.sendDidBecomeActive()
        await harness.coordinator.waitForStartupForTesting()

        XCTAssertEqual(harness.lifecycle.startCount, 1)
        XCTAssertEqual(harness.coordinator.state, .running)
    }

    func testFailedInitialStartRetriesOnNextActivation() async {
        let harness = makeHarness(startupErrors: [TestRuntimeFailure.startup])
        harness.coordinator.install()

        harness.source.sendDidFinishLaunching()
        await harness.coordinator.waitForStartupForTesting()
        XCTAssertEqual(
            harness.coordinator.state,
            .failed(retryAvailable: true)
        )

        harness.source.sendDidBecomeActive()
        await harness.coordinator.waitForStartupForTesting()

        XCTAssertEqual(harness.lifecycle.startCount, 2)
        XCTAssertEqual(harness.coordinator.state, .running)
        XCTAssertEqual(harness.reportedErrors.count, 1)
    }

    func testFailedRetryDoesNotRetryAgain() async {
        let harness = makeHarness(
            startupErrors: [
                TestRuntimeFailure.startup,
                TestRuntimeFailure.startup
            ]
        )
        harness.coordinator.install()

        harness.source.sendDidFinishLaunching()
        await harness.coordinator.waitForStartupForTesting()
        harness.source.sendDidBecomeActive()
        await harness.coordinator.waitForStartupForTesting()
        harness.source.sendDidBecomeActive()
        await harness.coordinator.waitForStartupForTesting()

        XCTAssertEqual(harness.lifecycle.startCount, 2)
        XCTAssertEqual(
            harness.coordinator.state,
            .failed(retryAvailable: false)
        )
        XCTAssertEqual(harness.reportedErrors.count, 2)
    }

    func testInitialLifecycleFactoryFailureAllowsOneRetry() async {
        let harness = makeHarness(
            factoryErrors: [TestRuntimeFailure.startup]
        )
        harness.coordinator.install()

        harness.source.sendDidFinishLaunching()
        await harness.coordinator.waitForStartupForTesting()
        XCTAssertEqual(
            harness.coordinator.state,
            .failed(retryAvailable: true)
        )

        harness.source.sendDidBecomeActive()
        await harness.coordinator.waitForStartupForTesting()

        XCTAssertEqual(harness.lifecycle.startCount, 1)
        XCTAssertEqual(harness.coordinator.state, .running)
        XCTAssertEqual(harness.reportedErrors.count, 1)
    }

    func testRetryLifecycleFactoryFailureDisablesFurtherRetries() async {
        let harness = makeHarness(
            factoryErrors: [
                TestRuntimeFailure.startup,
                TestRuntimeFailure.startup
            ]
        )
        harness.coordinator.install()

        harness.source.sendDidFinishLaunching()
        await harness.coordinator.waitForStartupForTesting()
        harness.source.sendDidBecomeActive()
        await harness.coordinator.waitForStartupForTesting()
        harness.source.sendDidBecomeActive()
        await harness.coordinator.waitForStartupForTesting()

        XCTAssertEqual(harness.lifecycle.startCount, 0)
        XCTAssertEqual(
            harness.coordinator.state,
            .failed(retryAvailable: false)
        )
        XCTAssertEqual(harness.reportedErrors.count, 2)
    }

    func testNoBackgroundEventStopsTheRuntime() async {
        let harness = makeHarness(applicationIsActive: true)
        harness.coordinator.install()
        await harness.coordinator.waitForStartupForTesting()

        harness.source.isApplicationActive = false

        XCTAssertEqual(harness.lifecycle.stopCount, 0)
        XCTAssertEqual(harness.coordinator.state, .running)
    }

    func testShutdownForTestingInvalidatesSourceAndStopsLifecycle() async {
        let harness = makeHarness(applicationIsActive: true)
        harness.coordinator.install()
        await harness.coordinator.waitForStartupForTesting()

        await harness.coordinator.shutdownForTesting()

        XCTAssertEqual(harness.source.invalidateCount, 1)
        XCTAssertEqual(harness.lifecycle.stopCount, 1)
        XCTAssertEqual(harness.coordinator.state, .notInstalled)
    }

    func testShutdownDuringStartupPreventsStaleCompletion() async {
        let harness = makeHarness()
        harness.lifecycle.shouldSuspendStartup = true
        harness.coordinator.install()
        harness.source.sendDidFinishLaunching()
        await harness.lifecycle.waitUntilStartupSuspends()

        XCTAssertEqual(harness.coordinator.state, .starting)

        await harness.coordinator.shutdownForTesting()
        harness.lifecycle.resumeStartup()
        await Task.yield()

        XCTAssertEqual(harness.lifecycle.stopCount, 1)
        XCTAssertEqual(harness.coordinator.state, .notInstalled)
    }

    private func makeHarness(
        applicationIsActive: Bool = false,
        startupErrors: [Error] = [],
        factoryErrors: [TestRuntimeFailure] = []
    ) -> CoordinatorHarness {
        let source = TestApplicationLifecycleSource()
        source.isApplicationActive = applicationIsActive
        let lifecycle = TestRuntimeProcessLifecycle()
        lifecycle.startupErrors = startupErrors
        let reportedErrors = ReportedErrors()
        let factoryFailures = FactoryFailures(values: factoryErrors)
        let coordinator = RuntimeProcessCoordinator(
            applicationLifecycleSource: source,
            lifecycleFactory: {
                if !factoryFailures.values.isEmpty {
                    throw factoryFailures.values.removeFirst()
                }
                return lifecycle
            },
            failureReporter: { error in
                reportedErrors.values.append(error)
            }
        )
        return CoordinatorHarness(
            coordinator: coordinator,
            source: source,
            lifecycle: lifecycle,
            reportedErrors: reportedErrors
        )
    }
}

@MainActor
private final class ReportedErrors {
    var values = [Error]()

    var count: Int {
        values.count
    }
}

@MainActor
private final class FactoryFailures {
    var values: [TestRuntimeFailure]

    init(values: [TestRuntimeFailure]) {
        self.values = values
    }
}

@MainActor
private struct CoordinatorHarness {
    let coordinator: RuntimeProcessCoordinator
    let source: TestApplicationLifecycleSource
    let lifecycle: TestRuntimeProcessLifecycle
    let reportedErrors: ReportedErrors
}
#endif
