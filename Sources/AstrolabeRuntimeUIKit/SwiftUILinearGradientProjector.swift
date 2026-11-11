#if canImport(UIKit)
import AstrolabeProtocol
import SwiftUI

/// Projects the current gradient's parameters, independently of layout and pixel interpolation.
@available(iOS 17.0, *)
@MainActor
enum SwiftUILinearGradientProjector {
    /// shortcut: gradient fields are verified on iOS 27.0 arm64 simulators; validate other targets before widening.
    private static var supportsCurrentLayout: Bool {
        #if arch(arm64) && targetEnvironment(simulator)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SwiftUITextMetadataPolicy.supportsLinearGradientLayout(major: version.majorVersion,
            minor: version.minorVersion, simulator: true)
        #else
        return false
        #endif
    }

    static func project(_ selection: SwiftUIEnvironmentStyleReader.Selection, environment: EnvironmentValues,
                        local: inout UIKitSemanticTraversalBudget,
                        budget: inout UIKitSemanticTraversalBudget) throws -> RuntimeSemanticTextField? {
        guard supportsCurrentLayout else { return nil }
        func field(_ value: Any, _ name: String, depth: Int) -> Any? {
            SwiftUIEnvironmentStyleReader.field(value, name, depth: depth, local: &local, budget: &budget)
        }
        let depth = selection.depth
        guard SwiftUITextMetadataPolicy.isLinearGradientBox(String(reflecting: type(of: selection.value))),
              Mirror(reflecting: selection.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
              let base = field(selection.value, "base", depth: depth + 1) as? LinearGradient,
              let gradient = field(base, "gradient", depth: depth + 2) as? Gradient,
              let start = field(base, "startPoint", depth: depth + 2) as? UnitPoint,
              let end = field(base, "endPoint", depth: depth + 2) as? UnitPoint,
              [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else { return nil }
        let stops = gradient.stops
        guard stops.count <= SwiftUITextMetadataPolicy.maxLinearGradientStops else {
            local.markTruncated()
            return nil
        }
        var locations: [Double] = []
        for stop in stops {
            guard local.consume(depth: depth + 3), budget.consume(depth: depth + 3) else { return nil }
            locations.append(Double(stop.location))
        }
        guard SwiftUITextMetadataPolicy.validLinearGradientLocations(locations) else { return nil }
        var resolvedStops: [RuntimeJSONValue] = []
        for (index, stop) in stops.enumerated() {
            guard let provider = field(stop.color, "provider", depth: depth + 4),
                  SwiftUIEnvironmentColorReader.supportsColorProvider(provider, depth: depth + 4, local: &local, budget: &budget),
                  local.consume(depth: depth + 5), budget.consume(depth: depth + 5) else { return nil }
            let resolved = stop.color.resolve(in: environment)
            let rgba = [resolved.red, resolved.green, resolved.blue, resolved.opacity].map(Double.init)
            guard rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
            resolvedStops.append(.object([
                "location": .number(locations[index]),
                "color": .object(["colorSpace": .string("srgb"), "red": .number(rgba[0]),
                    "green": .number(rgba[1]), "blue": .number(rgba[2]), "alpha": .number(rgba[3])])
            ]))
        }
        let value: RuntimeAttributeValue = .object([
            "kind": .string("linearGradient"), "coordinateSpace": .string("unit"),
            "startPoint": .object(["x": .number(Double(start.x)), "y": .number(Double(start.y))]),
            "endPoint": .object(["x": .number(Double(end.x)), "y": .number(Double(end.y))]),
            "stops": .array(resolvedStops)
        ])
        return try RuntimeSemanticTextField(path: selection.path,
            attribute: RuntimeAttribute(identifier: try .init(rawValue: "ios.swiftui.text.foregroundStyle"), value: value))
    }
}
#endif
