//
//  UIKitHierarchyCollector.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore
import AstrolabeRuntimeObjC
import QuartzCore
import UIKit

private struct UIKitCapturedLayerContext {
    /// Layer captured from the authoritative window layer hierarchy.
    let layer: CALayer

    /// Window that owns the authoritative layer hierarchy.
    let window: UIWindow

    /// Whether the owner or one of its ancestors hides dependent layers.
    let dependencyHiddenByAncestor: Bool

    /// Effective opacity inherited by dependent layers.
    let dependencyAncestorAlpha: Double

    /// Visible screen rect inherited by dependent layers.
    let dependencyAncestorVisibleRect: CGRect
}

private enum UIKitLayerCaptureMode {
    /// Capture from the authoritative layer hierarchy.
    case hierarchy

    /// Capture a detached mask tree using its owner as the coordinate anchor.
    case detachedMask(owner: CALayer)
}

@MainActor
final class UIKitHierarchyCollector {
    private let nodeRegistry: RuntimeNodeRegistry
    private let targetIdentifier: RuntimeOpaqueIdentifier
    private let screenMapper: UIKitRuntimeScreenMapper
    private let colorMapper: UIKitRuntimeColorMapper
    private let accessibilityMapper: UIKitRuntimeAccessibilityMapper
    private let attributeCollectorRegistry: UIKitRuntimeAttributeCollectorRegistry
    private let relationProviderRegistry: UIKitRuntimeNodeRelationProviderRegistry

    init(
        nodeRegistry: RuntimeNodeRegistry,
        targetIdentifier: RuntimeOpaqueIdentifier,
        screenMapper: UIKitRuntimeScreenMapper,
        colorMapper: UIKitRuntimeColorMapper,
        accessibilityMapper: UIKitRuntimeAccessibilityMapper,
        attributeCollectorRegistry: UIKitRuntimeAttributeCollectorRegistry,
        relationProviderRegistry: UIKitRuntimeNodeRelationProviderRegistry = .init()
    ) {
        self.nodeRegistry = nodeRegistry
        self.targetIdentifier = targetIdentifier
        self.screenMapper = screenMapper
        self.colorMapper = colorMapper
        self.accessibilityMapper = accessibilityMapper
        self.attributeCollectorRegistry = attributeCollectorRegistry
        self.relationProviderRegistry = relationProviderRegistry
    }

    func capture(
        context: UIKitRuntimeWindowContext
    ) throws -> RuntimeHierarchySnapshotPayload {
        try capture(
            windows: context.windows,
            screen: context.scene.screen,
            interfaceOrientation: orientationName(
                context.scene.interfaceOrientation
            ),
            capturedAtUnixTime: Date().timeIntervalSince1970
        )
    }

    func capture(
        windows: [UIWindow],
        screen: UIScreen,
        interfaceOrientation: String,
        capturedAtUnixTime: Double
    ) throws -> RuntimeHierarchySnapshotPayload {
        nodeRegistry.pruneReleasedObjects()
        var roots = try windows.enumerated().map { index, window in
            try viewNode(
                for: window,
                parentID: nil,
                siblingIndex: index,
                window: window,
                screen: screen,
                ancestorHidden: false,
                ancestorAlpha: 1,
                ancestorVisibleRect: screen.coordinateSpace.bounds
            )
        }
        let layerRootOffset = roots.count
        var capturedLayerContexts = [UIKitCapturedLayerContext]()
        roots.append(contentsOf: try windows.enumerated().map { index, window in
            try layerNode(
                for: window.layer,
                parentID: nil,
                siblingIndex: layerRootOffset + index,
                window: window,
                screen: screen,
                ancestorHidden: false,
                ancestorAlpha: 1,
                ancestorVisibleRect: screen.coordinateSpace.bounds,
                captureMode: .hierarchy,
                capturedLayerContexts: &capturedLayerContexts
            )
        })
        try appendDetachedMaskRoots(
            to: &roots,
            capturedLayerContexts: capturedLayerContexts,
            screen: screen
        )
        let relationContext = UIKitRuntimeNodeRelationCollectionContext(
            windows: windows,
            layers: capturedLayerContexts.map(\.layer),
            nodeIDsByObjectIdentity: capturedNodeIDs(in: roots)
        )

        return RuntimeHierarchySnapshotPayload(
            snapshotID: try RuntimeOpaqueIdentifier(
                rawValue: UUID().uuidString
            ),
            capturedAtUnixTime: capturedAtUnixTime,
            targetIdentifier: targetIdentifier,
            orientation: interfaceOrientation,
            display: screenMapper.displayInfo(for: screen),
            viewport: coordinateRect(
                screen.coordinateSpace.bounds,
                space: .screen
            ),
            roots: roots,
            relations: try relationProviderRegistry.relations(
                in: relationContext
            ),
            extensions: nil
        )
    }

