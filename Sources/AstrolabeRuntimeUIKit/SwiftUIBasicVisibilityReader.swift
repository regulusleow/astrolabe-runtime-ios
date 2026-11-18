#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeObjC
import Darwin
import SwiftUI
import UIKit

/// Snapshot-local render facts. AX containment and AX visibility flags never supply render ancestry.
@MainActor
final class SwiftUIBasicVisibilityReader {
    private struct Drawing {
        /// Retained render object keeps its identity valid for this capture.
        let object: AnyObject
        /// Basic visibility derived from the actual DisplayList ancestry and native host.
        let visibility: RuntimeNodeVisibility
    }

    private struct HostIndex {
        /// Unique text drawing objects in the last rendered list.
        var drawings: [ObjectIdentifier: Drawing] = [:]
        /// Shared drawing objects cannot identify one placement.
        var ambiguous: Set<ObjectIdentifier> = []
        /// Unsupported effects or exhausted budgets invalidate the entire index.
        var complete = true
    }

    private enum ReadFailure: Error { case unsupported }

    /// Selected native window, shared with the semantic capture.
    private let window: UIWindow
    /// Indexes never survive their owning frozen capture.
    private var hosts: [ObjectIdentifier: HostIndex] = [:]
    /// Bounds work across every host and AX node in this capture.
    private var remaining = 20_000

    init(window: UIWindow) { self.window = window }

    func visibility(for node: NSObject) -> RuntimeNodeVisibility? {
        #if !arch(arm64) || targetEnvironment(macCatalyst)
        return nil
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        // shortcut: this private render layout is verified on iOS 27.0; probe new layouts before widening.
        guard !ProcessInfo.processInfo.isiOSAppOnMac, version.majorVersion == 27, version.minorVersion == 0,
              NSStringFromClass(type(of: node)) == "SwiftUI.AccessibilityNode" else { return nil }
        do {
            let fields = try children(node)
            guard let hostValue = fields.first(where: { $0.label == "viewRendererHost" })?.value,
                  let host = try optional(hostValue) as? UIView, host.window === window,
                  let attachments = fields.first(where: { $0.label == "attachmentsStorage" })?.value,
                  let drawing = try drawingObject(attachments) else { return nil }
            let hostID = ObjectIdentifier(host)
            if hosts[hostID] == nil { hosts[hostID] = makeIndex(host: host) }
            let drawingID = ObjectIdentifier(drawing)
            guard let index = hosts[hostID], index.complete, !index.ambiguous.contains(drawingID) else { return nil }
            return index.drawings[drawingID]?.visibility
        } catch { return nil }
        #endif
    }

