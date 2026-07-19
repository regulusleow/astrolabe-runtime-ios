//
//  UIKitRuntimeAttributeMutator.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/13.
//

#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore
import QuartzCore
import UIKit

@MainActor
struct UIKitRuntimeAttributeMutator: RuntimeAttributeMutating {
    private let colorMapper = UIKitRuntimeColorMapper()
    private let patchCatalog = UIKitRuntimePatchCatalog()

    var patchableAttributeCatalog: RuntimePatchableAttributesPayload {
        patchCatalog.catalog
    }

    var invalidValueRecoverySuggestion: String? {
        "Inspect the target node and choose an attribute supported by its concrete UIKit type."
    }

    func mutationDescriptor(
        for object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> RuntimeAttributeMutationDescriptor {
        guard patchCatalog.attribute(for: attributeIdentifier) != nil else {
            throw unsupported(attributeIdentifier)
        }
        switch attributeIdentifier {
        case .text, .fontName, .fontSize, .textColor:
            guard let label = object as? UILabel else {
                throw unsupported(attributeIdentifier)
            }
            return descriptor(
                label,
                domainIdentifier: "label.presentation",
                effectIdentifiers: [attributeIdentifier.rawValue]
            )
        case .shadowOffset:
            let (layer, _) = try layer(for: object, attributeIdentifier: attributeIdentifier)
            return descriptor(
                layer,
                domainIdentifier: "layer.presentation",
                effectIdentifiers: ["layer.shadowOffset.width", "layer.shadowOffset.height"]
            )
        case .shadowOffsetWidth:
            let (layer, _) = try layer(for: object, attributeIdentifier: attributeIdentifier)
            return descriptor(
                layer,
                domainIdentifier: "layer.presentation",
                effectIdentifiers: ["layer.shadowOffset.width"]
            )
        case .shadowOffsetHeight:
            let (layer, _) = try layer(for: object, attributeIdentifier: attributeIdentifier)
            return descriptor(
                layer,
                domainIdentifier: "layer.presentation",
                effectIdentifiers: ["layer.shadowOffset.height"]
            )
        case .alpha, .backgroundColor:
            guard let view = object as? UIView else {
                throw unsupported(attributeIdentifier)
            }
            return descriptor(
                view,
                domainIdentifier: "view.presentation",
                effectIdentifiers: [attributeIdentifier.rawValue]
            )
        case .cornerRadius, .borderColor, .borderWidth,
             .shadowColor, .shadowOpacity, .shadowRadius:
            let (layer, _) = try layer(for: object, attributeIdentifier: attributeIdentifier)
            return descriptor(
                layer,
                domainIdentifier: "layer.presentation",
                effectIdentifiers: [attributeIdentifier.rawValue]
            )
        default:
            if let constraintIdentifier = constraintIdentifier(from: attributeIdentifier) {
                let constraint = try constraint(
                    identifiedBy: constraintIdentifier,
                    for: object,
                    attributeIdentifier: attributeIdentifier
                )
                return descriptor(
                    constraint,
                    domainIdentifier: "constraint.constant",
                    effectIdentifiers: ["constraint.constant"]
                )
            }
            throw unsupported(attributeIdentifier)
        }
    }

    private func descriptor(
        _ object: AnyObject,
        domainIdentifier: String,
        effectIdentifiers: Set<String>
    ) -> RuntimeAttributeMutationDescriptor {
        RuntimeAttributeMutationDescriptor(
            domain: RuntimeAttributeMutationDomain(
                objectIdentifier: ObjectIdentifier(object),
                domainIdentifier: domainIdentifier
            ),
            effectIdentifiers: effectIdentifiers
        )
    }

    func apply(
        value: RuntimeAttributeValue,
        to object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> RuntimeAttributeMutation {
        guard patchCatalog.attribute(for: attributeIdentifier) != nil else {
            throw unsupported(attributeIdentifier)
        }
        switch attributeIdentifier {
        case .text:
            return try applyText(value, to: object)
        case .fontName:
            return try applyFontName(value, to: object)
        case .fontSize:
            return try applyFontSize(value, to: object)
        case .textColor:
            return try applyTextColor(value, to: object)
        case .alpha:
            return try applyAlpha(value, to: object)
        case .backgroundColor:
            return try applyBackgroundColor(value, to: object)
        case .cornerRadius:
            return try applyNonnegativeLayerDecimal(
                value,
                to: object,
                attributeIdentifier: attributeIdentifier,
                keyPath: \.cornerRadius
            )
        case .borderWidth:
            return try applyNonnegativeLayerDecimal(
                value,
                to: object,
                attributeIdentifier: attributeIdentifier,
                keyPath: \.borderWidth
            )
        case .shadowRadius:
            return try applyNonnegativeLayerDecimal(
                value,
                to: object,
                attributeIdentifier: attributeIdentifier,
                keyPath: \.shadowRadius
            )
        case .borderColor:
            return try applyLayerColor(
                value,
                to: object,
                attributeIdentifier: attributeIdentifier,
                keyPath: \.borderColor
            )
        case .shadowColor:
            return try applyLayerColor(
                value,
                to: object,
                attributeIdentifier: attributeIdentifier,
                keyPath: \.shadowColor
            )
        case .shadowOpacity:
            return try applyShadowOpacity(value, to: object)
        case .shadowOffset:
            return try applyShadowOffset(value, to: object)
        case .shadowOffsetWidth:
            return try applyShadowOffsetComponent(value, to: object, isWidth: true)
        case .shadowOffsetHeight:
            return try applyShadowOffsetComponent(value, to: object, isWidth: false)
        default:
            guard let identifier = constraintIdentifier(from: attributeIdentifier) else {
                throw unsupported(attributeIdentifier)
            }
            return try applyConstraintConstant(
                value,
                to: object,
                identifier: identifier,
                attributeIdentifier: attributeIdentifier
            )
        }
    }

    private func applyText(
        _ value: RuntimeAttributeValue,
        to object: AnyObject
    ) throws -> RuntimeAttributeMutation {
        guard let label = object as? UILabel else {
            throw unsupported(.text)
        }
        let requested = try string(value, attributeIdentifier: .text)
        let original = label.text.map(RuntimeAttributeValue.string)
        let originalAttributedText = attributedTextToPreserve(from: label)
        label.text = requested
        refresh(label)
        return RuntimeAttributeMutation(
            originalValue: original,
            actualValue: label.text.map(RuntimeAttributeValue.string),
            restore: { [weak label] in
                guard let label else {
                    return nil
                }
                if let originalAttributedText {
                    label.attributedText = originalAttributedText
                } else {
                    label.text = original.flatMap { value in
                        guard case let .string(text) = value else {
                            return nil
                        }
                        return text
                    }
                }
                refresh(label)
                return label.text.map(RuntimeAttributeValue.string)
            }
        )
    }

    private func applyFontName(
        _ value: RuntimeAttributeValue,
        to object: AnyObject
    ) throws -> RuntimeAttributeMutation {
        guard let label = object as? UILabel,
              let originalFont = label.font else {
            throw unsupported(.fontName)
        }
        let requested = try string(value, attributeIdentifier: .fontName)
        guard !requested.isEmpty,
              let font = UIFont(name: requested, size: originalFont.pointSize) else {
            throw invalidValue(.fontName, expectation: "an installed font name")
        }
        let originalAttributedText = attributedTextToPreserve(from: label)
        label.font = font
        apply(font: font, to: label)
        refresh(label)
        return RuntimeAttributeMutation(
            originalValue: .string(originalFont.fontName),
            actualValue: label.font.map { .string($0.fontName) },
            restore: { [weak label] in
                guard let label else {
                    return nil
                }
                label.font = originalFont
                if let originalAttributedText {
                    label.attributedText = originalAttributedText
                }
                refresh(label)
                return label.font.map { .string($0.fontName) }
            }
        )
    }

    private func applyFontSize(
        _ value: RuntimeAttributeValue,
        to object: AnyObject
    ) throws -> RuntimeAttributeMutation {
        guard let label = object as? UILabel,
              let originalFont = label.font else {
            throw unsupported(.fontSize)
        }
        let requested = try decimal(value, attributeIdentifier: .fontSize)
        guard requested > 0 else {
            throw invalidValue(.fontSize, expectation: "a positive number")
        }
        let originalAttributedText = attributedTextToPreserve(from: label)
        label.font = UIFont(
            descriptor: originalFont.fontDescriptor,
            size: CGFloat(requested)
        )
        if let font = label.font {
            apply(font: font, to: label)
        }
        refresh(label)
        return RuntimeAttributeMutation(
            originalValue: .number(Double(originalFont.pointSize)),
            actualValue: label.font.map { .number(Double($0.pointSize)) },
            restore: { [weak label] in
                guard let label else {
                    return nil
                }
                label.font = originalFont
                if let originalAttributedText {
                    label.attributedText = originalAttributedText
                }
                refresh(label)
                return label.font.map { .number(Double($0.pointSize)) }
            }
        )
    }

    private func applyTextColor(
        _ value: RuntimeAttributeValue,
        to object: AnyObject
    ) throws -> RuntimeAttributeMutation {
        guard let label = object as? UILabel else {
            throw unsupported(.textColor)
        }
        let requested = try color(value, attributeIdentifier: .textColor)
        let originalColor = label.textColor
        let originalAttributedText = attributedTextToPreserve(from: label)
        let original = runtimeColor(originalColor, for: label).map(RuntimeAttributeValue.color)
        label.textColor = requested
        apply(textColor: requested, to: label)
        refresh(label)
        return RuntimeAttributeMutation(
            originalValue: original,
            actualValue: runtimeColor(label.textColor, for: label).map(RuntimeAttributeValue.color),
            comparisonValue: runtimeColor(requested, for: label).map(RuntimeAttributeValue.color),
            restore: { [weak label] in
                guard let label else {
                    return nil
                }
                label.textColor = originalColor
                if let originalAttributedText {
                    label.attributedText = originalAttributedText
                }
                refresh(label)
                return runtimeColor(label.textColor, for: label).map(RuntimeAttributeValue.color)
            }
        )
    }

    private func applyAlpha(
        _ value: RuntimeAttributeValue,
        to object: AnyObject
    ) throws -> RuntimeAttributeMutation {
        guard let view = object as? UIView else {
            throw unsupported(.alpha)
        }
        let requested = try decimal(value, attributeIdentifier: .alpha)
        guard (0 ... 1).contains(requested) else {
            throw invalidValue(.alpha, expectation: "a number from 0 through 1")
        }
        let original = view.alpha
        view.alpha = CGFloat(requested)
        refresh(view)
        return RuntimeAttributeMutation(
            originalValue: .number(Double(original)),
            actualValue: .number(Double(view.alpha)),
            restore: { [weak view] in
                guard let view else {
                    return nil
                }
                view.alpha = original
                refresh(view)
                return .number(Double(view.alpha))
            }
        )
    }

    private func applyBackgroundColor(
        _ value: RuntimeAttributeValue,
        to object: AnyObject
    ) throws -> RuntimeAttributeMutation {
        guard let view = object as? UIView else {
            throw unsupported(.backgroundColor)
        }
        let requested = try color(value, attributeIdentifier: .backgroundColor)
        let originalColor = view.backgroundColor
        let original = runtimeColor(originalColor, for: view).map(RuntimeAttributeValue.color)
        view.backgroundColor = requested
        refresh(view)
        return RuntimeAttributeMutation(
            originalValue: original,
            actualValue: runtimeColor(view.backgroundColor, for: view).map(RuntimeAttributeValue.color),
            comparisonValue: runtimeColor(requested, for: view).map(RuntimeAttributeValue.color),
            restore: { [weak view] in
                guard let view else {
                    return nil
                }
                view.backgroundColor = originalColor
                refresh(view)
                return runtimeColor(view.backgroundColor, for: view).map(RuntimeAttributeValue.color)
            }
        )
    }

    private func applyNonnegativeLayerDecimal(
        _ value: RuntimeAttributeValue,
        to object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier,
        keyPath: ReferenceWritableKeyPath<CALayer, CGFloat>
    ) throws -> RuntimeAttributeMutation {
        let (layer, view) = try layer(for: object, attributeIdentifier: attributeIdentifier)
        let requested = try decimal(value, attributeIdentifier: attributeIdentifier)
        guard requested >= 0 else {
            throw invalidValue(attributeIdentifier, expectation: "a nonnegative number")
        }
        let original = layer[keyPath: keyPath]
        layer[keyPath: keyPath] = CGFloat(requested)
        refresh(view)
        return RuntimeAttributeMutation(
            originalValue: .number(Double(original)),
            actualValue: .number(Double(layer[keyPath: keyPath])),
            restore: { [weak layer, weak view] in
                guard let layer else {
                    return nil
                }
                layer[keyPath: keyPath] = original
                refresh(view)
                return .number(Double(layer[keyPath: keyPath]))
            }
        )
    }

    private func applyLayerColor(
        _ value: RuntimeAttributeValue,
        to object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier,
        keyPath: ReferenceWritableKeyPath<CALayer, CGColor?>
    ) throws -> RuntimeAttributeMutation {
        let (layer, view) = try layer(for: object, attributeIdentifier: attributeIdentifier)
        let requested = try color(value, attributeIdentifier: attributeIdentifier).cgColor
        let original = layer[keyPath: keyPath]
        layer[keyPath: keyPath] = requested
        refresh(view)
        return RuntimeAttributeMutation(
            originalValue: colorMapper.color(from: original).map(RuntimeAttributeValue.color),
            actualValue: colorMapper.color(from: layer[keyPath: keyPath]).map(RuntimeAttributeValue.color),
            comparisonValue: colorMapper.color(from: requested).map(RuntimeAttributeValue.color),
            restore: { [weak layer, weak view] in
                guard let layer else {
                    return nil
                }
                layer[keyPath: keyPath] = original
                refresh(view)
                return colorMapper.color(from: layer[keyPath: keyPath]).map(RuntimeAttributeValue.color)
            }
        )
    }

    private func applyShadowOpacity(
        _ value: RuntimeAttributeValue,
        to object: AnyObject
    ) throws -> RuntimeAttributeMutation {
        let (layer, view) = try layer(for: object, attributeIdentifier: .shadowOpacity)
        let requested = try decimal(value, attributeIdentifier: .shadowOpacity)
        guard (0 ... 1).contains(requested) else {
            throw invalidValue(.shadowOpacity, expectation: "a number from 0 through 1")
        }
        let original = layer.shadowOpacity
        layer.shadowOpacity = Float(requested)
        refresh(view)
        return RuntimeAttributeMutation(
            originalValue: .number(Double(original)),
            actualValue: .number(Double(layer.shadowOpacity)),
            restore: { [weak layer, weak view] in
                guard let layer else {
                    return nil
                }
                layer.shadowOpacity = original
                refresh(view)
                return .number(Double(layer.shadowOpacity))
            }
        )
    }

    private func applyShadowOffset(
        _ value: RuntimeAttributeValue,
        to object: AnyObject
    ) throws -> RuntimeAttributeMutation {
        let (layer, view) = try layer(for: object, attributeIdentifier: .shadowOffset)
        let requested = try vector(value, attributeIdentifier: .shadowOffset)
        let original = layer.shadowOffset
        layer.shadowOffset = CGSize(width: requested.dx, height: requested.dy)
        refresh(view)
        return RuntimeAttributeMutation(
            originalValue: .vector(RuntimeVector(
                dx: original.width,
                dy: original.height,
                unit: .logical
            )),
            actualValue: .vector(RuntimeVector(
                dx: layer.shadowOffset.width,
                dy: layer.shadowOffset.height,
                unit: .logical
            )),
            restore: { [weak layer, weak view] in
                guard let layer else {
                    return nil
                }
                layer.shadowOffset = original
                refresh(view)
                return .vector(RuntimeVector(
                    dx: layer.shadowOffset.width,
                    dy: layer.shadowOffset.height,
                    unit: .logical
                ))
            }
        )
    }

    private func applyShadowOffsetComponent(
        _ value: RuntimeAttributeValue,
        to object: AnyObject,
        isWidth: Bool
    ) throws -> RuntimeAttributeMutation {
        let attributeIdentifier: RuntimeAttributeIdentifier = isWidth
            ? .shadowOffsetWidth
            : .shadowOffsetHeight
        let (layer, view) = try layer(for: object, attributeIdentifier: attributeIdentifier)
        let requested = try decimal(value, attributeIdentifier: attributeIdentifier)
        let original = layer.shadowOffset
        layer.shadowOffset = CGSize(
            width: isWidth ? requested : Double(original.width),
            height: isWidth ? Double(original.height) : requested
        )
        refresh(view)
        let actual = isWidth ? layer.shadowOffset.width : layer.shadowOffset.height
        let originalComponent = isWidth ? original.width : original.height
        return RuntimeAttributeMutation(
            originalValue: .number(Double(originalComponent)),
            actualValue: .number(Double(actual)),
            restore: { [weak layer, weak view] in
                guard let layer else {
                    return nil
                }
                layer.shadowOffset = original
                refresh(view)
                let restored = isWidth ? layer.shadowOffset.width : layer.shadowOffset.height
                return .number(Double(restored))
            }
        )
    }

    private func applyConstraintConstant(
        _ value: RuntimeAttributeValue,
        to object: AnyObject,
        identifier: String,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> RuntimeAttributeMutation {
        let constraint = try constraint(
            identifiedBy: identifier,
            for: object,
            attributeIdentifier: attributeIdentifier
        )
        let requested = try decimal(value, attributeIdentifier: attributeIdentifier)
        let original = constraint.constant
        constraint.constant = CGFloat(requested)
        let view = object as? UIView
        refresh(view)
        return RuntimeAttributeMutation(
            originalValue: .number(Double(original)),
            actualValue: .number(Double(constraint.constant)),
            restore: { [weak constraint, weak view] in
                guard let constraint else {
                    return nil
                }
                constraint.constant = original
                refresh(view)
                return .number(Double(constraint.constant))
            }
        )
    }

    private func layer(
        for object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> (CALayer, UIView?) {
        if let view = object as? UIView {
            return (view.layer, view)
        }
        if let layer = object as? CALayer {
            return (layer, layer.delegate as? UIView)
        }
        throw unsupported(attributeIdentifier)
    }

    private func constraint(
        identifiedBy identifier: String,
        for object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> NSLayoutConstraint {
        guard let view = object as? UIView else {
            throw unsupported(attributeIdentifier)
        }
        let matches = affectingConstraints(for: view).filter {
            $0.identifier == identifier
        }
        guard matches.count == 1, let constraint = matches.first else {
            throw RuntimeError(
                code: matches.isEmpty ? .unsupportedAttribute : .patchConflict,
                message: matches.isEmpty
                    ? "No active constraint matches the requested identifier."
                    : "Multiple active constraints use the requested identifier.",
                recoverySuggestion: "Use a unique NSLayoutConstraint identifier."
            )
        }
        return constraint
    }

    private func affectingConstraints(for view: UIView) -> [NSLayoutConstraint] {
        var constraints = [NSLayoutConstraint]()
        var seen = Set<ObjectIdentifier>()
        var owner: UIView? = view
        while let current = owner {
            for constraint in current.constraints where references(constraint, view: view) {
                if seen.insert(ObjectIdentifier(constraint)).inserted {
                    constraints.append(constraint)
                }
            }
            owner = current.superview
        }
        return constraints
    }

    private func references(_ constraint: NSLayoutConstraint, view: UIView) -> Bool {
        (constraint.firstItem as AnyObject?) === view ||
            (constraint.secondItem as AnyObject?) === view
    }

    private func constraintIdentifier(
        from attributeIdentifier: RuntimeAttributeIdentifier
    ) -> String? {
        let prefix = "ios.autoLayout.constraint."
        let suffix = ".constant"
        let value = attributeIdentifier.rawValue
        guard value.hasPrefix(prefix), value.hasSuffix(suffix) else {
            return nil
        }
        let start = value.index(value.startIndex, offsetBy: prefix.count)
        let end = value.index(value.endIndex, offsetBy: -suffix.count)
        let identifier = String(value[start ..< end])
        return identifier.isEmpty ? nil : identifier
    }

    private func string(
        _ value: RuntimeAttributeValue,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> String {
        guard case let .string(result) = value else {
            throw invalidValue(attributeIdentifier, expectation: "a string")
        }
        return result
    }

    private func decimal(
        _ value: RuntimeAttributeValue,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> Double {
        let result: Double
        switch value {
        case let .number(value):
            result = value
        case let .integer(value):
            result = Double(value)
        default:
            throw invalidValue(attributeIdentifier, expectation: "a number")
        }
        guard result.isFinite else {
            throw invalidValue(attributeIdentifier, expectation: "a finite number")
        }
        return result
    }

    private func vector(
        _ value: RuntimeAttributeValue,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> RuntimeVector {
        guard case let .vector(result) = value,
              result.dx.isFinite,
              result.dy.isFinite,
              result.unit == .logical else {
            throw invalidValue(
                attributeIdentifier,
                expectation: "a finite logical vector"
            )
        }
        return result
    }

    private func color(
        _ value: RuntimeAttributeValue,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> UIColor {
        guard case let .color(color) = value else {
            throw invalidValue(attributeIdentifier, expectation: "an sRGB or Display P3 color")
        }
        let components = [color.red, color.green, color.blue, color.alpha]
        guard components.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
            throw invalidValue(attributeIdentifier, expectation: "color components from 0 through 1")
        }
        if color.colorSpace == "display-p3" {
            return UIColor(
                displayP3Red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha
            )
        }
        guard color.colorSpace == "srgb" ||
                color.colorSpace == "extended-srgb" else {
            throw invalidValue(attributeIdentifier, expectation: "an sRGB or Display P3 color")
        }
        return UIColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }

    private func runtimeColor(_ color: UIColor?, for view: UIView) -> RuntimeColor? {
        colorMapper.color(from: color, traitCollection: view.traitCollection)
    }

    private func attributedTextToPreserve(from label: UILabel) -> NSAttributedString? {
        guard let attributedText = label.attributedText,
              attributedText.length > 0 else {
            return nil
        }
        let baselineLabel = UILabel()
        baselineLabel.font = label.font
        baselineLabel.textColor = label.textColor
        baselineLabel.textAlignment = label.textAlignment
        baselineLabel.lineBreakMode = label.lineBreakMode
        baselineLabel.shadowColor = label.shadowColor
        baselineLabel.shadowOffset = label.shadowOffset
        baselineLabel.text = label.text
        guard baselineLabel.attributedText?.isEqual(to: attributedText) != true else {
            return nil
        }
        return attributedText
    }

    private func apply(font: UIFont, to label: UILabel) {
        guard let attributedText = attributedTextToPreserve(from: label) else {
            return
        }
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        mutableText.addAttribute(
            .font,
            value: font,
            range: NSRange(location: 0, length: mutableText.length)
        )
        label.attributedText = mutableText
    }

    private func apply(textColor: UIColor, to label: UILabel) {
        guard let attributedText = attributedTextToPreserve(from: label) else {
            return
        }
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        mutableText.addAttribute(
            .foregroundColor,
            value: textColor,
            range: NSRange(location: 0, length: mutableText.length)
        )
        label.attributedText = mutableText
    }

    private func unsupported(
        _ attributeIdentifier: RuntimeAttributeIdentifier
    ) -> RuntimeError {
        RuntimeError(
            code: .unsupportedAttribute,
            message: "The Runtime cannot patch \(attributeIdentifier.rawValue) on this object.",
            recoverySuggestion: nil
        )
    }

    private func invalidValue(
        _ attributeIdentifier: RuntimeAttributeIdentifier,
        expectation: String
    ) -> RuntimeError {
        RuntimeError(
            code: .invalidAttributeValue,
            message: "\(attributeIdentifier.rawValue) requires \(expectation).",
            recoverySuggestion: nil
        )
    }

    private func refresh(_ view: UIView?) {
        guard let view else {
            return
        }
        view.setNeedsLayout()
        view.superview?.setNeedsLayout()
        view.window?.layoutIfNeeded()
    }
}
#endif
