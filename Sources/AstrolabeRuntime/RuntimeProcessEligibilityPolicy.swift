//
//  RuntimeProcessEligibilityPolicy.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
import Foundation

package struct RuntimeProcessFacts {
    /// Whether the main bundle is an iOS application bundle.
    package var isApplicationBundle: Bool

    /// Whether the current executable belongs to an app extension.
    package var isApplicationExtension: Bool

    /// Whether the process is hosting an XCTest session.
    package var isRunningTests: Bool

    /// Whether Xcode launched the process for a SwiftUI preview.
    package var isSwiftUIPreview: Bool

    /// Whether the UIKit application class exists in the process.
    package var hasUIKitApplicationClass: Bool

    package static var current: RuntimeProcessFacts {
        let bundle = Bundle.main
        let environment = ProcessInfo.processInfo.environment
        let testEnvironmentKeys = [
            "XCTestConfigurationFilePath",
            "XCTestSessionIdentifier",
            "XCTestBundlePath"
        ]

        return RuntimeProcessFacts(
            isApplicationBundle:
                bundle.object(forInfoDictionaryKey: "CFBundlePackageType")
                    as? String == "APPL",
            isApplicationExtension:
                bundle.object(forInfoDictionaryKey: "NSExtension") != nil
                    || bundle.bundleURL.pathExtension == "appex",
            isRunningTests:
                testEnvironmentKeys.contains { environment[$0] != nil }
                    || NSClassFromString("XCTestCase") != nil,
            isSwiftUIPreview:
                environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1",
            hasUIKitApplicationClass:
                NSClassFromString("UIApplication") != nil
        )
    }
}

package struct RuntimeProcessEligibilityPolicy {
    package func isEligible(_ facts: RuntimeProcessFacts) -> Bool {
        facts.isApplicationBundle
            && !facts.isApplicationExtension
            && !facts.isRunningTests
            && !facts.isSwiftUIPreview
            && facts.hasUIKitApplicationClass
    }
}
#endif
