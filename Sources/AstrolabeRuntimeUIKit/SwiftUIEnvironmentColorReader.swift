#if canImport(UIKit)
import AstrolabeProtocol
import Darwin
import Foundation
import SwiftUI

/// The iOS 27.0 singleton environment layout verified in the standalone probe.
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

        // shortcut: only a singleton head is proven; validate lookup order before reading deeper/merged storage.
        guard let plist = field(environment, "_plist", depth: 1),
              String(reflecting: type(of: plist)) == "SwiftUI.PropertyList",
              let elements = field(plist, "elements", depth: 2),
              let head = field(elements, "some", depth: 3),
              String(reflecting: type(of: head)) == "SwiftUI.PropertyList.Element",
              let before = field(head, "before", depth: 4),
              Mirror(reflecting: before).displayStyle == .optional,
              Mirror(reflecting: before).children.isEmpty,
              let storage = field(head, "storage", depth: 4),
              let count = field(storage, "_count", depth: 5) as? UInt32, count == 1,
              let next = field(storage, "nextOffset", depth: 5) as? UInt16, next == 32,
              let capacity = field(storage, "_capacity", depth: 5) as? UInt32, capacity >= UInt32(next),
              let last = field(storage, "lastOffset", depth: 5) as? UInt16, last == 0,
              let mask = field(storage, "alignMask", depth: 5) as? UInt16, mask == 7,
              let buffer = field(storage, "buf", depth: 5) as? UnsafeMutableRawPointer,
              UInt(bitPattern: buffer) % 8 == 0,
              local.consume(depth: 6), budget.consume(depth: 6),
              let words = copyWords(at: UInt(bitPattern: buffer), count: 4),
              words[2] == unsafeBitCast(Optional<AnyShapeStyle>.self, to: UInt.self),
              words[0] != 0, words[0] % 8 == 0,
              copyWords(at: words[0], count: 1) != nil else { return nil }

        // Metadata comes from the retained SwiftUI-owned singleton, not an arbitrary heap scan.
        let key = unsafeBitCast(words[0], to: Any.Type.self)
        guard SwiftUITextMetadataPolicy.isForegroundStyleKey(String(reflecting: key)) else { return nil }
        let style: AnyShapeStyle? = words.withUnsafeBytes {
            $0.baseAddress!.advanced(by: 24).load(as: Optional<AnyShapeStyle>.self)
        }
        guard let style,
              let styleStorage = field(style, "storage", depth: 7),
              String(reflecting: type(of: styleStorage)) == "SwiftUI.AnyShapeStyle.Storage",
              let value = field(styleStorage, "box", depth: 8),
              String(reflecting: type(of: value)) == "SwiftUI.ColorBox<SwiftUI.SystemColorType>",
              Mirror(reflecting: value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyColorBox" else { return nil }
        let box = value as AnyObject
        let color = unsafeBitCast(box, to: Color.self)
        guard let provider = field(color, "provider", depth: 9), (provider as AnyObject) === box,
              local.consume(depth: 10), budget.consume(depth: 10) else { return nil }
        let resolved = color.resolve(in: environment)
        withExtendedLifetime(environment) {}
        withExtendedLifetime(box) {}
        let rgba = [resolved.red, resolved.green, resolved.blue, resolved.opacity].map(Double.init)
        guard rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let attribute = RuntimeAttribute(identifier: try .init(rawValue: "common.text.color"),
            value: .color(.init(colorSpace: "srgb", red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])))
        return try RuntimeSemanticTextField(path: "environment/_plist/elements/some/storage/0/ForegroundStyleKey/value/storage/box", attribute: attribute)
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
