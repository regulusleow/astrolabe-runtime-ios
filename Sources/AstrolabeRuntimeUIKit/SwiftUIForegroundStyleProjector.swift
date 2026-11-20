#if canImport(UIKit)
import AstrolabeProtocol
import SwiftUI

/// Dispatches proven foreground values independently of their Text or environment source.
@available(iOS 17.0, *)
@MainActor
enum SwiftUIForegroundStyleProjector {
    static func projectModifier(_ value: Any, path: String, depth: Int, environment: EnvironmentValues,
                                local: inout UIKitSemanticTraversalBudget,
                                budget: inout UIKitSemanticTraversalBudget) throws -> RuntimeSemanticTextField? {
        guard SwiftUITextMetadataPolicy.supportsCurrentLayout,
              String(reflecting: type(of: value)) == "SwiftUI.TextForegroundStyleModifier",
              local.consume(depth: depth), budget.consume(depth: depth) else { return nil }
        let fields = Array(Mirror(reflecting: value).children.prefix(2))
        guard fields.count == 1, fields[0].label == "style", let style = fields[0].value as? AnyShapeStyle,
              let selection = SwiftUIEnvironmentStyleReader.unboxStyle(style, path: path + "/style", depth: depth + 1,
                  local: &local, budget: &budget),
              let field = try project(selection, environment: environment, local: &local, budget: &budget) else { return nil }
        return try RuntimeSemanticTextField(path: selection.path, attribute: field.attribute)
    }

    static func projectEnvironment(_ environment: EnvironmentValues, local: inout UIKitSemanticTraversalBudget,
                                   budget: inout UIKitSemanticTraversalBudget) throws -> RuntimeSemanticTextField? {
        guard let selection = SwiftUIEnvironmentStyleReader.select(environment: environment, local: &local, budget: &budget) else { return nil }
        return try project(selection, environment: environment, local: &local, budget: &budget)
    }

    private static func project(_ selection: SwiftUIEnvironmentStyleReader.Selection, environment: EnvironmentValues,
                                local: inout UIKitSemanticTraversalBudget,
                                budget: inout UIKitSemanticTraversalBudget) throws -> RuntimeSemanticTextField? {
        let type = String(reflecting: type(of: selection.value))
        if SwiftUITextMetadataPolicy.isLinearGradientBox(type) {
            return try SwiftUILinearGradientProjector.project(selection, environment: environment, local: &local, budget: &budget)
        }
        if SwiftUITextMetadataPolicy.isDirectHierarchyBox(type) {
            func field(_ value: Any, _ name: String, depth: Int) -> Any? {
                SwiftUIEnvironmentStyleReader.field(value, name, depth: depth, local: &local, budget: &budget)
            }
            guard Mirror(reflecting: selection.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  let style = field(selection.value, "base", depth: selection.depth + 1) as? HierarchicalShapeStyle,
                  let id = field(style, "id", depth: selection.depth + 2) as? UInt32,
                  SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(Int(id)),
                  let parent = SwiftUIEnvironmentForegroundStyleAccess.read(environment, local: &local, budget: &budget) else { return nil }
            if let style = parent.style {
                guard let base = SwiftUIEnvironmentStyleReader.unboxStyle(style, path: "environment/foregroundStyle", depth: 1,
                          local: &local, budget: &budget) else { return nil }
                return try SwiftUIEnvironmentColorReader.read(selection: base, hierarchyLevel: Int(id), environment: environment, local: &local, budget: &budget)
            }
            guard local.consume(depth: selection.depth + 3), budget.consume(depth: selection.depth + 3),
                  let resolved = SwiftUIHierarchicalColorResolver.defaultColor(level: Int(id), environment: environment) else { return nil }
            return try SwiftUIEnvironmentColorReader.resolvedField(resolved, path: selection.path)
        }
        return try SwiftUIEnvironmentColorReader.read(selection: selection, hierarchyLevel: 0, environment: environment, local: &local, budget: &budget)
    }
}
#endif
