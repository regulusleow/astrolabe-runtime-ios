//
//  UIKitRuntimeAppInfoProvider.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore
import Darwin
import Foundation
import UIKit

@MainActor
package final class UIKitRuntimeAppInfoProvider: RuntimeAppInfoProviding {
    private let sceneProvider: any UIKitRuntimeSceneProviding
    private let screenMapper: UIKitRuntimeScreenMapper

    package convenience init() {
        self.init(
            sceneProvider: UIKitRuntimeSceneProvider(),
            screenMapper: UIKitRuntimeScreenMapper()
        )
    }

    init(
        sceneProvider: any UIKitRuntimeSceneProviding,
        screenMapper: UIKitRuntimeScreenMapper
    ) {
        self.sceneProvider = sceneProvider
        self.screenMapper = screenMapper
    }

    package func appInfo(
        runtime: RuntimeDescriptor
    ) async throws -> RuntimeApplicationInfoPayload {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw RuntimeError(
                code: .internalFailure,
                message: "The application bundle identifier is unavailable.",
                recoverySuggestion: nil
            )
        }
        guard let screen = sceneProvider.activeWindowScenes().first?.screen else {
            throw RuntimeError(
                code: .internalFailure,
                message: "No active UIWindowScene is available.",
                recoverySuggestion: nil
            )
        }

        let device = UIDevice.current
        return RuntimeApplicationInfoPayload(
            application: RuntimeApplication(
                identifier: bundleIdentifier,
                displayName: displayName(bundleIdentifier: bundleIdentifier),
                version: bundleValue(for: "CFBundleShortVersionString"),
                buildVersion: bundleValue(for: "CFBundleVersion")
            ),
            target: RuntimeTarget(
                identifier: runtime.instanceID,
                processIdentifier: String(ProcessInfo.processInfo.processIdentifier),
                kind: "application",
                primary: true
            ),
            environment: RuntimeEnvironment(
                platform: "ios",
                operatingSystemVersion: device.systemVersion,
                deviceCategory: deviceCategory(device.userInterfaceIdiom),
                deviceName: device.name,
                deviceModel: device.model,
                virtualDevice: isVirtualDevice,
                locale: Locale.current.identifier,
                layoutDirection: layoutDirection,
                display: screenMapper.displayInfo(for: screen),
                extensions: try RuntimeExtensionMap(
                    values: [
                        "ios.hardwareModelIdentifier": .string(
                            hardwareModelIdentifier()
                        )
                    ]
                )
            ),
            extensions: nil
        )
    }

    private var layoutDirection: RuntimeLayoutDirection {
        switch UIView.userInterfaceLayoutDirection(
            for: .unspecified
        ) {
        case .leftToRight:
            return .leftToRight
        case .rightToLeft:
            return .rightToLeft
        @unknown default:
            return .unknown
        }
    }

    private var isVirtualDevice: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private func bundleValue(for key: String) -> String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: key
        ) as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    private func displayName(bundleIdentifier: String) -> String {
        if let displayName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String, !displayName.isEmpty {
            return displayName
        }
        if let bundleName = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleName"
        ) as? String, !bundleName.isEmpty {
            return bundleName
        }
        return bundleIdentifier
    }

    private func deviceCategory(_ idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .phone:
            return "phone"
        case .pad:
            return "tablet"
        default:
            return "unknown"
        }
    }

    private func hardwareModelIdentifier() -> String {
        if let simulatorModelIdentifier = ProcessInfo.processInfo.environment[
            "SIMULATOR_MODEL_IDENTIFIER"
        ], !simulatorModelIdentifier.isEmpty {
            return simulatorModelIdentifier
        }

        var systemInfo = utsname()
        uname(&systemInfo)
        let machineSize = MemoryLayout.size(ofValue: systemInfo.machine)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: machineSize
            ) {
                String(cString: $0)
            }
        }
    }
}
#endif
