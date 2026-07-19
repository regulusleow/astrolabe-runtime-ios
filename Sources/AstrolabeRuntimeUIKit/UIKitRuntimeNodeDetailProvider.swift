//
//  UIKitRuntimeNodeDetailProvider.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore

@MainActor
package final class UIKitRuntimeNodeDetailProvider: RuntimeNodeDetailProviding {
    private let nodeRegistry: RuntimeNodeRegistry
    private let collectorRegistry: UIKitRuntimeAttributeCollectorRegistry

    package convenience init(nodeRegistry: RuntimeNodeRegistry) {
        self.init(
            nodeRegistry: nodeRegistry,
            collectorRegistry: UIKitRuntimeAttributeCollectorRegistry(
                nodeRegistry: nodeRegistry
            )
        )
    }

    init(
        nodeRegistry: RuntimeNodeRegistry,
        collectorRegistry: UIKitRuntimeAttributeCollectorRegistry
    ) {
        self.nodeRegistry = nodeRegistry
        self.collectorRegistry = collectorRegistry
    }

    package func nodeDetail(
        for nodeID: RuntimeOpaqueIdentifier
    ) async throws -> RuntimeNodeDetailPayload {
        guard let object = nodeRegistry.object(for: nodeID) else {
            throw RuntimeError(
                code: .nodeNotFound,
                message: "The requested runtime node is no longer available.",
                recoverySuggestion: "Capture a new hierarchy and retry with its node ID."
            )
        }
        return RuntimeNodeDetailPayload(
            nodeID: nodeID,
            sections: collectorRegistry.sections(for: object),
            extensions: nil
        )
    }
}
#endif
