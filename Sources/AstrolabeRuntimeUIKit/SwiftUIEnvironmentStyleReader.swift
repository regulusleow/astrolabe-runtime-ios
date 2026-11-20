#if canImport(UIKit)
import Darwin
import SwiftUI

/// Selects one current environment entry and provides bounded field access to style projectors.
@available(iOS 17.0, *)
@MainActor
enum SwiftUIEnvironmentStyleReader {
    struct Selection {
        /// SwiftUI-owned box selected from the current Text environment.
        let value: Any
        /// Provenance within that environment, containing no business values.
        let path: String
        /// Traversal depth already charged before selecting this box.
        let depth: Int
    }

    static func select(environment: EnvironmentValues, tint: Bool = false,
                       local: inout UIKitSemanticTraversalBudget, budget: inout UIKitSemanticTraversalBudget) -> Selection? {
        guard SwiftUITextMetadataPolicy.supportsCurrentLayout,
              MemoryLayout<UInt>.size == 8, MemoryLayout<AnyShapeStyle>.size == 8,
              MemoryLayout<Color>.size == MemoryLayout<AnyObject>.size else { return nil }

        func field(_ value: Any, _ name: String, depth: Int) -> Any? {
            Self.field(value, name, depth: depth, local: &local, budget: &budget)
        }
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
                    return unboxStyle(style, path: path + "/storage/0/" + (tint ? "TintKey" : "ForegroundStyleKey") + "/value", depth: 6 + depth, local: &local, budget: &budget)
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

    static func field(_ value: Any, _ name: String, depth: Int,
                      local: inout UIKitSemanticTraversalBudget, budget: inout UIKitSemanticTraversalBudget) -> Any? {
        guard local.consume(depth: depth), budget.consume(depth: depth) else { return nil }
        let children = Array(Mirror(reflecting: value).children.prefix(51))
        guard children.count <= 50 else { local.markTruncated(); return nil }
        let matches = children.filter { $0.label == name }
        return matches.count == 1 ? matches[0].value : nil
    }

    static func unboxStyle(_ style: AnyShapeStyle, path: String, depth: Int,
                           local: inout UIKitSemanticTraversalBudget, budget: inout UIKitSemanticTraversalBudget) -> Selection? {
        guard let storage = field(style, "storage", depth: depth + 1, local: &local, budget: &budget),
              String(reflecting: type(of: storage)) == "SwiftUI.AnyShapeStyle.Storage",
              let value = field(storage, "box", depth: depth + 2, local: &local, budget: &budget) else { return nil }
        return Selection(value: value, path: path + "/storage/box", depth: depth + 2)
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
