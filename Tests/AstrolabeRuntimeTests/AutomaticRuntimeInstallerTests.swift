//
//  AutomaticRuntimeInstallerTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
@testable import AstrolabeRuntime
import XCTest

@MainActor
final class AutomaticRuntimeInstallerTests: XCTestCase {
    func testEligibleProcessInstallsCoordinator() {
        let harness = makeHarness(eligible: true)

        harness.installer.install()

        XCTAssertEqual(harness.source.installCount, 1)
    }

    func testIneligibleProcessDoesNotInstallCoordinator() {
        let harness = makeHarness(eligible: false)

        harness.installer.install()

        XCTAssertEqual(harness.source.installCount, 0)
    }

    func testRepeatedInstallDoesNotDuplicateObservers() {
        let harness = makeHarness(eligible: true)

        harness.installer.install()
        harness.installer.install()

        XCTAssertEqual(harness.source.installCount, 1)
    }

    private func makeHarness(eligible: Bool) -> InstallerHarness {
        let source = TestApplicationLifecycleSource()
        let lifecycle = TestRuntimeProcessLifecycle()
        let coordinator = RuntimeProcessCoordinator(
            applicationLifecycleSource: source,
            lifecycleFactory: { lifecycle },
            failureReporter: { _ in }
        )
        let facts = RuntimeProcessFacts(
            isApplicationBundle: eligible,
            isApplicationExtension: false,
            isRunningTests: false,
            isSwiftUIPreview: false,
            hasUIKitApplicationClass: true
        )
        return InstallerHarness(
            installer: AutomaticRuntimeInstaller(
                factsProvider: { facts },
                eligibilityPolicy: RuntimeProcessEligibilityPolicy(),
                coordinator: coordinator
            ),
            source: source
        )
    }
}

@MainActor
private struct InstallerHarness {
    let installer: AutomaticRuntimeInstaller
    let source: TestApplicationLifecycleSource
}
#endif
