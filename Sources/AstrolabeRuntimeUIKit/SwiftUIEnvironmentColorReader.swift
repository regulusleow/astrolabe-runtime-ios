#if canImport(UIKit)
import AstrolabeProtocol
import Darwin
import Foundation
import SwiftUI

/// The iOS 27.0 singleton color/font chain verified in the standalone probe.
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

        guard let plist = field(environment, "_plist", depth: 1),
              String(reflecting: type(of: plist)) == "SwiftUI.PropertyList",
              let elements = field(plist, "elements", depth: 2),
              let head = field(elements, "some", depth: 3) else { return nil }
        var element: Any = head
        var path = "environment/_plist/elements/some"
        var seen = Set<ObjectIdentifier>()

        // shortcut: only singleton FontKey/after hops are proven; reject merged or unknown layouts.
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
                      words[2] == unsafeBitCast(Optional<Font>.self, to: UInt.self),
                      let after = field(element, "after", depth: 4 + depth),
                      Mirror(reflecting: after).displayStyle == .optional,
                      let nextElement = field(after, "some", depth: 5 + depth) else { return nil }
                element = nextElement
                path += "/after/some"
                continue
            }
            // The first foreground entry is final even when its style is unsupported or nil.
            guard SwiftUITextMetadataPolicy.isForegroundStyleKey(key),
                  words[2] == unsafeBitCast(Optional<AnyShapeStyle>.self, to: UInt.self),
                  let payload = copyWords(at: UInt(bitPattern: buffer) + 24, count: 1) else { return nil }
            let style: AnyShapeStyle? = payload.withUnsafeBytes { $0.baseAddress!.load(as: Optional<AnyShapeStyle>.self) }
            guard let style,
                  let styleStorage = field(style, "storage", depth: 7 + depth),
                  String(reflecting: type(of: styleStorage)) == "SwiftUI.AnyShapeStyle.Storage",
                  let value = field(styleStorage, "box", depth: 8 + depth),
                  SwiftUITextMetadataPolicy.isColorBox(String(reflecting: type(of: value))),
                  Mirror(reflecting: value).superclassMirror.map({ String(reflecting: $0.subjectType) }) == "SwiftUI.AnyColorBox" else { return nil }
            let box = value as AnyObject
            let color = unsafeBitCast(box, to: Color.self)
            guard let provider = field(color, "provider", depth: 9 + depth), (provider as AnyObject) === box,
                  local.consume(depth: 10 + depth), budget.consume(depth: 10 + depth) else { return nil }
            let resolved = color.resolve(in: environment)
            withExtendedLifetime(environment) {}
            withExtendedLifetime(box) {}
            let rgba = [resolved.red, resolved.green, resolved.blue, resolved.opacity].map(Double.init)
            guard rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
            let attribute = RuntimeAttribute(identifier: try .init(rawValue: "common.text.color"),
                value: .color(.init(colorSpace: "srgb", red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])))
            return try RuntimeSemanticTextField(path: path + "/storage/0/ForegroundStyleKey/value/storage/box", attribute: attribute)
        }
        local.markTruncated()
        return nil
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
