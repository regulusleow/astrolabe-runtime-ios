#if canImport(UIKit)
import AstrolabeProtocol
import Foundation
import SwiftUI

/// Projects pure colors and palette levels from a selected style without choosing its source.
@available(iOS 17.0, *)
@MainActor
enum SwiftUIEnvironmentColorReader {
    static func read(selection: SwiftUIEnvironmentStyleReader.Selection, hierarchyLevel requestedLevel: Int, environment: EnvironmentValues, local: inout UIKitSemanticTraversalBudget,
                     budget: inout UIKitSemanticTraversalBudget) throws -> RuntimeSemanticTextField? {
        func field(_ value: Any, _ name: String, depth: Int) -> Any? {
            SwiftUIEnvironmentStyleReader.field(value, name, depth: depth, local: &local, budget: &budget)
        }

        func unboxStyle(_ style: AnyShapeStyle, path: String, depth: Int) -> SwiftUIEnvironmentStyleReader.Selection? {
            SwiftUIEnvironmentStyleReader.unboxStyle(style, path: path, depth: depth, local: &local, budget: &budget)
        }

        var selected = selection
        var hierarchyPath: String?
        var hierarchyLevel = 0
        let selectedType = String(reflecting: type(of: selected.value))
        if requestedLevel != 0 {
            guard SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(requestedLevel) else { return nil }
            hierarchyLevel = requestedLevel
            hierarchyPath = selection.path
        } else if SwiftUITextMetadataPolicy.isDefaultHierarchyOffsetBox(selectedType) {
            let depth = selected.depth
            guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  let offset = field(selected.value, "base", depth: depth + 1),
                  String(reflecting: type(of: offset)) == "SwiftUI.OffsetShapeStyle<SwiftUI.SystemColorsStyle>",
                  let level = field(offset, "offset", depth: depth + 2) as? Int,
                  SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(level),
                  let base = field(offset, "base", depth: depth + 2),
                  String(reflecting: type(of: base)) == "SwiftUI.SystemColorsStyle",
                  local.consume(depth: depth + 3), budget.consume(depth: depth + 3),
                  Mirror(reflecting: base).children.isEmpty,
                  local.consume(depth: depth + 4), budget.consume(depth: depth + 4),
                  let resolved = SwiftUIHierarchicalColorResolver.defaultColor(level: level, environment: environment) else { return nil }
            return try resolvedField(resolved, path: selected.path)
        } else if SwiftUITextMetadataPolicy.isHierarchyOffsetBox(selectedType) {
            let path = selected.path
            let depth = selected.depth
            guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  let offset = field(selected.value, "base", depth: depth + 1),
                  String(reflecting: type(of: offset)) == "SwiftUI.OffsetShapeStyle<SwiftUI.AnyShapeStyle>",
                  let level = field(offset, "offset", depth: depth + 2) as? Int,
                  SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(level),
                  let base = field(offset, "base", depth: depth + 2) as? AnyShapeStyle,
                  let box = unboxStyle(base, path: path + "/base/base", depth: depth + 2) else { return nil }
            selected = box
            hierarchyPath = path
            hierarchyLevel = level
        } else if SwiftUITextMetadataPolicy.isHierarchyModifierBox(selectedType) {
            let path = selected.path
            let depth = selected.depth
            guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  let modifier = field(selected.value, "base", depth: depth + 1),
                  String(reflecting: type(of: modifier)) == "SwiftUI.HierarchicalShapeStyleModifier<SwiftUI.Color>",
                  let level = field(modifier, "level", depth: depth + 2) as? Int,
                  SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(level),
                  let color = field(modifier, "base", depth: depth + 2) as? Color,
                  let provider = field(color, "provider", depth: depth + 3) else { return nil }
            selected = .init(value: provider, path: path + "/base/base/provider", depth: depth + 3)
            hierarchyPath = path
            hierarchyLevel = level
        }
        if hierarchyLevel > 0, SwiftUITextMetadataPolicy.isHierarchyPackBox(String(reflecting: type(of: selected.value))) {
            guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  let pack = field(selected.value, "base", depth: selected.depth + 1),
                  ["SwiftUI.ShapeStylePair<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>",
                   "SwiftUI.ShapeStyleTriple<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>"].contains(String(reflecting: type(of: pack))),
                  local.consume(depth: selected.depth + 2), budget.consume(depth: selected.depth + 2) else { return nil }
            // A pair reuses its secondary at level2; a triple has an explicit tertiary.
            let name = hierarchyLevel == 2 && String(reflecting: type(of: pack)).hasPrefix("SwiftUI.ShapeStyleTriple<") ? "tertiary" : "secondary"
            guard let style = field(pack, name, depth: selected.depth + 2) as? AnyShapeStyle,
                  let box = unboxStyle(style, path: selected.path + "/base/" + name, depth: selected.depth + 2) else { return nil }
            selected = box
            hierarchyPath = nil
            hierarchyLevel = 0
        }
        if SwiftUITextMetadataPolicy.isTintStyleBox(String(reflecting: type(of: selected.value))) {
            guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  field(selected.value, "base", depth: selected.depth + 1) is TintShapeStyle,
                  let tint = SwiftUIEnvironmentStyleReader.select(environment: environment, tint: true, local: &local, budget: &budget) else { return nil }
            selected = tint
        }
        let value = selected.value
        guard supportsColorProvider(value, depth: selected.depth, local: &local, budget: &budget) else { return nil }
        let box = value as AnyObject
        let color = unsafeBitCast(box, to: Color.self)
        guard let provider = field(color, "provider", depth: selected.depth + 1), (provider as AnyObject) === box,
              local.consume(depth: selected.depth + 2), budget.consume(depth: selected.depth + 2) else { return nil }
        var resolved = color.resolve(in: environment)
        if hierarchyPath != nil {
            let baseRGBA = [resolved.red, resolved.green, resolved.blue, resolved.opacity]
            guard baseRGBA.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  local.consume(depth: selected.depth + 2), budget.consume(depth: selected.depth + 2),
                  let secondary = SwiftUIHierarchicalColorResolver.apply(to: color, level: hierarchyLevel),
                  let provider = field(secondary, "provider", depth: selected.depth + 1),
                  String(reflecting: type(of: provider)) == "SwiftUI.ColorBox<SwiftUI.Color.HierarchicalOpacityColor>",
                  Mirror(reflecting: provider).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyColorBox",
                  let payload = field(provider, "base", depth: selected.depth + 2),
                  String(reflecting: type(of: payload)) == "SwiftUI.Color.HierarchicalOpacityColor",
                  field(payload, "level", depth: selected.depth + 3) as? Int == hierarchyLevel,
                  let original = field(payload, "base", depth: selected.depth + 3) as? Color,
                  let originalProvider = field(original, "provider", depth: selected.depth + 4),
                  (originalProvider as AnyObject) === box,
                  local.consume(depth: selected.depth + 5), budget.consume(depth: selected.depth + 5) else { return nil }
            resolved = secondary.resolve(in: environment)
        }
        withExtendedLifetime(environment) {}
        withExtendedLifetime(box) {}
        return try resolvedField(resolved, path: hierarchyPath ?? selected.path)
    }

