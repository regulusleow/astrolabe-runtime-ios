//
//  UIKitRuntimeNodeRelationCollection.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/8/4.
//

#if canImport(UIKit)
import AstrolabeProtocol
import UIKit

protocol UIKitRuntimeNodeRelationProviding: Sendable {
    @MainActor
    func relations(
        in context: UIKitRuntimeNodeRelationCollectionContext
    ) throws -> [RuntimeNodeRelation]
}

struct UIKitRuntimeNodeRelationCollectionContext {
    /// Windows in hierarchy-capture order.
    let windows: [UIWindow]

    /// Layers in authoritative hierarchy-capture order.
    let layers: [CALayer]

    /// Captured node identifiers keyed by runtime object identity.
    private let nodeIDsByObjectIdentity:
        [ObjectIdentifier: RuntimeOpaqueIdentifier]

    init(
        windows: [UIWindow],
        layers: [CALayer],
        nodeIDsByObjectIdentity:
            [ObjectIdentifier: RuntimeOpaqueIdentifier]
    ) {
        self.windows = windows
        self.layers = layers
        self.nodeIDsByObjectIdentity = nodeIDsByObjectIdentity
    }

    func nodeID(for object: AnyObject) -> RuntimeOpaqueIdentifier? {
        nodeIDsByObjectIdentity[ObjectIdentifier(object)]
    }
}

struct UIKitRuntimeNodeRelationProviderRegistry {
    /// Ordered relation providers enabled for one hierarchy collector.
    private let providers: [any UIKitRuntimeNodeRelationProviding]

    init(
        providers: [any UIKitRuntimeNodeRelationProviding] = [
            UIKitViewBackingLayerRelationProvider(),
            UIKitLayerMaskRelationProvider()
        ]
    ) {
        self.providers = providers
    }

    @MainActor
    func relations(
        in context: UIKitRuntimeNodeRelationCollectionContext
    ) throws -> [RuntimeNodeRelation] {
        try providers.flatMap { provider in
            try provider.relations(in: context)
        }
    }
}

private struct UIKitLayerMaskRelationProvider:
    UIKitRuntimeNodeRelationProviding
{
    @MainActor
    func relations(
        in context: UIKitRuntimeNodeRelationCollectionContext
    ) throws -> [RuntimeNodeRelation] {
        try context.layers.compactMap { layer in
            guard let mask = layer.mask,
                  let layerNodeID = context.nodeID(for: layer),
                  let maskNodeID = context.nodeID(for: mask)
            else {
                return nil
            }
            return RuntimeNodeRelation(
                type: .iosLayerMaskRelation,
                sourceNodeID: layerNodeID,
                targetNodeID: maskNodeID,
                extensions: try RuntimeExtensionMap()
            )
        }
    }
}

private struct UIKitViewBackingLayerRelationProvider:
    UIKitRuntimeNodeRelationProviding
{
    @MainActor
    func relations(
        in context: UIKitRuntimeNodeRelationCollectionContext
    ) throws -> [RuntimeNodeRelation] {
        try context.windows.flatMap { window in
            try relations(for: window, context: context)
        }
    }

    @MainActor
    private func relations(
        for view: UIView,
        context: UIKitRuntimeNodeRelationCollectionContext
    ) throws -> [RuntimeNodeRelation] {
        var relations = [RuntimeNodeRelation]()
        if let viewNodeID = context.nodeID(for: view),
           let layerNodeID = context.nodeID(for: view.layer) {
            relations.append(
                RuntimeNodeRelation(
                    type: .iosViewBackingLayerRelation,
                    sourceNodeID: viewNodeID,
                    targetNodeID: layerNodeID,
                    extensions: try RuntimeExtensionMap()
                )
            )
        }
        for subview in view.subviews {
            relations.append(contentsOf: try self.relations(
                for: subview,
                context: context
            ))
        }
        return relations
    }
}
#endif
