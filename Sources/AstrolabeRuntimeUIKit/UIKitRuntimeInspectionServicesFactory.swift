//
//  UIKitRuntimeInspectionServicesFactory.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeRuntimeCore
import AstrolabeProtocol
import OSLog

@MainActor
package final class UIKitRuntimeInspectionServicesFactory: Sendable {
    private static let logger = Logger(
        subsystem: "com.astrolabe.runtime",
        category: "AttributePatch"
    )

    private let nodeRegistry = RuntimeNodeRegistry()
    private let targetIdentifier: RuntimeOpaqueIdentifier
    private lazy var attributePatchProvider = RuntimeAttributePatchService(
        nodeRegistry: nodeRegistry,
        mutator: UIKitRuntimeAttributeMutator()
    )

    package init(targetIdentifier: RuntimeOpaqueIdentifier) {
        self.targetIdentifier = targetIdentifier
    }

    package func makeServices() -> RuntimeInspectionServices {
        return RuntimeInspectionServices(
            appInfoProvider: UIKitRuntimeAppInfoProvider(),
            hierarchyProvider: UIKitRuntimeHierarchyProvider(
                nodeRegistry: nodeRegistry,
                targetIdentifier: targetIdentifier
            ),
            nodeDetailProvider: UIKitRuntimeNodeDetailProvider(
                nodeRegistry: nodeRegistry
            ),
            attributePatchProvider: attributePatchProvider
        )
    }

    package func clearAttributePatches() async {
        do {
            _ = try await attributePatchProvider.clearAttributePatches()
        } catch {
            Self.logger.error(
                "Failed to restore temporary attribute patches: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
#endif
