//
//  RuntimeApplicationLifecycleSourceTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
@testable import AstrolabeRuntime
import XCTest

@MainActor
final class RuntimeApplicationLifecycleSourceTests: XCTestCase {
    func testForwardsLaunchAndActivationNotifications() {
        let center = NotificationCenter()
        let launchNotification = Notification.Name("test.runtime.launch")
        let activationNotification = Notification.Name("test.runtime.active")
        let source = UIKitRuntimeApplicationLifecycleSource(
            notificationCenter: center,
            didFinishLaunchingName: launchNotification,
            didBecomeActiveName: activationNotification,
            applicationIsActive: { false }
        )
        var launchCount = 0
        var activationCount = 0

        source.installHandlers(
            didFinishLaunching: { launchCount += 1 },
            didBecomeActive: { activationCount += 1 }
        )
        center.post(name: launchNotification, object: nil)
        center.post(name: activationNotification, object: nil)

        XCTAssertEqual(launchCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testInvalidateStopsNotificationDelivery() {
        let center = NotificationCenter()
        let launchNotification = Notification.Name("test.runtime.launch")
        let source = UIKitRuntimeApplicationLifecycleSource(
            notificationCenter: center,
            didFinishLaunchingName: launchNotification,
            didBecomeActiveName: .init("test.runtime.active"),
            applicationIsActive: { false }
        )
        var launchCount = 0
        source.installHandlers(
            didFinishLaunching: { launchCount += 1 },
            didBecomeActive: {}
        )

        source.invalidate()
        center.post(name: launchNotification, object: nil)

        XCTAssertEqual(launchCount, 0)
    }
}
#endif
