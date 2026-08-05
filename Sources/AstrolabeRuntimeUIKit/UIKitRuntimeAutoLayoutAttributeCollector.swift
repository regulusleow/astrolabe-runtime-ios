//
//  UIKitRuntimeAutoLayoutAttributeCollector.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore
import AstrolabeRuntimeObjC
import UIKit

private struct UIKitAutoLayoutConstraintSource {
    func constraints(affecting view: UIView) -> [NSLayoutConstraint] {
        var result = [NSLayoutConstraint]()
        var seen = Set<ObjectIdentifier>()

        func append(_ constraints: [NSLayoutConstraint]) {
            for constraint in constraints where references(constraint, view: view) {
                let identifier = ObjectIdentifier(constraint)
                guard seen.insert(identifier).inserted else {
                    continue
                }
                result.append(constraint)
            }
        }

        var owner: UIView? = view
        while let current = owner {
            append(current.constraints)
            owner = current.superview
        }
        append(view.constraintsAffectingLayout(for: .horizontal))
        append(view.constraintsAffectingLayout(for: .vertical))
        return result
    }

    private func references(
        _ constraint: NSLayoutConstraint,
        view: UIView
    ) -> Bool {
        (constraint.firstItem as AnyObject?) === view ||
            (constraint.secondItem as AnyObject?) === view
    }
}

private struct UIKitAutoLayoutConstraintMapper {
    func attributeName(_ attribute: NSLayoutConstraint.Attribute) -> String {
        switch attribute {
        case .notAnAttribute: return "notAnAttribute"
        case .left: return "left"
        case .right: return "right"
        case .top: return "top"
        case .bottom: return "bottom"
        case .leading: return "leading"
        case .trailing: return "trailing"
        case .width: return "width"
        case .height: return "height"
        case .centerX: return "centerX"
        case .centerY: return "centerY"
        case .firstBaseline: return "firstBaseline"
        case .lastBaseline: return "lastBaseline"
        case .leftMargin: return "leftMargin"
        case .rightMargin: return "rightMargin"
        case .topMargin: return "topMargin"
        case .bottomMargin: return "bottomMargin"
        case .leadingMargin: return "leadingMargin"
        case .trailingMargin: return "trailingMargin"
        case .centerXWithinMargins: return "centerXWithinMargins"
        case .centerYWithinMargins: return "centerYWithinMargins"
        @unknown default:
            return "unknown:\(attribute.rawValue)"
        }
    }

    func relationName(_ relation: NSLayoutConstraint.Relation) -> String {
        switch relation {
        case .lessThanOrEqual: return "lessThanOrEqual"
        case .equal: return "equal"
        case .greaterThanOrEqual: return "greaterThanOrEqual"
        @unknown default:
            return "unknown:\(relation.rawValue)"
        }
    }

    func relationKind(
        _ relation: NSLayoutConstraint.Relation
    ) -> RuntimeLayoutRelationKind? {
        switch relation {
        case .lessThanOrEqual: return .lessThanOrEqual
        case .equal: return .equal
        case .greaterThanOrEqual: return .greaterThanOrEqual
        @unknown default: return nil
        }
    }
}

@MainActor
private struct UIKitNormalizedLayoutRelationProjector {
    private let mapper = UIKitAutoLayoutConstraintMapper()

    func relation(
        from constraint: NSLayoutConstraint,
        nodeRegistry: RuntimeNodeRegistry
    ) -> RuntimeLayoutRelation? {
        guard let sourceView = constraint.firstItem as? UIView,
              constraint.multiplier.isFinite,
              constraint.constant.isFinite,
              constraint.priority.rawValue.isFinite,
              let relation = mapper.relationKind(constraint.relation),
              let extensions = try? RuntimeExtensionMap(values: [
                  "ios.uikit.priority": .number(Double(constraint.priority.rawValue))
              ]) else {
            return nil
        }
        let target: RuntimeLayoutAnchor?
        if let secondItem = constraint.secondItem {
            guard let targetView = secondItem as? UIView else {
                return nil
            }
            target = RuntimeLayoutAnchor(
                nodeID: nodeRegistry.nodeID(for: targetView),
                anchor: mapper.attributeName(constraint.secondAttribute)
            )
        } else {
            target = nil
        }
        let strength = min(max(Double(constraint.priority.rawValue) / 1_000, 0), 1)
        return RuntimeLayoutRelation(
            identifier: nonempty(constraint.identifier),
            source: RuntimeLayoutAnchor(
                nodeID: nodeRegistry.nodeID(for: sourceView),
                anchor: mapper.attributeName(constraint.firstAttribute)
            ),
            relation: relation,
            target: target,
            multiplier: Double(constraint.multiplier),
            offset: RuntimeMeasurement(
                value: Double(constraint.constant),
                unit: .logical
            ),
            strength: strength,
            active: constraint.isActive,
            extensions: extensions
        )
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct UIKitNormalizedLayoutRelationAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.commonLayout

    private let constraintSource = UIKitAutoLayoutConstraintSource()
    private let projector = UIKitNormalizedLayoutRelationProjector()

    func supports(_ object: AnyObject) -> Bool {
        object is UIView
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let view = object as? UIView else {
            return []
        }
        let relations = constraintSource.constraints(affecting: view).compactMap {
            projector.relation(from: $0, nodeRegistry: context.nodeRegistry)
        }
        return [attribute(.commonLayoutRelations, .layoutRelations(relations))]
    }
}

struct UIKitAutoLayoutAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.autoLayout

