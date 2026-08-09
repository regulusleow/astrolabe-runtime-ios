//
//  UIKitRuntimeProtocolIdentifiers.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/16.
//

#if canImport(UIKit)
import AstrolabeProtocol

extension RuntimeNamespacedIdentifier {
    static let iosLayerMaskRelation = iosNamespacedIdentifier(
        "layer.mask"
    )

    static let iosViewBackingLayerRelation = iosNamespacedIdentifier(
        "view.backingLayer"
    )
}

extension RuntimeAttributeCategory {
    static let commonLayout = commonCategory("layout")
    static let layout = iosCategory("layout")
    static let view = iosCategory("view")
    static let layer = iosCategory("layer")
    static let gradientLayer = iosCategory("gradientLayer")
    static let shapeLayer = iosCategory("shapeLayer")
    static let accessibility = iosCategory("accessibility")
    static let control = iosCategory("control")
    static let label = iosCategory("label")
    static let button = iosCategory("button")
    static let imageView = iosCategory("imageView")
    static let scrollView = iosCategory("scrollView")
    static let stackView = iosCategory("stackView")
    static let textInput = iosCategory("textInput")
    static let autoLayout = iosCategory("autoLayout")
}

extension RuntimeAttributeIdentifier {
    static let commonLayoutRelations = commonAttribute("layout.relations")
    static let frameInParent = iosAttribute("layout.frameInParent")
    static let frameInScreen = iosAttribute("layout.frameInScreen")
    static let bounds = iosAttribute("layout.bounds")
    static let safeAreaInsets = iosAttribute("layout.safeAreaInsets")
    static let intrinsicContentSize = iosAttribute("layout.intrinsicContentSize")
    static let position = iosAttribute("layout.position")
    static let anchorPoint = iosAttribute("layout.anchorPoint")
    static let hidden = iosAttribute("view.hidden")
    static let hiddenByAncestor = iosAttribute("view.hiddenByAncestor")
    static let alpha = iosAttribute("view.alpha")
    static let effectiveAlpha = iosAttribute("view.effectiveAlpha")
    static let userInteractionEnabled = iosAttribute("view.userInteractionEnabled")
    static let clipsToBounds = iosAttribute("view.clipsToBounds")
    static let contentMode = iosAttribute("view.contentMode")
    static let tintAdjustmentMode = iosAttribute("view.tintAdjustmentMode")
    static let tag = iosAttribute("view.tag")
    static let backgroundColor = iosAttribute("view.backgroundColor")
    static let tintColor = iosAttribute("view.tintColor")
    static let layerHidden = iosAttribute("layer.hidden")
    static let layerOpacity = iosAttribute("layer.opacity")
    static let masksToBounds = iosAttribute("layer.masksToBounds")
    static let cornerRadius = iosAttribute("layer.cornerRadius")
    static let borderWidth = iosAttribute("layer.borderWidth")
    static let shadowOpacity = iosAttribute("layer.shadowOpacity")
    static let shadowRadius = iosAttribute("layer.shadowRadius")
    static let shadowOffset = iosAttribute("layer.shadowOffset")
    static let shadowOffsetWidth = iosAttribute("layer.shadowOffsetWidth")
    static let shadowOffsetHeight = iosAttribute("layer.shadowOffsetHeight")
    static let layerBackgroundColor = iosAttribute("layer.backgroundColor")
    static let borderColor = iosAttribute("layer.borderColor")
    static let shadowColor = iosAttribute("layer.shadowColor")
    static let gradientLayerColors = iosAttribute("gradientLayer.colors")
    static let gradientLayerLocations = iosAttribute("gradientLayer.locations")
    static let gradientLayerStartPoint = iosAttribute("gradientLayer.startPoint")
    static let gradientLayerEndPoint = iosAttribute("gradientLayer.endPoint")
    static let gradientLayerType = iosAttribute("gradientLayer.type")
    static let shapeLayerPath = iosAttribute("shapeLayer.path")
    static let shapeLayerFillRule = iosAttribute("shapeLayer.fillRule")
    static let accessibilityElement = iosAttribute("accessibility.element")
    static let accessibilityIdentifier = iosAttribute("accessibility.identifier")
    static let accessibilityLabel = iosAttribute("accessibility.label")
    static let accessibilityValue = iosAttribute("accessibility.value")
    static let accessibilityHint = iosAttribute("accessibility.hint")
    static let accessibilityTraits = iosAttribute("accessibility.traits")
    static let enabled = iosAttribute("control.enabled")
    static let selected = iosAttribute("control.selected")
    static let highlighted = iosAttribute("control.highlighted")
    static let text = iosAttribute("label.text")
    static let attributedTextRuns = iosAttribute("label.attributedTextRuns")
    static let adjustsFontSizeToFitWidth = iosAttribute("label.adjustsFontSizeToFitWidth")
    static let fontName = iosAttribute("label.fontName")
    static let fontFamilyName = iosAttribute("label.fontFamilyName")
    static let fontSize = iosAttribute("label.fontSize")
    static let textColor = iosAttribute("label.textColor")
    static let textAlignment = iosAttribute("label.textAlignment")
    static let numberOfLines = iosAttribute("label.numberOfLines")
    static let lineBreakMode = iosAttribute("label.lineBreakMode")
    static let buttonTitle = iosAttribute("button.title")
    static let imagePresent = iosAttribute("imageView.imagePresent")
    static let imageSize = iosAttribute("imageView.imageSize")
    static let imageScale = iosAttribute("imageView.imageScale")
    static let imageRenderingMode = iosAttribute("imageView.renderingMode")
    static let horizontalAlignment = iosAttribute("control.horizontalAlignment")
    static let verticalAlignment = iosAttribute("control.verticalAlignment")
    static let contentInsets = iosAttribute("button.contentInsets")
    static let contentOffset = iosAttribute("scrollView.contentOffset")
    static let contentSize = iosAttribute("scrollView.contentSize")
    static let contentInset = iosAttribute("scrollView.contentInset")
    static let adjustedContentInset = iosAttribute("scrollView.adjustedContentInset")
    static let isScrollEnabled = iosAttribute("scrollView.isScrollEnabled")
    static let isPagingEnabled = iosAttribute("scrollView.isPagingEnabled")
    static let showsHorizontalScrollIndicator = iosAttribute(
        "scrollView.showsHorizontalScrollIndicator"
    )
    static let showsVerticalScrollIndicator = iosAttribute(
        "scrollView.showsVerticalScrollIndicator"
    )
    static let stackAxis = iosAttribute("stackView.axis")
    static let stackAlignment = iosAttribute("stackView.alignment")
    static let stackSpacing = iosAttribute("stackView.spacing")
    static let stackDistribution = iosAttribute("stackView.distribution")
    static let inputText = iosAttribute("textInput.text")
    static let placeholder = iosAttribute("textInput.placeholder")
    static let isSecureTextEntry = iosAttribute("textInput.isSecureTextEntry")
    static let keyboardType = iosAttribute("textInput.keyboardType")
    static let constraints = iosAttribute("autoLayout.constraints")
    static let translatesAutoresizingMaskIntoConstraints = iosAttribute(
        "autoLayout.translatesAutoresizingMaskIntoConstraints"
    )
    static let horizontalContentHuggingPriority = iosAttribute(
        "autoLayout.horizontalContentHuggingPriority"
    )
    static let verticalContentHuggingPriority = iosAttribute(
        "autoLayout.verticalContentHuggingPriority"
    )
    static let horizontalCompressionResistancePriority = iosAttribute(
        "autoLayout.horizontalCompressionResistancePriority"
    )
    static let verticalCompressionResistancePriority = iosAttribute(
        "autoLayout.verticalCompressionResistancePriority"
    )
}

