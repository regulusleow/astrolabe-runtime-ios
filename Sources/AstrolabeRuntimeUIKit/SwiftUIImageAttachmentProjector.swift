#if canImport(UIKit)
import AstrolabeProtocol
import CoreGraphics
import SwiftUI
import UIKit

/// Freezes only the current image's proven source parameters, never a reconstructed image or cached label.
@MainActor
enum SwiftUIImageAttachmentProjector {
    struct Projection {
        /// Typed metadata from one complete original image scope.
        let attributes: [RuntimeAttribute]
        /// Reasons for refused metadata, without business values in paths.
        let issues: [RuntimeInspectionIssue]
        /// Whether local or shared traversal work was refused.
        let truncated: Bool
    }

    private static var supportsCurrentLayout: Bool {
        #if arch(arm64) && targetEnvironment(simulator)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SwiftUIImageMetadataPolicy.supportsLayout(major: version.majorVersion, minor: version.minorVersion, simulator: true)
        #else
        return false
        #endif
    }

    static func project(node: NSObject, budget: inout UIKitSemanticTraversalBudget, outputBytes: inout Int) throws -> Projection {
        var local = UIKitSemanticTraversalBudget(maxDepth: SwiftUIImageMetadataPolicy.maximumDepth, maxVisits: 1_500)
        func refused(_ code: String, path: String = "attachmentsStorage") -> Projection {
            Projection(attributes: [], issues: [semanticIssue("image." + code, path: path)], truncated: local.truncated || budget.truncated)
        }
        guard supportsCurrentLayout, NSStringFromClass(Swift.type(of: node)) == "SwiftUI.AccessibilityNode" else { return refused("unsupportedLayout") }
        func children(_ value: Any, depth: Int) -> [Mirror.Child]? {
            guard local.consume(depth: depth), budget.consume(depth: depth) else { return nil }
            let values = Array(Mirror(reflecting: value).children.prefix(51))
            guard values.count <= 50 else { local.markTruncated(); return nil }
            return values
        }
        func fields(_ value: Any, names: Set<String>, depth: Int) -> [String: Any]? {
            guard let values = children(value, depth: depth), values.count == names.count,
                  Set(values.compactMap(\.label)) == names else { return nil }
            return Dictionary(uniqueKeysWithValues: values.map { ($0.label!, $0.value) })
        }
        func type(_ value: Any) -> String { String(reflecting: Swift.type(of: value)) }
        func emptyOptional(_ value: Any, type expected: String, depth: Int) -> Bool {
            type(value) == expected && children(value, depth: depth)?.isEmpty == true
        }
        guard let root = children(node, depth: 0),
              let environment = root.first(where: { $0.label == "environment" })?.value as? EnvironmentValues,
              let storage = root.first(where: { $0.label == "attachmentsStorage" })?.value,
              type(storage) == "Swift.Array<SwiftUI.AccessibilityNodeAttachmentStorage>",
              let attachments = children(storage, depth: 1) else { return refused("unsupportedLayout") }
        var counts: [Int] = []
        var selected: (image: Image, path: String)?
        for (index, attachment) in attachments.enumerated() {
            guard type(attachment.value) == "SwiftUI.AccessibilityNodeAttachmentStorage",
                  let entry = fields(attachment.value, names: ["modified", "token", "attachment", "geometry"], depth: 2),
                  type(entry["attachment"]!) == "SwiftUI.AccessibilityAttachment",
                  let contents = fields(entry["attachment"]!, names: ["properties", "platformElement"], depth: 3),
                  type(contents["properties"]!) == "SwiftUI.AccessibilityProperties",
                  let properties = fields(contents["properties"]!, names: ["storage"], depth: 4) else { return refused("unsupportedLayout") }
            let entriesType = type(properties["storage"]!)
            guard entriesType.hasPrefix("Swift.Array<"), entriesType.hasSuffix(">"),
                  SwiftUIImageMetadataPolicy.privateType(String(entriesType.dropFirst("Swift.Array<".count).dropLast()), prefix: "SwiftUI.AccessibilityProperties.", suffix: "Entry"),
                  let values = children(properties["storage"]!, depth: 5) else { return refused("unsupportedLayout") }
            for (slot, value) in values.enumerated() {
                guard SwiftUIImageMetadataPolicy.privateType(type(value.value), prefix: "SwiftUI.AccessibilityProperties.", suffix: "Entry"),
                      let property = fields(value.value, names: ["key", "value"], depth: 6) else { return refused("unsupportedLayout") }
                guard type(property["key"]!) == "SwiftUI.AccessibilityProperties.ImagesKey.Type" else { continue }
                guard type(property["value"]!) == "Swift.Array<SwiftUI.Image>", let images = property["value"]! as? [Image],
                      local.consume(depth: 7), budget.consume(depth: 7) else { return refused("unsupportedLayout") }
                counts.append(images.count)
                guard SwiftUIImageMetadataPolicy.isSingleOriginalImage(counts), let image = images.first else { return refused("ambiguousSource") }
                selected = (image, "attachmentsStorage/\(index)/attachment/properties/storage/\(slot)/value/0")
            }
        }
        guard SwiftUIImageMetadataPolicy.isSingleOriginalImage(counts), let selected else { return refused("sourceUnavailable") }

        func symbolMode(_ mode: SymbolRenderingMode?, depth: Int) -> RuntimeJSONValue? {
            guard let mode else { return .null }
            guard let value = fields(mode, names: ["storage"], depth: depth)?["storage"],
                  type(value) == "SwiftUI.SymbolRenderingMode.Storage",
                  children(value, depth: depth + 1)?.isEmpty == true else { return nil }
            let name = String(describing: value)
            return ["monochrome", "hierarchical", "palette", "multicolor"].contains(name) ? .string(name) : nil
        }
        func insets(_ values: [Double], names: [String]) -> RuntimeJSONValue? {
            guard SwiftUIImageMetadataPolicy.validInsets(values) else { return nil }
            return .object(Dictionary(uniqueKeysWithValues: zip(names, values.map(RuntimeJSONValue.number))))
        }
        func pixels(_ image: CGImage) -> RuntimeJSONValue? {
            let width = Double(image.width), height = Double(image.height)
            guard width > 0, height > 0, SwiftUIImageMetadataPolicy.validSize(width: width, height: height, scale: 1) else { return nil }
            return .object(["width": .number(width), "height": .number(height), "unit": .string("pixel")])
        }
        func orientation(_ value: Image.Orientation) -> String? {
            switch value {
            case .up: return "up"
            case .down: return "down"
            case .left: return "left"
            case .right: return "right"
            case .upMirrored: return "upMirrored"
            case .downMirrored: return "downMirrored"
            case .leftMirrored: return "leftMirrored"
            case .rightMirrored: return "rightMirrored"
            @unknown default: return nil
            }
        }
        var current = selected.image
        var modifiers: [RuntimeJSONValue] = []
        var source: [String: RuntimeJSONValue]?
        var seen = Set<ObjectIdentifier>()
        for wrapper in 0...SwiftUIImageMetadataPolicy.maximumWrappers {
            let depth = 8 + wrapper * 3
            guard let provider = fields(current, names: ["provider"], depth: depth)?["provider"],
                  let kind = SwiftUIImageMetadataPolicy.providerKind(type(provider)),
                  Mirror(reflecting: provider).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyImageProviderBox",
                  seen.insert(ObjectIdentifier(provider as AnyObject)).inserted,
                  let base = fields(provider, names: ["base"], depth: depth + 1)?["base"] else { return refused("unsupportedLayout", path: selected.path) }
            switch kind {
            case .named:
                guard type(base) == "SwiftUI.Image.NamedImageProvider",
                      let value = fields(base, names: ["name", "value", "location", "backupLocation", "label", "decorative"], depth: depth + 2),
                      let name = value["name"] as? String, !name.isEmpty, name.utf8.count <= 16_384,
                      let decorative = value["decorative"] as? Bool,
                      emptyOptional(value["backupLocation"]!, type: "Swift.Optional<SwiftUI.Image.Location>", depth: depth + 3),
                      type(value["value"]!) == "Swift.Optional<Swift.Float>", let variable = children(value["value"]!, depth: depth + 3), variable.count <= 1,
                      type(value["location"]!) == "SwiftUI.Image.Location", let location = children(value["location"]!, depth: depth + 3) else { return refused("unsupportedLayout", path: selected.path) }
                var data: [String: RuntimeJSONValue] = ["name": .string(name), "decorative": .boolean(decorative)]
                if location.isEmpty && String(describing: value["location"]!) == "system" { data["kind"] = .string("systemSymbol") }
                else if location.count == 1, location[0].label == "bundle", let bundle = location[0].value as? Bundle {
                    data["kind"] = .string("namedResource")
                    if let identifier = bundle.bundleIdentifier {
                        guard identifier.utf8.count <= 16_384 else { return refused("invalidValue") }
                        data["bundleIdentifier"] = .string(identifier)
                    }
                } else { return refused("unsupportedLayout", path: selected.path) }
                if let value = variable.first {
                    guard value.label == "some", let value = value.value as? Float, value.isFinite, (0...1).contains(value) else { return refused("invalidValue", path: selected.path) }
                    data["variableValue"] = .number(Double(value))
                }
                source = data
            case .uiImage:
                guard let image = base as? UIImage, local.consume(depth: depth + 2), budget.consume(depth: depth + 2),
                      SwiftUIImageMetadataPolicy.validSize(width: image.size.width, height: image.size.height, scale: image.scale),
                      let caps = insets([image.capInsets.top, image.capInsets.left, image.capInsets.bottom, image.capInsets.right], names: ["top", "left", "bottom", "right"]) else { return refused("invalidValue", path: selected.path) }
                let rendering: String
                switch image.renderingMode {
                case .automatic: rendering = "automatic"
                case .alwaysOriginal: rendering = "original"
                case .alwaysTemplate: rendering = "template"
                @unknown default: return refused("unsupportedLayout")
                }
                let resizing: String
                switch image.resizingMode {
                case .tile: resizing = "tile"
                case .stretch: resizing = "stretch"
                @unknown default: return refused("unsupportedLayout")
                }
                var data: [String: RuntimeJSONValue] = ["kind": .string("uiImage"), "pointSize": .object(["width": .number(image.size.width), "height": .number(image.size.height), "unit": .string("logical")]),
                    "scale": .number(image.scale), "renderingMode": .string(rendering), "resizingMode": .string(resizing), "capInsets": caps, "isSymbolImage": .boolean(image.isSymbolImage), "orientationRawValue": .number(Double(image.imageOrientation.rawValue))]
                if let cgImage = image.cgImage {
                    guard let size = pixels(cgImage) else { return refused("invalidValue") }
                    data["pixelSize"] = size
                }
                source = data
            case .cgImage:
                guard let value = fields(base, names: ["image", "scale", "orientation", "label", "decorative"], depth: depth + 2),
                      let scale = value["scale"] as? CGFloat, let direction = value["orientation"] as? Image.Orientation,
                      let direction = orientation(direction), let decorative = value["decorative"] as? Bool,
                      type(value["image"]!) == "__NSCFType", CFGetTypeID(value["image"]! as AnyObject) == CGImage.typeID,
                      local.consume(depth: depth + 3), budget.consume(depth: depth + 3) else { return refused("unsupportedLayout", path: selected.path) }
                let image = unsafeBitCast(value["image"]! as AnyObject, to: CGImage.self)
                guard SwiftUIImageMetadataPolicy.validSize(width: Double(image.width), height: Double(image.height), scale: scale),
                      let size = pixels(image) else { return refused("invalidValue", path: selected.path) }
                source = ["kind": .string("cgImage"), "pixelSize": size, "scale": .number(scale), "orientation": .string(direction), "decorative": .boolean(decorative)]
            case .renderingMode, .resizable, .symbolOptions:
                guard SwiftUIImageMetadataPolicy.validWrapperCount(wrapper + 1) else { local.markTruncated(); return refused("wrapperLimit", path: selected.path) }
                let names: Set<String> = kind == .renderingMode ? ["base", "renderingMode"] : kind == .resizable ? ["base", "capInsets", "resizingMode"] : ["base", "options", "properties"]
                guard let value = fields(base, names: names, depth: depth + 2), let image = value["base"] as? Image else { return refused("unsupportedLayout", path: selected.path) }
                var modifier: [String: RuntimeJSONValue]
                if kind == .renderingMode {
                    guard let mode = value["renderingMode"]! as? Image.TemplateRenderingMode? else { return refused("unsupportedLayout") }
                    let encoded: RuntimeJSONValue
                    if let mode {
                        switch mode {
                        case .template: encoded = .string("template")
                        case .original: encoded = .string("original")
                        @unknown default: return refused("unsupportedLayout")
                        }
                    } else { encoded = .null }
                    modifier = ["kind": .string("renderingMode"), "value": encoded]
                } else if kind == .resizable {
                    guard let edges = value["capInsets"] as? EdgeInsets, let mode = value["resizingMode"] as? Image.ResizingMode,
                          let caps = insets([edges.top, edges.leading, edges.bottom, edges.trailing], names: ["top", "leading", "bottom", "trailing"]) else { return refused("invalidValue") }
                    let resizing: String
                    switch mode {
                    case .stretch: resizing = "stretch"
                    case .tile: resizing = "tile"
                    @unknown default: return refused("unsupportedLayout")
                    }
                    modifier = ["kind": .string("resizable"), "mode": .string(resizing), "capInsets": caps]
                } else {
                    guard type(value["options"]!) == "SwiftUI.SymbolRenderingOptions",
                          let options = fields(value["options"]!, names: ["renderingMode", "variableValueMode", "colorMode"], depth: depth + 3),
                          type(value["properties"]!) == type(base) + ".Properties",
                          let properties = fields(value["properties"]!, names: ["rawValue"], depth: depth + 3), properties["rawValue"] as? UInt8 == 1,
                          emptyOptional(options["variableValueMode"]!, type: "Swift.Optional<SwiftUI.SymbolVariableValueMode>", depth: depth + 4),
                          emptyOptional(options["colorMode"]!, type: "Swift.Optional<SwiftUI.SymbolColorRenderingMode>", depth: depth + 4),
                          let mode = options["renderingMode"]! as? SymbolRenderingMode?, let mode = symbolMode(mode, depth: depth + 4) else { return refused("unsupportedLayout") }
                    modifier = ["kind": .string("symbolRenderingMode"), "value": mode]
                }
                modifiers.append(.object(modifier))
                current = image
            }
            if source != nil { break }
        }
        let imageScale: String
        switch environment.imageScale {
        case .small: imageScale = "small"
        case .medium: imageScale = "medium"
        case .large: imageScale = "large"
        @unknown default: return refused("unsupportedLayout")
        }
        guard let source, let mode = symbolMode(environment.symbolRenderingMode, depth: 1), !local.truncated, !budget.truncated else { return refused("unsupportedLayout", path: selected.path) }
        let attribute = RuntimeAttribute(identifier: try .init(rawValue: "ios.swiftui.image.metadata"), value: .object([
            "source": .object(source), "modifiers": .array(modifiers),
            "environment": .object(["imageScale": .string(imageScale), "symbolRenderingMode": mode]),
            "provenance": .object(["source": .string("ios.swiftui.attachmentsStorage"), "path": .string(selected.path)])]))
        let bytes = try JSONEncoder().encode(attribute).count
        guard outputBytes + bytes <= 4 * 1024 * 1024 else { local.markTruncated(); return refused("outputBudgetExceeded") }
        outputBytes += bytes
        return Projection(attributes: [attribute], issues: [], truncated: false)
    }
}
#endif