    private let constraintSource = UIKitAutoLayoutConstraintSource()
    private let mapper = UIKitAutoLayoutConstraintMapper()

    func supports(_ object: AnyObject) -> Bool {
        object is UIView
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let view = object as? UIView else {
            return []
        }
        let constraints = constraintSource.constraints(affecting: view).compactMap {
            runtimeConstraint($0, nodeRegistry: context.nodeRegistry)
        }
        return [
            attribute(
                .translatesAutoresizingMaskIntoConstraints,
                .boolean(view.translatesAutoresizingMaskIntoConstraints)
            ),
            attribute(
                .horizontalContentHuggingPriority,
                .number(
                    Double(
                        view.contentHuggingPriority(
                            for: .horizontal
                        ).rawValue
                    )
                )
            ),
            attribute(
                .verticalContentHuggingPriority,
                .number(
                    Double(
                        view.contentHuggingPriority(
                            for: .vertical
                        ).rawValue
                    )
                )
            ),
            attribute(
                .horizontalCompressionResistancePriority,
                .number(
                    Double(
                        view.contentCompressionResistancePriority(
                            for: .horizontal
                        ).rawValue
                    )
                )
            ),
            attribute(
                .verticalCompressionResistancePriority,
                .number(
                    Double(
                        view.contentCompressionResistancePriority(
                            for: .vertical
                        ).rawValue
                    )
                )
            ),
            attribute(.constraints, .array(constraints))
        ]
    }

    private func runtimeConstraint(
        _ constraint: NSLayoutConstraint,
        nodeRegistry: RuntimeNodeRegistry
    ) -> RuntimeJSONValue? {
        guard let firstItem = runtimeItem(
            constraint.firstItem as AnyObject?,
            nodeRegistry: nodeRegistry
        ) else {
            return nil
        }
        let secondItem = runtimeItem(
            constraint.secondItem as AnyObject?,
            nodeRegistry: nodeRegistry
        ) ?? .null
        return .object([
            "identifier": optionalString(constraint.identifier),
            "firstItem": firstItem,
            "firstAttribute": .string(
                mapper.attributeName(constraint.firstAttribute)
            ),
            "relation": .string(mapper.relationName(constraint.relation)),
            "secondItem": secondItem,
            "secondAttribute": .string(
                mapper.attributeName(constraint.secondAttribute)
            ),
            "multiplier": .number(constraint.multiplier),
            "constant": .number(constraint.constant),
            "priority": .number(Double(constraint.priority.rawValue)),
            "active": .boolean(constraint.isActive)
        ])
    }

    private func runtimeItem(
        _ item: AnyObject?,
        nodeRegistry: RuntimeNodeRegistry
    ) -> RuntimeJSONValue? {
        guard let item else {
            return nil
        }
        if let view = item as? UIView {
            return .object([
                "kind": .string("node"),
                "nodeID": .string(
                    nodeRegistry.nodeID(for: view).rawValue
                ),
                "name": .string(
                    nonempty(view.accessibilityIdentifier) ??
                        RuntimeMetadataAdapter.className(for: view)
                )
            ])
        }
        if let guide = item as? UILayoutGuide {
            return .object([
                "kind": .string("layoutGuide"),
                "name": .string(
                    nonempty(guide.identifier) ??
                        RuntimeMetadataAdapter.className(for: guide)
                )
            ])
        }
        return .object([
            "kind": .string("object"),
            "name": .string(
                RuntimeMetadataAdapter.className(for: item)
            )
        ])
    }

    private func optionalString(_ value: String?) -> RuntimeJSONValue {
        guard let value = nonempty(value) else {
            return .null
        }
        return .string(value)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
#endif