    private func capturedNodeIDs(
        in roots: [RuntimeNode]
    ) -> [ObjectIdentifier: RuntimeOpaqueIdentifier] {
        var nodeIDsByObjectIdentity =
            [ObjectIdentifier: RuntimeOpaqueIdentifier]()
        for root in roots {
            collectCapturedNodeIDs(
                from: root,
                into: &nodeIDsByObjectIdentity
            )
        }
        return nodeIDsByObjectIdentity
    }

    private func collectCapturedNodeIDs(
        from node: RuntimeNode,
        into nodeIDsByObjectIdentity:
            inout [ObjectIdentifier: RuntimeOpaqueIdentifier]
    ) {
        if let object = nodeRegistry.object(for: node.nodeID) {
            nodeIDsByObjectIdentity[ObjectIdentifier(object)] = node.nodeID
        }
        for child in node.children {
            collectCapturedNodeIDs(
                from: child,
                into: &nodeIDsByObjectIdentity
            )
        }
    }

    private func viewNode(
        for view: UIView,
        parentID: RuntimeOpaqueIdentifier?,
        siblingIndex: Int,
        window: UIWindow,
        screen: UIScreen,
        ancestorHidden: Bool,
        ancestorAlpha: Double,
        ancestorVisibleRect: CGRect
    ) throws -> RuntimeNode {
        let nodeID = nodeRegistry.nodeID(for: view)
        let hiddenByAncestor = ancestorHidden
        let effectiveAlpha = ancestorAlpha * Double(view.alpha)
        let geometry = viewGeometry(
            view,
            isRoot: parentID == nil,
            window: window,
            screen: screen
        )
        let frameInScreen = cgRect(geometry.frameInScreen)
        let visibleRect = ancestorVisibleRect.intersection(frameInScreen)
        let intersectsViewport = screen.coordinateSpace.bounds.intersects(
            frameInScreen
        )
        let fullyClippedByAncestor = intersectsViewport &&
            (visibleRect.isNull || visibleRect.isEmpty)
        let onscreen = !view.isHidden &&
            !hiddenByAncestor &&
            effectiveAlpha > 0.01 &&
            intersectsViewport &&
            !fullyClippedByAncestor
        let childVisibleRect = view.clipsToBounds ?
            visibleRect :
            ancestorVisibleRect
        let children = try view.subviews.enumerated().map { index, subview in
            try viewNode(
                for: subview,
                parentID: nodeID,
                siblingIndex: index,
                window: window,
                screen: screen,
                ancestorHidden: hiddenByAncestor || view.isHidden,
                ancestorAlpha: effectiveAlpha,
                ancestorVisibleRect: childVisibleRect
            )
        }

        return RuntimeNode(
            nodeID: nodeID,
            parentID: parentID,
            siblingIndex: siblingIndex,
            role: semanticRole(for: view),
            runtimeType: runtimeType(for: view),
            geometry: geometry,
            visibility: try RuntimeNodeVisibility(
                hidden: view.isHidden,
                hiddenByAncestor: hiddenByAncestor,
                opacity: Double(view.alpha),
                effectiveOpacity: effectiveAlpha,
                intersectsViewport: intersectsViewport,
                fullyClippedByAncestor: fullyClippedByAncestor,
                onscreen: onscreen
            ),
            clipsContent: view.clipsToBounds,
            backgroundColor: colorMapper.color(
                from: view.backgroundColor,
                traitCollection: view.traitCollection
            ),
            text: textPreview(for: view),
            accessibility: accessibilityMapper.accessibilityInfo(for: view),
            interaction: interaction(for: view),
            availableDetailCategories: try detailCategories(for: view),
            extensions: try RuntimeExtensionMap(),
            children: children
        )
    }