extension RuntimePatchValueType {
    static let string = patchValueType("string")
    static let number = patchValueType("number")
    static let color = patchValueType("color")
    static let vector = patchValueType("vector")
}

private func iosCategory(_ path: String) -> RuntimeAttributeCategory {
    do {
        return try RuntimeAttributeCategory(rawValue: "ios.\(path)")
    } catch {
        preconditionFailure("Invalid built-in iOS attribute category: \(path)")
    }
}

private func commonCategory(_ path: String) -> RuntimeAttributeCategory {
    do {
        return try RuntimeAttributeCategory(rawValue: "common.\(path)")
    } catch {
        preconditionFailure("Invalid built-in common attribute category: \(path)")
    }
}

private func iosAttribute(_ path: String) -> RuntimeAttributeIdentifier {
    do {
        return try RuntimeAttributeIdentifier(rawValue: "ios.\(path)")
    } catch {
        preconditionFailure("Invalid built-in iOS attribute identifier: \(path)")
    }
}

private func commonAttribute(_ path: String) -> RuntimeAttributeIdentifier {
    do {
        return try RuntimeAttributeIdentifier(rawValue: "common.\(path)")
    } catch {
        preconditionFailure("Invalid built-in common attribute identifier: \(path)")
    }
}

private func iosNamespacedIdentifier(
    _ path: String
) -> RuntimeNamespacedIdentifier {
    do {
        return try RuntimeNamespacedIdentifier(rawValue: "ios.\(path)")
    } catch {
        preconditionFailure("Invalid built-in iOS identifier: \(path)")
    }
}

private func patchValueType(_ rawValue: String) -> RuntimePatchValueType {
    do {
        return try RuntimePatchValueType(rawValue: rawValue)
    } catch {
        preconditionFailure("Invalid built-in patch value type: \(rawValue)")
    }
}
#endif
