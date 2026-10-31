#if canImport(UIKit)
import AstrolabeProtocol
import Darwin
import Foundation
import SwiftUI

/// The iOS 27.0 singleton color/font/tint chain verified in the standalone probe.
@available(iOS 17.0, *)
@MainActor
enum SwiftUIEnvironmentColorReader {
    static func read(environment: EnvironmentValues, local: inout UIKitSemanticTraversalBudget,
                     budget: inout UIKitSemanticTraversalBudget) throws -> RuntimeSemanticTextField? {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion == 27, version.minorVersion == 0,
              MemoryLayout<UInt>.size == 8, MemoryLayout<AnyShapeStyle>.size == 8,
              MemoryLayout<Color>.size == MemoryLayout<AnyObject>.size else { return nil }

        func field(_ value: Any, _ name: String, depth: Int) -> Any? {
            guard local.consume(depth: depth), budget.consume(depth: depth) else { return nil }
            let children = Array(Mirror(reflecting: value).children.prefix(51))
            guard children.count <= 50 else { local.markTruncated(); return nil }
            let matches = children.filter { $0.label == name }
            return matches.count == 1 ? matches[0].value : nil
        }

        func unboxStyle(_ style: AnyShapeStyle, path: String, depth: Int) -> (value: Any, path: String, depth: Int)? {
            guard let storage = field(style, "storage", depth: depth + 1),
                  String(reflecting: type(of: storage)) == "SwiftUI.AnyShapeStyle.Storage",
                  let value = field(storage, "box", depth: depth + 2) else { return nil }
            return (value, path + "/storage/box", depth + 2)
        }

        func styleBox(tint: Bool) -> (value: Any, path: String, depth: Int)? {
            guard let plist = field(environment, "_plist", depth: 1),
                  String(reflecting: type(of: plist)) == "SwiftUI.PropertyList",
                  let elements = field(plist, "elements", depth: 2),
                  let head = field(elements, "some", depth: 3) else { return nil }
            var element: Any = head
            var path = "environment/_plist/elements/some"
            var seen = Set<ObjectIdentifier>()

            // shortcut: only singleton Font/ForegroundStyle/Tint after hops are proven; reject other layouts until verified.
            for hop in 0..<8 {
                let depth = hop * 2
                guard local.consume(depth: 3 + depth), budget.consume(depth: 3 + depth),
                      String(reflecting: type(of: element)) == "SwiftUI.PropertyList.Element",
                      seen.insert(ObjectIdentifier(element as AnyObject)).inserted,
                      let before = field(element, "before", depth: 4 + depth),
                      Mirror(reflecting: before).displayStyle == .optional,
                      Mirror(reflecting: before).children.isEmpty,
                      let storage = field(element, "storage", depth: 4 + depth),
                      let count = field(storage, "_count", depth: 5 + depth) as? UInt32, count == 1,
                      let next = field(storage, "nextOffset", depth: 5 + depth) as? UInt16, next == 32,
                      let capacity = field(storage, "_capacity", depth: 5 + depth) as? UInt32, capacity >= UInt32(next),
                      let last = field(storage, "lastOffset", depth: 5 + depth) as? UInt16, last == 0,
                      let mask = field(storage, "alignMask", depth: 5 + depth) as? UInt16, mask == 7,
                      let buffer = field(storage, "buf", depth: 5 + depth) as? UnsafeMutableRawPointer,
                      UInt(bitPattern: buffer) % 8 == 0, UInt(bitPattern: buffer) <= UInt.max - 32,
                      local.consume(depth: 6 + depth), budget.consume(depth: 6 + depth),
                      let words = copyWords(at: UInt(bitPattern: buffer), count: 3),
                      words[0] != 0, words[0] % 8 == 0,
                      copyWords(at: words[0], count: 1) != nil else { return nil }

                // Metadata comes from the retained SwiftUI-owned singleton, not an arbitrary heap scan.
                let key = String(reflecting: unsafeBitCast(words[0], to: Any.Type.self))
                if SwiftUITextMetadataPolicy.isFontKey(key) {
                    guard MemoryLayout<Font?>.size == 8,
                          words[2] == unsafeBitCast(Optional<Font>.self, to: UInt.self) else { return nil }
                } else {
                    let isForeground = SwiftUITextMetadataPolicy.isForegroundStyleKey(key)
                    let isTint = SwiftUITextMetadataPolicy.isTintKey(key)
                    guard isForeground || isTint,
                          words[2] == unsafeBitCast(Optional<AnyShapeStyle>.self, to: UInt.self) else { return nil }
                    if tint ? isTint : isForeground {
                        // The first matching entry is final, including nil or unsupported styles.
                        guard let payload = copyWords(at: UInt(bitPattern: buffer) + 24, count: 1) else { return nil }
                        let style: AnyShapeStyle? = payload.withUnsafeBytes { $0.baseAddress!.load(as: Optional<AnyShapeStyle>.self) }
                        guard let style else { return nil }
                        return unboxStyle(style, path: path + "/storage/0/" + (tint ? "TintKey" : "ForegroundStyleKey") + "/value", depth: 6 + depth)
                    }
                }
                guard let after = field(element, "after", depth: 4 + depth),
                      Mirror(reflecting: after).displayStyle == .optional,
                      let nextElement = field(after, "some", depth: 5 + depth) else { return nil }
                element = nextElement
                path += "/after/some"
            }
            local.markTruncated()
            return nil
        }

        guard var selected = styleBox(tint: false) else { return nil }
        var secondaryPath: String?
        let selectedType = String(reflecting: type(of: selected.value))
        if SwiftUITextMetadataPolicy.isSecondaryOffsetBox(selectedType) {
            let path = selected.path
            let depth = selected.depth
            guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  let offset = field(selected.value, "base", depth: depth + 1),
                  String(reflecting: type(of: offset)) == "SwiftUI.OffsetShapeStyle<SwiftUI.AnyShapeStyle>",
                  field(offset, "offset", depth: depth + 2) as? Int == 1,
                  let base = field(offset, "base", depth: depth + 2) as? AnyShapeStyle,
                  let box = unboxStyle(base, path: path + "/base/base", depth: depth + 2) else { return nil }
            selected = box
            secondaryPath = path
            if SwiftUITextMetadataPolicy.isSecondaryPackBox(String(reflecting: type(of: selected.value))) {
                guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                      let pack = field(selected.value, "base", depth: selected.depth + 1),
                      ["SwiftUI.ShapeStylePair<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>",
                       "SwiftUI.ShapeStyleTriple<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>"].contains(String(reflecting: type(of: pack))),
                      let secondary = field(pack, "secondary", depth: selected.depth + 2) as? AnyShapeStyle,
                      let box = unboxStyle(secondary, path: selected.path + "/base/secondary", depth: selected.depth + 2) else { return nil }
                selected = box
                secondaryPath = nil
            }
        } else if SwiftUITextMetadataPolicy.isSecondaryModifierBox(selectedType) {
            let path = selected.path
            let depth = selected.depth
            guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  let modifier = field(selected.value, "base", depth: depth + 1),
                  String(reflecting: type(of: modifier)) == "SwiftUI.HierarchicalShapeStyleModifier<SwiftUI.Color>",
                  field(modifier, "level", depth: depth + 2) as? Int == 1,
                  let color = field(modifier, "base", depth: depth + 2) as? Color,
                  let provider = field(color, "provider", depth: depth + 3) else { return nil }
            selected = (provider, path + "/base/base/provider", depth + 3)
            secondaryPath = path
        }
        if SwiftUITextMetadataPolicy.isTintStyleBox(String(reflecting: type(of: selected.value))) {
            guard Mirror(reflecting: selected.value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyShapeStyleBox",
                  field(selected.value, "base", depth: selected.depth + 1) is TintShapeStyle,
                  let tint = styleBox(tint: true) else { return nil }
            selected = tint
        }
        let value = selected.value
        // An opacity wrapper is accepted only when its entire bounded base chain is proven.
        var currentProvider = value
        var providerDepth = selected.depth
        var seenProviders = Set<ObjectIdentifier>()
        for wrapper in 0...4 {
            let providerType = String(reflecting: type(of: currentProvider))
            guard SwiftUITextMetadataPolicy.isColorBox(providerType),
                  Mirror(reflecting: currentProvider).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyColorBox",
                  seenProviders.insert(ObjectIdentifier(currentProvider as AnyObject)).inserted else { return nil }
            if providerType != "SwiftUI.ColorBox<SwiftUI.Color.OpacityColor>" { break }
            guard wrapper < 4 else { local.markTruncated(); return nil }
            guard let opacityColor = field(currentProvider, "base", depth: providerDepth + 1),
                  String(reflecting: type(of: opacityColor)) == "SwiftUI.Color.OpacityColor",
                  let opacity = field(opacityColor, "opacity", depth: providerDepth + 2) as? Double,
                  opacity.isFinite, (0...1).contains(opacity),
                  let base = field(opacityColor, "base", depth: providerDepth + 2) as? Color,
                  let provider = field(base, "provider", depth: providerDepth + 3) else { return nil }
            currentProvider = provider
            providerDepth += 3
        }
        let box = value as AnyObject
        let color = unsafeBitCast(box, to: Color.self)
        guard let provider = field(color, "provider", depth: selected.depth + 1), (provider as AnyObject) === box,
              local.consume(depth: selected.depth + 2), budget.consume(depth: selected.depth + 2) else { return nil }
        var resolved = color.resolve(in: environment)
        if secondaryPath != nil {
            let baseRGBA = [resolved.red, resolved.green, resolved.blue, resolved.opacity]
            guard baseRGBA.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  local.consume(depth: selected.depth + 2), budget.consume(depth: selected.depth + 2),
                  let secondary = SwiftUISecondaryColorResolver.apply(to: color),
                  let provider = field(secondary, "provider", depth: selected.depth + 1),
                  String(reflecting: type(of: provider)) == "SwiftUI.ColorBox<SwiftUI.Color.HierarchicalOpacityColor>",
                  Mirror(reflecting: provider).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyColorBox",
                  let payload = field(provider, "base", depth: selected.depth + 2),
                  String(reflecting: type(of: payload)) == "SwiftUI.Color.HierarchicalOpacityColor",
                  field(payload, "level", depth: selected.depth + 3) as? Int == 1,
                  let original = field(payload, "base", depth: selected.depth + 3) as? Color,
                  let originalProvider = field(original, "provider", depth: selected.depth + 4),
                  (originalProvider as AnyObject) === box,
                  local.consume(depth: selected.depth + 5), budget.consume(depth: selected.depth + 5) else { return nil }
            resolved = secondary.resolve(in: environment)
        }
        withExtendedLifetime(environment) {}
        withExtendedLifetime(box) {}
        let rgba = [resolved.red, resolved.green, resolved.blue, resolved.opacity].map(Double.init)
        guard rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let attribute = RuntimeAttribute(identifier: try .init(rawValue: "common.text.color"),
            value: .color(.init(colorSpace: "srgb", red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])))
        return try RuntimeSemanticTextField(path: secondaryPath ?? selected.path, attribute: attribute)
    }

    private static func copyWords(at address: UInt, count: Int) -> [UInt]? {
        guard address != 0, address % 8 == 0, count > 0, count <= 4 else { return nil }
        var words = [UInt](repeating: 0, count: count)
        var copied: vm_size_t = 0
        let size = count * MemoryLayout<UInt>.size
        let result = words.withUnsafeMutableBytes {
            vm_read_overwrite(mach_task_self_, vm_address_t(address), vm_size_t(size),
                              vm_address_t(UInt(bitPattern: $0.baseAddress!)), &copied)
        }
        return result == KERN_SUCCESS && copied == size ? words : nil
    }
}
#endif
