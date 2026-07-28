//
//  RuntimeApplicationLifecycleSource.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
import Foundation
import UIKit

@MainActor
package protocol RuntimeApplicationLifecycleSource: AnyObject {
    var isApplicationActive: Bool { get }

    func installHandlers(
        didFinishLaunching: @escaping @MainActor @Sendable () -> Void,
        didBecomeActive: @escaping @MainActor @Sendable () -> Void
    )

    func invalidate()
}

@MainActor
package final class UIKitRuntimeApplicationLifecycleSource:
    RuntimeApplicationLifecycleSource
{
    package var isApplicationActive: Bool {
        applicationIsActive()
    }

    private let notificationCenter: NotificationCenter
    private let didFinishLaunchingName: Notification.Name
    private let didBecomeActiveName: Notification.Name
    private let applicationIsActive: @MainActor () -> Bool
    private var observerTokens = [NSObjectProtocol]()

    package init(
        notificationCenter: NotificationCenter = .default,
        didFinishLaunchingName: Notification.Name =
            UIApplication.didFinishLaunchingNotification,
        didBecomeActiveName: Notification.Name =
            UIApplication.didBecomeActiveNotification,
        applicationIsActive: @escaping @MainActor () -> Bool = {
            UIApplication.shared.applicationState == .active
        }
    ) {
        self.notificationCenter = notificationCenter
        self.didFinishLaunchingName = didFinishLaunchingName
        self.didBecomeActiveName = didBecomeActiveName
        self.applicationIsActive = applicationIsActive
    }

    deinit {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
    }

    package func installHandlers(
        didFinishLaunching: @escaping @MainActor @Sendable () -> Void,
        didBecomeActive: @escaping @MainActor @Sendable () -> Void
    ) {
        guard observerTokens.isEmpty else {
            return
        }
        observerTokens = [
            observe(didFinishLaunchingName, handler: didFinishLaunching),
            observe(didBecomeActiveName, handler: didBecomeActive)
        ]
    }

    package func invalidate() {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    private func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
    }
}
#endif
