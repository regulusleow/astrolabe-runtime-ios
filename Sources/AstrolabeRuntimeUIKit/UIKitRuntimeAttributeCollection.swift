//
//  UIKitRuntimeAttributeCollection.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore

@MainActor
protocol UIKitRuntimeAttributeCollecting: Sendable {
    var category: RuntimeAttributeCategory { get }

    func supports(_ object: AnyObject) -> Bool

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute]
}

@MainActor
struct UIKitRuntimeAttributeCollectionContext {
    /// Registry resolving runtime objects to session-scoped node identifiers.
    let nodeRegistry: RuntimeNodeRegistry

    /// Mapper normalizing UIKit and Core Animation colors.
    let colorMapper: UIKitRuntimeColorMapper

    /// Mapper normalizing UIKit accessibility metadata.
    let accessibilityMapper: UIKitRuntimeAccessibilityMapper
}

@MainActor
final class UIKitRuntimeAttributeCollectorRegistry {
    private let collectors: [any UIKitRuntimeAttributeCollecting]
    private let context: UIKitRuntimeAttributeCollectionContext

    convenience init(
        nodeRegistry: RuntimeNodeRegistry,
        collectors: [any UIKitRuntimeAttributeCollecting]? = nil
    ) {
        self.init(
            nodeRegistry: nodeRegistry,
            colorMapper: UIKitRuntimeColorMapper(),
            accessibilityMapper: UIKitRuntimeAccessibilityMapper(),
            collectors: collectors
        )
    }

    init(
        nodeRegistry: RuntimeNodeRegistry,
        colorMapper: UIKitRuntimeColorMapper,
        accessibilityMapper: UIKitRuntimeAccessibilityMapper,
        collectors: [any UIKitRuntimeAttributeCollecting]? = nil
    ) {
        context = UIKitRuntimeAttributeCollectionContext(
            nodeRegistry: nodeRegistry,
            colorMapper: colorMapper,
            accessibilityMapper: accessibilityMapper
        )
        self.collectors = collectors ?? Self.defaultCollectors
    }

    func categories(for object: AnyObject) -> [RuntimeAttributeCategory] {
        collectors.compactMap { collector in
            collector.supports(object) ? collector.category : nil
        }
    }

    func sections(for object: AnyObject) -> [RuntimeAttributeSection] {
        collectors.compactMap { collector in
            guard collector.supports(object) else {
                return nil
            }
            return RuntimeAttributeSection(
                category: collector.category,
                attributes: collector.attributes(for: object, context: context)
            )
        }
    }

    private static var defaultCollectors: [any UIKitRuntimeAttributeCollecting] {
        [
            UIKitLayoutAttributeCollector(),
            UIKitNormalizedLayoutRelationAttributeCollector(),
            UIKitViewAttributeCollector(),
            UIKitLayerAttributeCollector(),
            UIKitGradientLayerAttributeCollector(),
            UIKitShapeLayerAttributeCollector(),
            UIKitAccessibilityAttributeCollector(),
            UIKitLabelAttributeCollector(),
            UIKitImageViewAttributeCollector(),
            UIKitControlAttributeCollector(),
            UIKitButtonAttributeCollector(),
            UIKitTextInputAttributeCollector(),
            UIKitScrollViewAttributeCollector(),
            UIKitStackViewAttributeCollector(),
            UIKitAutoLayoutAttributeCollector()
        ]
    }
}
#endif
