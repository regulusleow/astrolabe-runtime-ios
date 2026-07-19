//
//  UIKitRuntimeHierarchyProvider.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore

@MainActor
package final class UIKitRuntimeHierarchyProvider: RuntimeHierarchyProviding {
    /// Shared registry used to resolve hierarchy node IDs for later detail requests.
    package let nodeRegistry: RuntimeNodeRegistry

    private let windowProvider: any UIKitRuntimeWindowProviding
    private let collector: UIKitHierarchyCollector

    package convenience init(
        targetIdentifier: RuntimeOpaqueIdentifier
    ) {
        self.init(
            nodeRegistry: RuntimeNodeRegistry(),
            targetIdentifier: targetIdentifier
        )
    }

    package convenience init(
        nodeRegistry: RuntimeNodeRegistry,
        targetIdentifier: RuntimeOpaqueIdentifier
    ) {
        let sceneProvider = UIKitRuntimeSceneProvider()
        let screenMapper = UIKitRuntimeScreenMapper()
        let colorMapper = UIKitRuntimeColorMapper()
        let accessibilityMapper = UIKitRuntimeAccessibilityMapper()
        let attributeCollectorRegistry = UIKitRuntimeAttributeCollectorRegistry(
            nodeRegistry: nodeRegistry,
            colorMapper: colorMapper,
            accessibilityMapper: accessibilityMapper
        )
        self.init(
            nodeRegistry: nodeRegistry,
            windowProvider: UIKitRuntimeWindowProvider(
                sceneProvider: sceneProvider
            ),
            collector: UIKitHierarchyCollector(
                nodeRegistry: nodeRegistry,
                targetIdentifier: targetIdentifier,
                screenMapper: screenMapper,
                colorMapper: colorMapper,
                accessibilityMapper: accessibilityMapper,
                attributeCollectorRegistry: attributeCollectorRegistry
            )
        )
    }

    init(
        nodeRegistry: RuntimeNodeRegistry,
        windowProvider: any UIKitRuntimeWindowProviding,
        collector: UIKitHierarchyCollector
    ) {
        self.nodeRegistry = nodeRegistry
        self.windowProvider = windowProvider
        self.collector = collector
    }

    package func hierarchySnapshot() async throws -> RuntimeHierarchySnapshotPayload {
        try collector.capture(context: windowProvider.activeWindowContext())
    }
}
#endif
