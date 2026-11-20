//
//  AppKitRuntimeInspectionProvider.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/11/20.
//

#if os(macOS)
import AppKit
import AstrolabeProtocol
import AstrolabeRuntimeCore

@MainActor
final class AppKitRuntimeInspectionProvider:
    RuntimeAppInfoProviding,
    RuntimeHierarchyProviding,
    RuntimeNodeDetailProviding
{
    private let targetID: RuntimeOpaqueIdentifier
    private let registry = RuntimeNodeRegistry()

    init(targetID: RuntimeOpaqueIdentifier) {
        self.targetID = targetID
    }

    func appInfo(runtime: RuntimeDescriptor) async throws -> RuntimeApplicationInfoPayload {
        guard let bundleID = Bundle.main.bundleIdentifier, let screen = NSScreen.screens.first else {
            throw unavailableTarget()
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return RuntimeApplicationInfoPayload(
            application: RuntimeApplication(
                identifier: bundleID,
                displayName: bundleString("CFBundleDisplayName") ?? bundleString("CFBundleName") ?? bundleID,
                version: bundleString("CFBundleShortVersionString"),
                buildVersion: bundleString("CFBundleVersion")
            ),
            target: RuntimeTarget(
                identifier: runtime.instanceID,
                processIdentifier: String(ProcessInfo.processInfo.processIdentifier),
                kind: "application",
                primary: true
            ),
            environment: RuntimeEnvironment(
                platform: "macos",
                operatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                deviceCategory: "desktop",
                deviceName: nil,
                deviceModel: nil,
                virtualDevice: false,
                locale: Locale.current.identifier,
                layoutDirection: NSApp.userInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight,
                display: displayInfo(screen)
            ),
            extensions: nil
        )
    }

    func hierarchySnapshot() async throws -> RuntimeHierarchySnapshotPayload {
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { throw unavailableTarget() }
        let windows = NSApp.windows.filter { isInspectable($0, screens: screens) }
        guard !windows.isEmpty else { throw unavailableTarget() }

        registry.pruneReleasedObjects()
        let viewport = windows.reduce(NSRect.null) { $0.union($1.frame) }
        let roots = try windows.enumerated().map { index, window in
            let id = registry.nodeID(for: window)
            let geometry = windowGeometry(window, primaryScreen: primaryScreen)
            let content: [RuntimeNode]
            if let view = window.contentView {
                content = [try collect(view, parentID: id, index: 0, primaryScreen: primaryScreen,
                                       displays: screens.map(\.frame), ancestorAlpha: window.alphaValue,
                                       ancestorHidden: false)]
            } else {
                content = []
            }
            let visibility = try makeVisibility(hidden: false, ancestorHidden: false, alpha: window.alphaValue,
                                                inheritedAlpha: 1, intersects: true, clipped: false)
            return try makeNode(object: window, id: id, parentID: nil, index: index, role: "window",
                                geometry: geometry, visibility: visibility, clips: true,
                                text: window.title, interaction: interaction(for: window), children: content)
        }
        return RuntimeHierarchySnapshotPayload(
            snapshotID: try RuntimeOpaqueIdentifier(rawValue: UUID().uuidString),
            capturedAtUnixTime: Date().timeIntervalSince1970,
            targetIdentifier: targetID,
            orientation: "desktop",
            display: displayInfo(primaryScreen),
            viewport: screenRect(viewport, primaryScreen: primaryScreen),
            roots: roots
        )
    }

    func nodeDetail(for nodeID: RuntimeOpaqueIdentifier) async throws -> RuntimeNodeDetailPayload {
        let screens = NSScreen.screens
        guard let screen = screens.first, let object = registry.object(for: nodeID) else {
            throw nodeNotFound()
        }
        let geometry: RuntimeNodeGeometry
        let text: String?
        if let window = object as? NSWindow, isInspectable(window, screens: screens) {
            geometry = windowGeometry(window, primaryScreen: screen)
            text = window.title
        } else if let view = object as? NSView, let window = view.window,
                  isInspectable(window, screens: screens), let root = window.contentView,
                  view === root || view.isDescendant(of: root) {
            geometry = viewGeometry(view, window: window, primaryScreen: screen)
            text = textPreview(view)
        } else {
            throw nodeNotFound()
        }

        var sections = [try section("common.layout", [
            ("bounds", .rect(geometry.bounds)),
            ("frameInParent", geometry.frameInParent.map(RuntimeAttributeValue.rect) ?? .null),
            ("frameInScreen", .rect(geometry.frameInScreen))
        ])]
        if let text, !text.isEmpty {
            sections.append(try section("common.text", [("content", .string(text))]))
        }
        return RuntimeNodeDetailPayload(nodeID: nodeID, sections: sections)
    }

    private func collect(
        _ view: NSView,
        parentID: RuntimeOpaqueIdentifier,
        index: Int,
        primaryScreen: NSScreen,
        displays: [NSRect],
        ancestorAlpha: CGFloat,
        ancestorHidden: Bool
    ) throws -> RuntimeNode {
        guard let window = view.window else { throw unavailableTarget() }
        let id = registry.nodeID(for: view)
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        let visibility = try makeVisibility(
            hidden: view.isHidden, ancestorHidden: ancestorHidden, alpha: view.alphaValue,
            inheritedAlpha: ancestorAlpha, intersects: frame.intersects(window.frame) && displays.contains { $0.intersects(frame) },
            clipped: view.visibleRect.isEmpty && !view.bounds.isEmpty && !view.isHidden && !ancestorHidden
        )
        let children = try view.subviews.enumerated().map { childIndex, child in
            try collect(child, parentID: id, index: childIndex, primaryScreen: primaryScreen, displays: displays,
                        ancestorAlpha: visibility.effectiveOpacity, ancestorHidden: view.isHidden || ancestorHidden)
        }
        return try makeNode(
            object: view, id: id, parentID: parentID, index: index, role: role(of: view),
            geometry: viewGeometry(view, window: window, primaryScreen: primaryScreen),
            visibility: visibility, clips: view is NSClipView || view.clipsToBounds,
            text: textPreview(view), interaction: interaction(for: view), children: children
        )
    }

    private func makeNode(
        object: AnyObject,
        id: RuntimeOpaqueIdentifier,
        parentID: RuntimeOpaqueIdentifier?,
        index: Int,
        role: String,
        geometry: RuntimeNodeGeometry,
        visibility: RuntimeNodeVisibility,
        clips: Bool,
        text: String?,
        interaction: RuntimeInteraction,
        children: [RuntimeNode]
    ) throws -> RuntimeNode {
        var categories = [try RuntimeNamespacedIdentifier(rawValue: "common.layout")]
        if let text, !text.isEmpty {
            categories.append(try RuntimeNamespacedIdentifier(rawValue: "common.text"))
        }
        var ancestors = [String]()
        var parentClass: AnyClass? = class_getSuperclass(type(of: object))
        while let current = parentClass {
            ancestors.append(NSStringFromClass(current))
            parentClass = class_getSuperclass(current)
        }
        return RuntimeNode(
            nodeID: id, parentID: parentID, siblingIndex: index, role: role,
            runtimeType: RuntimeType(name: NSStringFromClass(type(of: object)), ancestors: ancestors),
            geometry: geometry, visibility: visibility, clipsContent: clips, backgroundColor: nil,
            text: text, accessibility: nil, interaction: interaction, availableDetailCategories: categories,
            extensions: try RuntimeExtensionMap(), children: children
        )
    }

    private func isInspectable(_ window: NSWindow, screens: [NSScreen]) -> Bool {
        window.level == .normal && window.canBecomeMain && window.parent == nil &&
            window.isVisible && !window.isMiniaturized &&
            window.alphaValue > 0 && window.contentView != nil &&
            screens.contains { $0.frame.intersects(window.frame) }
    }

    private func textPreview(_ view: NSView) -> String? {
        if let text = view as? NSTextField {
            // 共享编辑器和各类可编辑控件的值不属于一期文本投影。
            guard !text.isEditable, !(text is NSSecureTextField), !(text.cell is NSSecureTextFieldCell) else { return nil }
            return text.stringValue
        }
        return (view as? NSButton)?.title
    }

    private func role(of view: NSView) -> String {
        switch view {
        case is NSButton: return "button"
        case let field as NSTextField: return field.isEditable || field is NSSecureTextField ? "input" : "text"
        case is NSTextView: return "input"
        case is NSScrollView: return "scroll"
        case is NSTableView, is NSCollectionView: return "list"
        case is NSStackView: return "stack"
        case is NSImageView: return "image"
        default: return "container"
        }
    }

    private func interaction(for object: AnyObject) -> RuntimeInteraction {
        let view = object as? NSView
        let control = object as? NSControl
        let interactive = control.map { !($0 is NSTextField) || ($0 as? NSTextField)?.isEditable == true } ?? (view is NSTextView)
        return RuntimeInteraction(interactive: interactive, enabled: control?.isEnabled, selected: nil,
                                  focused: view?.window.map { $0.firstResponder === view })
    }

    private func makeVisibility(
        hidden: Bool,
        ancestorHidden: Bool,
        alpha: CGFloat,
        inheritedAlpha: CGFloat,
        intersects: Bool,
        clipped: Bool
    ) throws -> RuntimeNodeVisibility {
        let effective = alpha * inheritedAlpha
        return try RuntimeNodeVisibility(
            hidden: hidden, hiddenByAncestor: ancestorHidden, opacity: alpha, effectiveOpacity: effective,
            intersectsViewport: intersects, fullyClippedByAncestor: clipped,
            onscreen: !hidden && !ancestorHidden && effective > 0.01 && intersects && !clipped
        )
    }

    private func windowGeometry(_ window: NSWindow, primaryScreen: NSScreen) -> RuntimeNodeGeometry {
        RuntimeNodeGeometry(bounds: coordinateRect(NSRect(origin: .zero, size: window.frame.size), space: .local),
                            frameInParent: nil, frameInScreen: screenRect(window.frame, primaryScreen: primaryScreen))
    }

    private func viewGeometry(_ view: NSView, window: NSWindow, primaryScreen: NSScreen) -> RuntimeNodeGeometry {
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        let parentFrame: NSRect
        if view === window.contentView {
            parentFrame = NSRect(x: frame.minX - window.frame.minX, y: window.frame.maxY - frame.maxY,
                                 width: frame.width, height: frame.height)
        } else if let parent = view.superview, !parent.isFlipped {
            parentFrame = NSRect(x: view.frame.minX, y: parent.bounds.minY + parent.bounds.maxY - view.frame.maxY,
                                 width: view.frame.width, height: view.frame.height)
        } else {
            parentFrame = view.frame
        }
        return RuntimeNodeGeometry(bounds: coordinateRect(view.bounds, space: .local),
                                   frameInParent: coordinateRect(parentFrame, space: .parent),
                                   frameInScreen: screenRect(frame, primaryScreen: primaryScreen))
    }

    private func screenRect(_ rect: NSRect, primaryScreen: NSScreen) -> RuntimeCoordinateRect {
        // 保留跨屏逻辑坐标，统一以主显示器左上角为原点。
        coordinateRect(NSRect(x: rect.minX - primaryScreen.frame.minX, y: primaryScreen.frame.maxY - rect.maxY,
                             width: rect.width, height: rect.height), space: .screen)
    }

    private func coordinateRect(_ rect: NSRect, space: RuntimeCoordinateSpace) -> RuntimeCoordinateRect {
        RuntimeCoordinateRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                              coordinateSpace: space, unit: .logical)
    }

    private func displayInfo(_ screen: NSScreen) -> RuntimeDisplayInfo {
        let scale = screen.backingScaleFactor
        return RuntimeDisplayInfo(
            logicalSize: RuntimeMeasuredSize(width: screen.frame.width, height: screen.frame.height, unit: .logical),
            pixelSize: RuntimeMeasuredSize(width: screen.frame.width * scale, height: screen.frame.height * scale, unit: .pixel),
            logicalToPixelScale: RuntimeScale(x: scale, y: scale),
            maximumRefreshRate: screen.maximumFramesPerSecond > 0 ? Double(screen.maximumFramesPerSecond) : nil
        )
    }

    private func section(_ category: String, _ values: [(String, RuntimeAttributeValue)]) throws -> RuntimeAttributeSection {
        try RuntimeAttributeSection(
            category: RuntimeAttributeCategory(rawValue: category),
            attributes: values.map { name, value in
                RuntimeAttribute(identifier: try RuntimeAttributeIdentifier(rawValue: "\(category).\(name)"), value: value)
            }
        )
    }

    private func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }

    private func unavailableTarget() -> RuntimeError {
        RuntimeError(code: .internalFailure, message: "当前没有可读取的 AppKit 窗口或显示器。", recoverySuggestion: nil)
    }

    private func nodeNotFound() -> RuntimeError {
        RuntimeError(code: .nodeNotFound, message: "AppKit 节点已离开可检查的窗口。", recoverySuggestion: nil)
    }
}
#endif
