//
//  AppKitRuntimeInstaller.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/11/20.
//

#if os(macOS)
import AstrolabeProtocol
import AstrolabeRuntimeCore
import Foundation
import OSLog

@MainActor
package enum AppKitRuntimeInstaller {
    private static let logger = Logger(subsystem: "com.astrolabe.runtime", category: "AppKit")
    private static var server: RuntimeServer?

    package static func install(version: String) async {
        let bundle = Bundle.main
        let environment = ProcessInfo.processInfo.environment
        guard server == nil,
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              bundle.object(forInfoDictionaryKey: "NSExtension") == nil,
              environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil else {
            return
        }

        do {
            let configuration = RuntimeServerConfiguration(
                runtimeVersion: version,
                platform: "macos",
                runtimeIdentifier: try RuntimeNamespacedIdentifier(rawValue: "astrolabe.runtime-macos")
            )
            let provider = AppKitRuntimeInspectionProvider(targetID: configuration.runtimeInstanceIdentifier)
            let runtime = try RuntimeServer(
                configuration: configuration,
                transport: LocalTCPRuntimeTransport(portSelection: .range(RuntimePortDefaults.macOSRange)),
                inspectionServicesFactory: {
                    RuntimeInspectionServices(
                        appInfoProvider: provider,
                        hierarchyProvider: provider,
                        nodeDetailProvider: provider
                    )
                }
            )
            server = runtime
            try await runtime.start()
        } catch {
            server = nil
            if case RuntimeTransportError.noAvailablePort = error {
                let ports = RuntimePortDefaults.macOSRange
                logger.error("AppKit Runtime 启动失败：本机端口 \(ports.lowerBound) 至 \(ports.upperBound) 均不可用")
            } else {
                logger.error("AppKit Runtime 启动失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