    private func layerNode(
        for layer: CALayer,
        parentID: RuntimeOpaqueIdentifier?,
        siblingIndex: Int,
        window: UIWindow,
        screen: UIScreen,
        ancestorHidden: Bool,
        ancestorAlpha: Double,
        ancestorVisibleRect: CGRect,
        captureMode: UIKitLayerCaptureMode,
        capturedLayerContexts: inout [UIKitCapturedLayerContext]
    ) throws -> RuntimeNode {
        let nodeID = nodeRegistry.nodeID(for: layer)
        let hiddenByAncestor = ancestorHidden
        let effectiveAlpha = ancestorAlpha * Double(layer.opacity)
        let geometry = layerGeometry(
            layer,
            isRoot: parentID == nil,
            window: window,
            screen: screen,
            captureMode: captureMode
        )
        let frameInScreen = cgRect(geometry.frameInScreen)
        let visibleRect = ancestorVisibleRect.intersection(frameInScreen)
        let intersectsViewport = screen.coordinateSpace.bounds.intersects(
            frameInScreen
        )
        let fullyClippedByAncestor = intersectsViewport &&
            (visibleRect.isNull || visibleRect.isEmpty)
        let onscreen = !layer.isHidden &&
            !hiddenByAncestor &&
            effectiveAlpha > 0.01 &&
            intersectsViewport &&
            !fullyClippedByAncestor
        let childVisibleRect = layer.masksToBounds ?
            visibleRect :
            ancestorVisibleRect
        if case .hierarchy = captureMode {
            capturedLayerContexts.append(UIKitCapturedLayerContext(
                layer: layer,
                window: window,
                dependencyHiddenByAncestor: hiddenByAncestor || layer.isHidden,
                dependencyAncestorAlpha: effectiveAlpha,
                dependencyAncestorVisibleRect: visibleRect
            ))
        }
        let children = try (layer.sublayers ?? []).enumerated().map {
            index, sublayer in
            try layerNode(
                for: sublayer,
                parentID: nodeID,
                siblingIndex: index,
                window: window,
                screen: screen,
                ancestorHidden: hiddenByAncestor || layer.isHidden,
                ancestorAlpha: effectiveAlpha,
                ancestorVisibleRect: childVisibleRect,
                captureMode: captureMode,
                capturedLayerContexts: &capturedLayerContexts
            )
        }

        return RuntimeNode(
            nodeID: nodeID,
            parentID: parentID,
            siblingIndex: siblingIndex,
            role: "layer",
            runtimeType: runtimeType(for: layer),
            geometry: geometry,
            visibility: try RuntimeNodeVisibility(
                hidden: layer.isHidden,
                hiddenByAncestor: hiddenByAncestor,
                opacity: Double(layer.opacity),
                effectiveOpacity: effectiveAlpha,
                intersectsViewport: intersectsViewport,
                fullyClippedByAncestor: fullyClippedByAncestor,
                onscreen: onscreen
            ),
            clipsContent: layer.masksToBounds,
            backgroundColor: colorMapper.color(from: layer.backgroundColor),
            text: nil,
            accessibility: nil,
            interaction: RuntimeInteraction(
                interactive: false,
                enabled: nil,
                selected: nil,
                focused: nil
            ),
            availableDetailCategories: try detailCategories(for: layer),
            extensions: try RuntimeExtensionMap(),
            children: children
        )
    }

    private func viewGeometry(
        _ view: UIView,
        isRoot: Bool,
        window: UIWindow,
        screen: UIScreen
    ) -> RuntimeNodeGeometry {
        let rectInWindow = view.convert(view.bounds, to: window)
        let rectInScreen = window.convert(
            rectInWindow,
            to: screen.coordinateSpace
        )
        return RuntimeNodeGeometry(
            bounds: coordinateRect(view.bounds, space: .local),
            frameInParent: isRoot ? nil : coordinateRect(
                view.frame,
                space: .parent
            ),
            frameInScreen: coordinateRect(rectInScreen, space: .screen)
        )
    }

    private func layerGeometry(
        _ layer: CALayer,
        isRoot: Bool,
        window: UIWindow,
        screen: UIScreen,
        captureMode: UIKitLayerCaptureMode
    ) -> RuntimeNodeGeometry {
        let rectInWindow: CGRect
        switch captureMode {
        case .hierarchy:
            rectInWindow = layer.convert(layer.bounds, to: window.layer)
        case let .detachedMask(owner):
            let rectInOwner = layer.convert(layer.bounds, to: owner)
            rectInWindow = owner.convert(rectInOwner, to: window.layer)
        }
        let rectInScreen = window.convert(
            rectInWindow,
            to: screen.coordinateSpace
        )
        return RuntimeNodeGeometry(
            bounds: coordinateRect(layer.bounds, space: .local),
            frameInParent: isRoot ? nil : coordinateRect(
                layer.frame,
                space: .parent
            ),
            frameInScreen: coordinateRect(rectInScreen, space: .screen)
        )
    }