    /// Verifies every pure-color provider before an environment or gradient stop can resolve it.
    static func supportsColorProvider(_ value: Any, depth: Int, local: inout UIKitSemanticTraversalBudget,
                                      budget: inout UIKitSemanticTraversalBudget) -> Bool {
        func field(_ value: Any, _ name: String, depth: Int) -> Any? {
            SwiftUIEnvironmentStyleReader.field(value, name, depth: depth, local: &local, budget: &budget)
        }

        // An opacity wrapper is accepted only when its entire bounded base chain is proven.
        var currentProvider = value
        var providerDepth = depth
        var seenProviders = Set<ObjectIdentifier>()
        for wrapper in 0...4 {
            let providerType = String(reflecting: type(of: currentProvider))
            guard SwiftUITextMetadataPolicy.isColorBox(providerType),
                  Mirror(reflecting: currentProvider).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyColorBox",
                  seenProviders.insert(ObjectIdentifier(currentProvider as AnyObject)).inserted else { return false }
            if providerType != "SwiftUI.ColorBox<SwiftUI.Color.OpacityColor>" { break }
            guard wrapper < 4 else { local.markTruncated(); return false }
            guard let opacityColor = field(currentProvider, "base", depth: providerDepth + 1),
                  String(reflecting: type(of: opacityColor)) == "SwiftUI.Color.OpacityColor",
                  let opacity = field(opacityColor, "opacity", depth: providerDepth + 2) as? Double,
                  opacity.isFinite, (0...1).contains(opacity),
                  let base = field(opacityColor, "base", depth: providerDepth + 2) as? Color,
                  let provider = field(base, "provider", depth: providerDepth + 3) else { return false }
            currentProvider = provider
            providerDepth += 3
        }
        return true
    }

    static func resolvedField(_ resolved: Color.Resolved, path: String) throws -> RuntimeSemanticTextField? {
        let rgba = [resolved.red, resolved.green, resolved.blue, resolved.opacity].map(Double.init)
        guard rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let attribute = RuntimeAttribute(identifier: try .init(rawValue: "common.text.color"),
            value: .color(.init(colorSpace: "srgb", red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])))
        return try RuntimeSemanticTextField(path: path, attribute: attribute)
    }
}
#endif
