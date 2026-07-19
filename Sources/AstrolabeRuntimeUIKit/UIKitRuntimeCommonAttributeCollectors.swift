//
//  UIKitRuntimeCommonAttributeCollectors.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import QuartzCore
import UIKit

struct UIKitLayoutAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.layout

    func supports(_ object: AnyObject) -> Bool {
        object is UIView || object is CALayer
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        if let view = object as? UIView {
            return viewAttributes(view)
        }
        guard let layer = object as? CALayer else {
            return []
        }
        return layerAttributes(layer)
    }

    private func viewAttributes(_ view: UIView) -> [RuntimeAttribute] {
        var attributes = [
            attribute(.frameInParent, .rect(runtimeRect(view.frame, space: .parent))),
            attribute(.bounds, .rect(runtimeRect(view.bounds, space: .local))),
            attribute(.safeAreaInsets, .insets(runtimeEdgeInsets(view.safeAreaInsets)))
        ]
        if let frameInScreen = frameInScreen(for: view) {
            attributes.insert(attribute(.frameInScreen, .rect(frameInScreen)), at: 1)
        }
        let intrinsicContentSize = view.intrinsicContentSize
        if intrinsicContentSize.width.isFinite,
           intrinsicContentSize.height.isFinite,
           intrinsicContentSize.width >= 0,
           intrinsicContentSize.height >= 0 {
            attributes.append(
                attribute(
                    .intrinsicContentSize,
                    .size(runtimeSize(intrinsicContentSize))
                )
            )
        }
        return attributes
    }

    private func layerAttributes(_ layer: CALayer) -> [RuntimeAttribute] {
        var attributes = [
            attribute(.frameInParent, .rect(runtimeRect(layer.frame, space: .parent))),
            attribute(.bounds, .rect(runtimeRect(layer.bounds, space: .local))),
            attribute(.position, .point(runtimePoint(layer.position, space: .parent))),
            attribute(.anchorPoint, runtimeUnitPoint(layer.anchorPoint))
        ]
        if let frameInScreen = frameInScreen(for: layer) {
            attributes.insert(attribute(.frameInScreen, .rect(frameInScreen)), at: 1)
        }
        return attributes
    }

    private func frameInScreen(for view: UIView) -> RuntimeCoordinateRect? {
        guard let window = view.window ?? view as? UIWindow else {
            return nil
        }
        let rectInWindow = view.convert(view.bounds, to: window)
        return runtimeRect(
            window.convert(rectInWindow, to: window.screen.coordinateSpace),
            space: .screen
        )
    }

    private func frameInScreen(for layer: CALayer) -> RuntimeCoordinateRect? {
        guard let window = owningWindow(for: layer) else {
            return nil
        }
        let rectInWindow = layer.convert(layer.bounds, to: window.layer)
        return runtimeRect(
            window.convert(rectInWindow, to: window.screen.coordinateSpace),
            space: .screen
        )
    }

    private func owningWindow(for layer: CALayer) -> UIWindow? {
        var candidate: CALayer? = layer
        while let current = candidate {
            if let window = current.delegate as? UIWindow {
                return window
            }
            if let view = current.delegate as? UIView, let window = view.window {
                return window
            }
            candidate = current.superlayer
        }
        return nil
    }
}

struct UIKitViewAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.view

    func supports(_ object: AnyObject) -> Bool {
        object is UIView
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let view = object as? UIView else {
            return []
        }
        let ancestorState = ancestorVisibilityState(for: view)
        var attributes = [
            attribute(.hidden, .boolean(view.isHidden)),
            attribute(.hiddenByAncestor, .boolean(ancestorState.hidden)),
            attribute(.alpha, .number(Double(view.alpha))),
            attribute(.effectiveAlpha, .number(ancestorState.alpha * Double(view.alpha))),
            attribute(.userInteractionEnabled, .boolean(view.isUserInteractionEnabled)),
            attribute(.clipsToBounds, .boolean(view.clipsToBounds)),
            attribute(.contentMode, .string(contentModeName(view.contentMode))),
            attribute(
                .tintAdjustmentMode,
                .string(tintAdjustmentModeName(view.tintAdjustmentMode))
            ),
            attribute(.tag, .integer(Int64(view.tag)))
        ]
        if let color = context.colorMapper.color(
            from: view.backgroundColor,
            traitCollection: view.traitCollection
        ) {
            attributes.append(attribute(.backgroundColor, .color(color)))
        }
        if let color = context.colorMapper.color(
            from: view.tintColor,
            traitCollection: view.traitCollection
        ) {
            attributes.append(attribute(.tintColor, .color(color)))
        }
        return attributes
    }

    private func ancestorVisibilityState(for view: UIView) -> (hidden: Bool, alpha: Double) {
        var hidden = false
        var alpha = 1.0
        var ancestor = view.superview
        while let current = ancestor {
            hidden = hidden || current.isHidden
            alpha *= Double(current.alpha)
            ancestor = current.superview
        }
        return (hidden, alpha)
    }
}

