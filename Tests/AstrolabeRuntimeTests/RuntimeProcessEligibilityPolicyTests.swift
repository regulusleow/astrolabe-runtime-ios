//
//  RuntimeProcessEligibilityPolicyTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
@testable import AstrolabeRuntime
import XCTest

final class RuntimeProcessEligibilityPolicyTests: XCTestCase {
    private let policy = RuntimeProcessEligibilityPolicy()

    func testAcceptsRegularUIKitApplication() {
        XCTAssertTrue(policy.isEligible(regularApplication))
    }

    func testRejectsUnitTestProcess() {
        var facts = regularApplication
        facts.isRunningTests = true

        XCTAssertFalse(policy.isEligible(facts))
    }

    func testRejectsApplicationExtension() {
        var facts = regularApplication
        facts.isApplicationExtension = true

        XCTAssertFalse(policy.isEligible(facts))
    }

    func testRejectsSwiftUIPreview() {
        var facts = regularApplication
        facts.isSwiftUIPreview = true

        XCTAssertFalse(policy.isEligible(facts))
    }

    func testRejectsNonApplicationBundle() {
        var facts = regularApplication
        facts.isApplicationBundle = false

        XCTAssertFalse(policy.isEligible(facts))
    }

    func testRejectsProcessWithoutUIKitApplicationClass() {
        var facts = regularApplication
        facts.hasUIKitApplicationClass = false

        XCTAssertFalse(policy.isEligible(facts))
    }

    private var regularApplication: RuntimeProcessFacts {
        RuntimeProcessFacts(
            isApplicationBundle: true,
            isApplicationExtension: false,
            isRunningTests: false,
            isSwiftUIPreview: false,
            hasUIKitApplicationClass: true
        )
    }
}
#endif