    private func appendDetachedMaskRoots(
        to roots: inout [RuntimeNode],
        capturedLayerContexts: [UIKitCapturedLayerContext],
        screen: UIScreen
    ) throws {
        var capturedLayerIdentities = Set(
            capturedLayerContexts.map { ObjectIdentifier($0.layer) }
        )
        var ignoredLayerContexts = [UIKitCapturedLayerContext]()
        for context in capturedLayerContexts {
            guard let mask = context.layer.mask,
                  capturedLayerIdentities.insert(ObjectIdentifier(mask)).inserted
            else {
                continue
            }
            capturedLayerIdentities.formUnion(layerIdentities(in: mask))
            roots.append(try layerNode(
                for: mask,
                parentID: nil,
                siblingIndex: roots.count,
                window: context.window,
                screen: screen,
                ancestorHidden: context.dependencyHiddenByAncestor,
                ancestorAlpha: context.dependencyAncestorAlpha,
                ancestorVisibleRect: context.dependencyAncestorVisibleRect,
                captureMode: .detachedMask(owner: context.layer),
                capturedLayerContexts: &ignoredLayerContexts
            ))
        }
    }

    private func layerIdentities(
        in root: CALayer
    ) -> Set<ObjectIdentifier> {
        (root.sublayers ?? []).reduce(into: [ObjectIdentifier(root)]) {
            identities, layer in
            identities.formUnion(layerIdentities(in: layer))
        }
    }

    private func runtimeType(for object: AnyObject) -> RuntimeType {
        let classChain = RuntimeMetadataAdapter.classChain(for: object)
        return RuntimeType(
            name: RuntimeMetadataAdapter.className(for: object),
            ancestors: Array(classChain.dropFirst())
        )
    }

    private func semanticRole(for view: UIView) -> String {
        switch view {
        case is UIWindow:
            return "window"
        case is UILabel:
            return "label"
        case is UIButton:
            return "button"
        case is UIImageView:
            return "image"
        case is UITextField, is UITextView, is UISearchBar:
            return "textInput"
        case is UIScrollView:
            return "scroll"
        case is UIStackView:
            return "container"
        default:
            return "view"
        }
    }

    private func interaction(for view: UIView) -> RuntimeInteraction {
        let control = view as? UIControl
        return RuntimeInteraction(
            interactive: view.isUserInteractionEnabled,
            enabled: control?.isEnabled,
            selected: control?.isSelected,
            focused: view.isFocused
        )
    }

    private func detailCategories(
        for object: AnyObject
    ) throws -> [RuntimeNamespacedIdentifier] {
        try attributeCollectorRegistry.categories(for: object).map {
            try RuntimeNamespacedIdentifier(rawValue: $0.rawValue)
        }
    }

    private func textPreview(for view: UIView) -> String? {
        let text: String?
        switch view {
        case let label as UILabel:
            text = label.text
        case let button as UIButton:
            text = button.currentTitle
        case let textField as UITextField:
            text = textField.isSecureTextEntry ?
                textField.placeholder :
                (textField.text?.isEmpty == false ?
                    textField.text :
                    textField.placeholder)
        case let textView as UITextView:
            text = textView.isSecureTextEntry ? nil : textView.text
        case let searchBar as UISearchBar:
            text = searchBar.searchTextField.isSecureTextEntry ?
                searchBar.placeholder :
                (searchBar.text?.isEmpty == false ?
                    searchBar.text :
                    searchBar.placeholder)
        default:
            text = nil
        }
        guard let text, !text.isEmpty else {
            return nil
        }
        return text
    }

    private func orientationName(
        _ orientation: UIInterfaceOrientation
    ) -> String {
        switch orientation {
        case .portrait:
            return "portrait"
        case .portraitUpsideDown:
            return "portraitUpsideDown"
        case .landscapeLeft:
            return "landscapeLeft"
        case .landscapeRight:
            return "landscapeRight"
        default:
            return "unknown"
        }
    }

    private func coordinateRect(
        _ rect: CGRect,
        space: RuntimeCoordinateSpace
    ) -> RuntimeCoordinateRect {
        RuntimeCoordinateRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height,
            coordinateSpace: space,
            unit: .logical
        )
    }

    private func cgRect(_ rect: RuntimeCoordinateRect) -> CGRect {
        CGRect(
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        )
    }
}
#endif