struct UIKitLayerAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.layer

    func supports(_ object: AnyObject) -> Bool {
        object is UIView || object is CALayer
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        let layer: CALayer
        let traitCollection: UITraitCollection?
        if let view = object as? UIView {
            layer = view.layer
            traitCollection = view.traitCollection
        } else if let objectLayer = object as? CALayer {
            layer = objectLayer
            traitCollection = nil
        } else {
            return []
        }

        var attributes = [
            attribute(.layerHidden, .boolean(layer.isHidden)),
            attribute(.layerOpacity, .number(Double(layer.opacity))),
            attribute(.masksToBounds, .boolean(layer.masksToBounds)),
            attribute(.cornerRadius, .number(layer.cornerRadius)),
            attribute(.borderWidth, .number(layer.borderWidth)),
            attribute(.shadowOpacity, .number(Double(layer.shadowOpacity))),
            attribute(.shadowRadius, .number(layer.shadowRadius)),
            attribute(.shadowOffset, .vector(runtimeVector(layer.shadowOffset))),
            attribute(.shadowOffsetWidth, .number(layer.shadowOffset.width)),
            attribute(.shadowOffsetHeight, .number(layer.shadowOffset.height))
        ]
        appendColor(
            layer.backgroundColor,
            identifier: .layerBackgroundColor,
            traitCollection: traitCollection,
            context: context,
            attributes: &attributes
        )
        appendColor(
            layer.borderColor,
            identifier: .borderColor,
            traitCollection: traitCollection,
            context: context,
            attributes: &attributes
        )
        appendColor(
            layer.shadowColor,
            identifier: .shadowColor,
            traitCollection: traitCollection,
            context: context,
            attributes: &attributes
        )
        return attributes
    }

    private func appendColor(
        _ color: CGColor?,
        identifier: RuntimeAttributeIdentifier,
        traitCollection: UITraitCollection?,
        context: UIKitRuntimeAttributeCollectionContext,
        attributes: inout [RuntimeAttribute]
    ) {
        let mappedColor: RuntimeColor?
        if let traitCollection, let color {
            mappedColor = context.colorMapper.color(
                from: UIColor(cgColor: color),
                traitCollection: traitCollection
            )
        } else {
            mappedColor = context.colorMapper.color(from: color)
        }
        if let mappedColor {
            attributes.append(attribute(identifier, .color(mappedColor)))
        }
    }
}

struct UIKitAccessibilityAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.accessibility

    func supports(_ object: AnyObject) -> Bool {
        object is UIView
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let view = object as? UIView else {
            return []
        }
        let info = context.accessibilityMapper.accessibilityInfo(for: view)
        var attributes = [
            attribute(.accessibilityElement, .boolean(view.isAccessibilityElement))
        ]
        append(info?.identifier, identifier: .accessibilityIdentifier, to: &attributes)
        append(info?.label, identifier: .accessibilityLabel, to: &attributes)
        append(info?.value, identifier: .accessibilityValue, to: &attributes)
        append(info?.hint, identifier: .accessibilityHint, to: &attributes)
        if let info, !info.traits.isEmpty {
            attributes.append(
                attribute(
                    .accessibilityTraits,
                    .stringList(info.traits)
                )
            )
        }
        return attributes
    }

    private func append(
        _ value: String?,
        identifier: RuntimeAttributeIdentifier,
        to attributes: inout [RuntimeAttribute]
    ) {
        guard let value else {
            return
        }
        attributes.append(attribute(identifier, .string(value)))
    }
}

func attribute(
    _ identifier: RuntimeAttributeIdentifier,
    _ value: RuntimeAttributeValue
) -> RuntimeAttribute {
    RuntimeAttribute(identifier: identifier, value: value)
}

func runtimePoint(
    _ point: CGPoint,
    space: RuntimeCoordinateSpace = .local
) -> RuntimeCoordinatePoint {
    RuntimeCoordinatePoint(
        x: point.x,
        y: point.y,
        coordinateSpace: space,
        unit: .logical
    )
}

func runtimeSize(_ size: CGSize) -> RuntimeMeasuredSize {
    RuntimeMeasuredSize(
        width: size.width,
        height: size.height,
        unit: .logical
    )
}

func runtimeVector(_ size: CGSize) -> RuntimeVector {
    RuntimeVector(dx: size.width, dy: size.height, unit: .logical)
}

func runtimeRect(
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

func runtimeEdgeInsets(_ insets: UIEdgeInsets) -> RuntimeInsets {
    RuntimeInsets(
        top: insets.top,
        left: insets.left,
        bottom: insets.bottom,
        right: insets.right,
        unit: .logical
    )
}

func runtimeEdgeInsets(_ insets: NSDirectionalEdgeInsets) -> RuntimeInsets {
    RuntimeInsets(
        top: insets.top,
        left: insets.leading,
        bottom: insets.bottom,
        right: insets.trailing,
        unit: .logical
    )
}

private func runtimeUnitPoint(_ point: CGPoint) -> RuntimeAttributeValue {
    let type: RuntimeNamespacedIdentifier
    do {
        type = try RuntimeNamespacedIdentifier(rawValue: "ios.unitPoint")
    } catch {
        preconditionFailure("Invalid built-in unit point type")
    }
    return .extensionValue(
        type: type,
        value: .object([
            "x": .number(point.x),
            "y": .number(point.y)
        ])
    )
}

private func contentModeName(_ contentMode: UIView.ContentMode) -> String {
    switch contentMode {
    case .scaleToFill: return "scaleToFill"
    case .scaleAspectFit: return "scaleAspectFit"
    case .scaleAspectFill: return "scaleAspectFill"
    case .redraw: return "redraw"
    case .center: return "center"
    case .top: return "top"
    case .bottom: return "bottom"
    case .left: return "left"
    case .right: return "right"
    case .topLeft: return "topLeft"
    case .topRight: return "topRight"
    case .bottomLeft: return "bottomLeft"
    case .bottomRight: return "bottomRight"
    @unknown default: return "unknown:\(contentMode.rawValue)"
    }
}

private func tintAdjustmentModeName(
    _ mode: UIView.TintAdjustmentMode
) -> String {
    switch mode {
    case .automatic: return "automatic"
    case .normal: return "normal"
    case .dimmed: return "dimmed"
    @unknown default: return "unknown:\(mode.rawValue)"
    }
}
#endif