    private func drawingObject(_ attachments: Any) throws -> AnyObject? {
        guard let responderType = _typeByName("7SwiftUI13ViewResponderC"),
              let getter = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                "$s7SwiftUI28AccessibilityGeometryStorageC13viewResponder6ofTypexSgxm_tAA04ViewG0CRbzlF") else { return nil }
        var image = Dl_info()
        var swiftUIImage = Dl_info()
        guard dladdr(getter, &image) != 0,
              dladdr(unsafeBitCast(EnvironmentValues.self, to: UnsafeRawPointer.self), &swiftUIImage) != 0,
              image.dli_fbase == swiftUIImage.dli_fbase, image.dli_saddr == getter,
              let symbol = image.dli_sname,
              String(cString: symbol) == "$s7SwiftUI28AccessibilityGeometryStorageC13viewResponder6ofTypexSgxm_tAA04ViewG0CRbzlF"
        else { return nil }
        var result: AnyObject?
        for attachment in try children(attachments, maximum: 32) {
            guard typeName(attachment.value) == "SwiftUI.AccessibilityNodeAttachmentStorage",
                  let geometryValue = try optional(field(attachment.value, "geometry")) else { continue }
            guard typeName(geometryValue) == "SwiftUI.AccessibilityGeometryStorage",
                  Mirror(reflecting: geometryValue).displayStyle == .class else { throw ReadFailure.unsupported }
            let geometry = geometryValue as AnyObject
            guard let pointer = ASTCopySwiftUIVisibilityResponder(Unmanaged.passUnretained(geometry).toOpaque(),
                getter, unsafeBitCast(responderType, to: UnsafeRawPointer.self)) else { throw ReadFailure.unsupported }
            let responder = Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue()
            guard typeName(responder) == "SwiftUI.StyledTextResponder",
                  let data = try optional(field(field(responder, "helper"), "data")) else { throw ReadFailure.unsupported }
            let view = try field(data, "view")
            let drawing = try textDrawing(view)
            if let result, result !== drawing { throw ReadFailure.unsupported }
            result = drawing
        }
        return result
    }

    private func makeIndex(host: UIView) -> HostIndex {
        var index = HostIndex()
        do {
            guard hosts.count < 64 else { throw ReadFailure.unsupported }
            let base = try field(host, "_base")
            guard typeName(base) == "UIKit.UIHostingViewBase" else { throw ReadFailure.unsupported }
            let graph = try field(base, "viewGraph")
            let renderer = try field(graph, "renderer")
            guard let updater = try optional(field(renderer, "renderer")),
                  try field(updater, "isValid") as? Bool == true else { throw ReadFailure.unsupported }
            let list = try field(updater, "lastList")
            let viewport = window.screen.coordinateSpace.bounds
            var clip = viewport
            var opacity = 1.0
            var hidden = false
            var current: UIView? = host
            var ancestors = 0
            while let view = current {
                ancestors += 1
                guard ancestors <= 64, view.alpha.isFinite, (0...1).contains(view.alpha) else { throw ReadFailure.unsupported }
                hidden = hidden || view.isHidden
                opacity *= Double(view.alpha)
                if view.clipsToBounds {
                    let rect = screenRect(view.bounds, from: view)
                    guard finite(rect) else { throw ReadFailure.unsupported }
                    clip = clip.intersection(rect)
                }
                current = view.superview
            }
            try walk(list, host: host, origin: .zero, opacity: opacity, clip: clip,
                     hidden: hidden, depth: 0, index: &index)
        } catch { index.complete = false; index.drawings.removeAll() }
        return index
    }

    private func walk(_ list: Any, host: UIView, origin: CGPoint, opacity: Double,
                      clip: CGRect, hidden: Bool, depth: Int, index: inout HostIndex) throws {
        guard depth < 48, typeName(list) == "SwiftUI.DisplayList" else { throw ReadFailure.unsupported }
        for item in try children(field(list, "items"), maximum: 2_000) {
            guard typeName(item.value) == "SwiftUI.DisplayList.Item",
                  let frame = try field(item.value, "frame") as? CGRect, finite(frame) else { throw ReadFailure.unsupported }
            let position = CGPoint(x: origin.x + frame.minX, y: origin.y + frame.minY)
            guard position.x.isFinite, position.y.isFinite else { throw ReadFailure.unsupported }
            let value = try field(item.value, "value")
            let cases = try children(value, maximum: 1)
            guard let entry = cases.first else { throw ReadFailure.unsupported }
            if entry.label == "effect" {
                let effect = try field(entry.value, ".0")
                let nested = try field(entry.value, ".1")
                let effects = try children(effect, maximum: 1)
                var nextOpacity = opacity
                var nextClip = clip
                var nextHidden = hidden
                if let effectCase = effects.first {
                    switch effectCase.label {
                    case "opacity":
                        guard let alpha = effectCase.value as? Float, alpha.isFinite, (0...1).contains(alpha) else { throw ReadFailure.unsupported }
                        nextOpacity *= Double(alpha)
                    case "clip":
                        guard let path = try field(effectCase.value, ".0") as? Path,
                              let options = try field(effectCase.value, ".2") as? GraphicsContext.ClipOptions,
                              options.isEmpty,
                              let rect = try children(field(path, "storage"), maximum: 1).first,
                              rect.label == "rect", let bounds = rect.value as? CGRect, finite(bounds) else { throw ReadFailure.unsupported }
                        let clipRect = screenRect(bounds.offsetBy(dx: position.x, dy: position.y), from: host)
                        guard finite(clipRect) else { throw ReadFailure.unsupported }
                        nextClip = clip.intersection(clipRect)
                    case "platformGroup":
                        guard let container = effectCase.value as? UIView,
                              typeName(container) == "SwiftUI.HostingScrollView.PlatformContainer",
                              container.window === window,
                              container.subviews.count == 1, let scroll = container.subviews.first as? UIScrollView,
                              typeName(scroll) == "SwiftUI.HostingScrollView",
                              scroll.subviews.count < 32 else { throw ReadFailure.unsupported }
                        let groups = scroll.subviews.filter { typeName($0) == "SwiftUI.HostingScrollView.PlatformGroupContainer" }
                        guard groups.count == 1, let group = groups.first else { throw ReadFailure.unsupported }
                        var groupHidden = hidden
                        for view in [container, scroll, group] {
                            // Native effect alpha may duplicate a DisplayList opacity; only the verified neutral path is accepted.
                            guard view.alpha == 1 else { throw ReadFailure.unsupported }
                            groupHidden = groupHidden || view.isHidden
                            if view.clipsToBounds {
                                let bounds = screenRect(view.bounds, from: view)
                                guard finite(bounds) else { throw ReadFailure.unsupported }
                                nextClip = nextClip.intersection(bounds)
                            }
                        }
                        // The nested list belongs to the actual content view, whose conversion includes contentOffset.
                        try walk(nested, host: group, origin: .zero, opacity: opacity, clip: nextClip,
                                 hidden: groupHidden, depth: depth + 1, index: &index)
                        continue
                    case "properties":
                        // Verified native flags: ignoresEvents (2), hiddenForReuse (256).
                        guard let bits = try field(effectCase.value, "rawValue") as? UInt32,
                              bits & ~UInt32(2 | 256) == 0 else { throw ReadFailure.unsupported }
                        nextHidden = nextHidden || bits & 256 != 0
                    default: throw ReadFailure.unsupported
                    }
                } else {
                    guard typeName(effect) == "SwiftUI.DisplayList.Effect",
                          String(describing: effect) == "identity" else { throw ReadFailure.unsupported }
                }
                try walk(nested, host: host, origin: position, opacity: nextOpacity, clip: nextClip,
                         hidden: nextHidden, depth: depth + 1, index: &index)
            } else if entry.label == "content" {
                let content = try children(field(entry.value, "value"), maximum: 1)
                guard let contentCase = content.first else { throw ReadFailure.unsupported }
                guard contentCase.label == "text" else { continue }
                let drawing = try textDrawing(field(contentCase.value, ".0"))
                let rect = screenRect(CGRect(origin: position, size: frame.size), from: host)
                guard finite(rect) else { throw ReadFailure.unsupported }
                let intersects = window.screen.coordinateSpace.bounds.intersects(rect)
                let intersection = clip.intersection(rect)
                let clipped = intersects && (intersection.isNull || intersection.isEmpty)
                let visibility = try RuntimeNodeVisibility(hidden: false, hiddenByAncestor: hidden,
                    opacity: 1, effectiveOpacity: opacity, intersectsViewport: intersects,
                    fullyClippedByAncestor: clipped, onscreen: !hidden && opacity > 0.01 && intersects && !clipped)
                let id = ObjectIdentifier(drawing)
                if index.drawings[id] != nil { index.ambiguous.insert(id) }
                index.drawings[id] = Drawing(object: drawing, visibility: visibility)
            } else { throw ReadFailure.unsupported }
        }
    }

    private func textDrawing(_ view: Any) throws -> AnyObject {
        guard typeName(view) == "SwiftUI.StyledTextContentView",
              try optional(field(view, "renderer")) == nil else { throw ReadFailure.unsupported }
        let text = try field(view, "text")
        guard typeName(text) == "SwiftUI.ResolvedStyledText.StringDrawing",
              Mirror(reflecting: text).displayStyle == .class else { throw ReadFailure.unsupported }
        return text as AnyObject
    }

    private func children(_ value: Any, maximum: Int = 50) throws -> [Mirror.Child] {
        guard remaining > 0 else { throw ReadFailure.unsupported }
        let result = Array(Mirror(reflecting: value).children.prefix(min(maximum, remaining) + 1))
        guard result.count <= maximum, result.count < remaining else { remaining = 0; throw ReadFailure.unsupported }
        remaining -= result.count + 1
        return result
    }

    private func field(_ value: Any, _ name: String) throws -> Any {
        var mirror: Mirror? = Mirror(reflecting: value)
        for _ in 0..<8 {
            guard let level = mirror else { break }
            for child in level.children.prefix(50) {
                guard remaining > 0 else { throw ReadFailure.unsupported }
                remaining -= 1
                if child.label == name { return child.value }
            }
            mirror = level.superclassMirror
        }
        throw ReadFailure.unsupported
    }

    private func optional(_ value: Any) throws -> Any? {
        guard Mirror(reflecting: value).displayStyle == .optional else { throw ReadFailure.unsupported }
        return try children(value, maximum: 1).first?.value
    }

    private func typeName(_ value: Any) -> String { String(reflecting: type(of: value)) }

    private func finite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite &&
            rect.width >= 0 && rect.height >= 0 && rect.maxX.isFinite && rect.maxY.isFinite
    }

    private func screenRect(_ rect: CGRect, from host: UIView) -> CGRect {
        window.convert(host.convert(rect, to: window), to: window.screen.coordinateSpace)
    }
}
#endif
