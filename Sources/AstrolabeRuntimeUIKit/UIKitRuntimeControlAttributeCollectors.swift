//
//  UIKitRuntimeControlAttributeCollectors.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import UIKit

struct UIKitLabelAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.label

    func supports(_ object: AnyObject) -> Bool {
        object is UILabel
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let label = object as? UILabel else {
            return []
        }
        var attributes = [
            attribute(.numberOfLines, .integer(Int64(label.numberOfLines))),
            attribute(.textAlignment, .string(textAlignmentName(label.textAlignment))),
            attribute(.lineBreakMode, .string(lineBreakModeName(label.lineBreakMode))),
            attribute(
                .adjustsFontSizeToFitWidth,
                .boolean(label.adjustsFontSizeToFitWidth)
            )
        ]
        if let text = nonempty(label.attributedText?.string ?? label.text) {
            attributes.insert(attribute(.text, .string(text)), at: 0)
        }
        if let font = uniformFont(for: label) {
            attributes.append(attribute(.fontName, .string(font.fontName)))
            attributes.append(
                attribute(.fontFamilyName, .string(font.familyName))
            )
            if !label.adjustsFontSizeToFitWidth {
                attributes.append(
                    attribute(
                        .fontSize,
                        .measurement(
                            RuntimeMeasurement(
                                value: font.pointSize,
                                unit: .logical
                            )
                        )
                    )
                )
            }
        }
        if let textColor = uniformTextColor(for: label),
           let color = context.colorMapper.color(
               from: textColor,
               traitCollection: label.traitCollection
           ) {
            attributes.append(attribute(.textColor, .color(color)))
        }
        if let runs = attributedTextRuns(for: label, context: context) {
            attributes.append(attribute(.attributedTextRuns, .textRuns(runs)))
        }
        return attributes
    }

    private func attributedTextRuns(
        for label: UILabel,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeTextRun]? {
        guard let attributedText = label.attributedText,
              attributedText.length > 0 else {
            return nil
        }

        var runs = [RuntimeTextRun]()
        attributedText.enumerateAttributes(
            in: NSRange(location: 0, length: attributedText.length)
        ) { values, range, _ in
            guard let font = values[.font] as? UIFont ?? label.font else {
                return
            }
            let textColor = values[.foregroundColor] as? UIColor ?? label.textColor
            runs.append(
                RuntimeTextRun(
                    range: RuntimeTextRange(
                        location: Int64(range.location),
                        length: Int64(range.length)
                    ),
                    text: attributedText.attributedSubstring(
                        from: range
                    ).string,
                    fontName: font.fontName,
                    fontFamilyName: font.familyName,
                    fontSize: label.adjustsFontSizeToFitWidth ? nil :
                        RuntimeMeasurement(
                            value: font.pointSize,
                            unit: .logical
                        ),
                    color: context.colorMapper.color(
                        from: textColor,
                        traitCollection: label.traitCollection
                    ),
                    extensions: textRunExtensions(
                        values: values,
                        paragraphStyle: values[.paragraphStyle]
                            as? NSParagraphStyle
                    )
                )
            )
        }
        return runs
    }

    private func uniformFont(for label: UILabel) -> UIFont? {
        guard let font = label.font else {
            return nil
        }
        return uniformAttribute(
            .font,
            in: label.attributedText,
            fallback: font
        )
    }

    private func uniformTextColor(for label: UILabel) -> UIColor? {
        uniformAttribute(
            .foregroundColor,
            in: label.attributedText,
            fallback: label.textColor
        )
    }

    private func uniformAttribute<Value: NSObject>(
        _ key: NSAttributedString.Key,
        in attributedText: NSAttributedString?,
        fallback: Value
    ) -> Value? {
        guard let attributedText, attributedText.length > 0 else {
            return fallback
        }

        var uniformValue: Value?
        var isUniform = true
        attributedText.enumerateAttribute(
            key,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, stop in
            let resolvedValue = value as? Value ?? fallback
            if let uniformValue,
               !uniformValue.isEqual(resolvedValue) {
                isUniform = false
                stop.pointee = true
            } else {
                uniformValue = resolvedValue
            }
        }
        return isUniform ? uniformValue : nil
    }
}

private func textRunExtensions(
    values: [NSAttributedString.Key: Any],
    paragraphStyle: NSParagraphStyle?
) -> RuntimeExtensionMap {
    var result = [String: RuntimeJSONValue]()
    if let paragraphStyle {
        result["ios.paragraphStyle.alignment"] = .string(
            textAlignmentName(paragraphStyle.alignment)
        )
        result["ios.paragraphStyle.lineBreakMode"] = .string(
            lineBreakModeName(paragraphStyle.lineBreakMode)
        )
        result["ios.paragraphStyle.lineSpacing"] = .number(
            paragraphStyle.lineSpacing
        )
        result["ios.paragraphStyle.paragraphSpacing"] = .number(
            paragraphStyle.paragraphSpacing
        )
        result["ios.paragraphStyle.paragraphSpacingBefore"] = .number(
            paragraphStyle.paragraphSpacingBefore
        )
        result["ios.paragraphStyle.firstLineHeadIndent"] = .number(
            paragraphStyle.firstLineHeadIndent
        )
        result["ios.paragraphStyle.headIndent"] = .number(
            paragraphStyle.headIndent
        )
        result["ios.paragraphStyle.tailIndent"] = .number(
            paragraphStyle.tailIndent
        )
        result["ios.paragraphStyle.minimumLineHeight"] = .number(
            paragraphStyle.minimumLineHeight
        )
        result["ios.paragraphStyle.maximumLineHeight"] = .number(
            paragraphStyle.maximumLineHeight
        )
        result["ios.paragraphStyle.lineHeightMultiple"] = .number(
            paragraphStyle.lineHeightMultiple
        )
    }
    if let value = decimalAttribute(.kern, in: values) {
        result["ios.textRun.kern"] = .number(value)
    }
    if let value = decimalAttribute(.baselineOffset, in: values) {
        result["ios.textRun.baselineOffset"] = .number(value)
    }
    if let value = integerAttribute(.underlineStyle, in: values) {
        result["ios.textRun.underlineStyle"] = .integer(value)
    }
    if let value = integerAttribute(.strikethroughStyle, in: values) {
        result["ios.textRun.strikethroughStyle"] = .integer(value)
    }
    do {
        return try RuntimeExtensionMap(values: result)
    } catch {
        preconditionFailure("Invalid built-in iOS attributed-text extension")
    }
}

private func decimalAttribute(
    _ key: NSAttributedString.Key,
    in values: [NSAttributedString.Key: Any]
) -> Double? {
    (values[key] as? NSNumber)?.doubleValue
}

private func integerAttribute(
    _ key: NSAttributedString.Key,
    in values: [NSAttributedString.Key: Any]
) -> Int64? {
    (values[key] as? NSNumber)?.int64Value
}

struct UIKitImageViewAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.imageView

    func supports(_ object: AnyObject) -> Bool {
        object is UIImageView
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let imageView = object as? UIImageView else {
            return []
        }
        var attributes = [
            attribute(.imagePresent, .boolean(imageView.image != nil))
        ]
        if let image = imageView.image {
            attributes.append(attribute(.imageSize, .size(runtimeSize(image.size))))
            attributes.append(attribute(.imageScale, .number(image.scale)))
            attributes.append(
                attribute(
                    .imageRenderingMode,
                    .string(imageRenderingModeName(image.renderingMode))
                )
            )
        }
        return attributes
    }
}

struct UIKitControlAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.control

    func supports(_ object: AnyObject) -> Bool {
        object is UIControl
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let control = object as? UIControl else {
            return []
        }
        return [
            attribute(.enabled, .boolean(control.isEnabled)),
            attribute(.selected, .boolean(control.isSelected)),
            attribute(.highlighted, .boolean(control.isHighlighted)),
            attribute(
                .horizontalAlignment,
                .string(horizontalAlignmentName(control.contentHorizontalAlignment))
            ),
            attribute(
                .verticalAlignment,
                .string(verticalAlignmentName(control.contentVerticalAlignment))
            )
        ]
    }
}

struct UIKitButtonAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.button

    func supports(_ object: AnyObject) -> Bool {
        object is UIButton
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let button = object as? UIButton else {
            return []
        }
        var attributes = [RuntimeAttribute]()
        if let title = nonempty(button.currentTitle) {
            attributes.append(attribute(.buttonTitle, .string(title)))
        }
        if let configuration = button.configuration {
            attributes.append(
                attribute(
                    .contentInsets,
                    .insets(runtimeEdgeInsets(configuration.contentInsets))
                )
            )
        }
        return attributes
    }
}

struct UIKitTextInputAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.textInput

    func supports(_ object: AnyObject) -> Bool {
        object is UITextField || object is UITextView || object is UISearchBar
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        if let textField = object as? UITextField {
            return textFieldAttributes(textField)
        }
        if let searchBar = object as? UISearchBar {
            return searchBarAttributes(searchBar)
        }
        guard let textView = object as? UITextView else {
            return []
        }
        return textViewAttributes(textView)
    }

    private func textFieldAttributes(_ textField: UITextField) -> [RuntimeAttribute] {
        var attributes = commonAttributes(
            text: textField.text,
            isSecureTextEntry: textField.isSecureTextEntry,
            keyboardType: textField.keyboardType
        )
        if let placeholder = nonempty(textField.placeholder) {
            attributes.append(attribute(.placeholder, .string(placeholder)))
        }
        return attributes
    }

    private func textViewAttributes(_ textView: UITextView) -> [RuntimeAttribute] {
        commonAttributes(
            text: textView.text,
            isSecureTextEntry: textView.isSecureTextEntry,
            keyboardType: textView.keyboardType
        )
    }

    private func searchBarAttributes(_ searchBar: UISearchBar) -> [RuntimeAttribute] {
        var attributes = commonAttributes(
            text: searchBar.text,
            isSecureTextEntry: searchBar.searchTextField.isSecureTextEntry,
            keyboardType: searchBar.keyboardType
        )
        if let placeholder = nonempty(searchBar.placeholder) {
            attributes.append(attribute(.placeholder, .string(placeholder)))
        }
        return attributes
    }

    private func commonAttributes(
        text: String?,
        isSecureTextEntry: Bool,
        keyboardType: UIKeyboardType
    ) -> [RuntimeAttribute] {
        var attributes = [
            attribute(.isSecureTextEntry, .boolean(isSecureTextEntry)),
            attribute(.keyboardType, .string(keyboardTypeName(keyboardType)))
        ]
        if !isSecureTextEntry, let text = nonempty(text) {
            attributes.insert(attribute(.inputText, .string(text)), at: 0)
        }
        return attributes
    }
}

struct UIKitScrollViewAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.scrollView

    func supports(_ object: AnyObject) -> Bool {
        object is UIScrollView
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let scrollView = object as? UIScrollView else {
            return []
        }
        return [
            attribute(.contentSize, .size(runtimeSize(scrollView.contentSize))),
            attribute(.contentOffset, .point(runtimePoint(scrollView.contentOffset))),
            attribute(.contentInset, .insets(runtimeEdgeInsets(scrollView.contentInset))),
            attribute(
                .adjustedContentInset,
                .insets(runtimeEdgeInsets(scrollView.adjustedContentInset))
            ),
            attribute(.isScrollEnabled, .boolean(scrollView.isScrollEnabled)),
            attribute(.isPagingEnabled, .boolean(scrollView.isPagingEnabled)),
            attribute(
                .showsHorizontalScrollIndicator,
                .boolean(scrollView.showsHorizontalScrollIndicator)
            ),
            attribute(
                .showsVerticalScrollIndicator,
                .boolean(scrollView.showsVerticalScrollIndicator)
            )
        ]
    }
}

struct UIKitStackViewAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.stackView

    func supports(_ object: AnyObject) -> Bool {
        object is UIStackView
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let stackView = object as? UIStackView else {
            return []
        }
        return [
            attribute(.stackAxis, .string(axisName(stackView.axis))),
            attribute(.stackAlignment, .string(alignmentName(stackView.alignment))),
            attribute(
                .stackDistribution,
                .string(distributionName(stackView.distribution))
            ),
            attribute(.stackSpacing, .number(stackView.spacing))
        ]
    }
}

private func nonempty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
        return nil
    }
    return value
}

private func textAlignmentName(_ alignment: NSTextAlignment) -> String {
    switch alignment {
    case .left: return "left"
    case .center: return "center"
    case .right: return "right"
    case .justified: return "justified"
    case .natural: return "natural"
    @unknown default: return "unknown:\(alignment.rawValue)"
    }
}

private func lineBreakModeName(_ mode: NSLineBreakMode) -> String {
    switch mode {
    case .byWordWrapping: return "wordWrapping"
    case .byCharWrapping: return "characterWrapping"
    case .byClipping: return "clipping"
    case .byTruncatingHead: return "truncatingHead"
    case .byTruncatingTail: return "truncatingTail"
    case .byTruncatingMiddle: return "truncatingMiddle"
    @unknown default: return "unknown:\(mode.rawValue)"
    }
}

private func imageRenderingModeName(_ mode: UIImage.RenderingMode) -> String {
    switch mode {
    case .automatic: return "automatic"
    case .alwaysOriginal: return "alwaysOriginal"
    case .alwaysTemplate: return "alwaysTemplate"
    @unknown default: return "unknown:\(mode.rawValue)"
    }
}

private func horizontalAlignmentName(_ alignment: UIControl.ContentHorizontalAlignment) -> String {
    switch alignment {
    case .center: return "center"
    case .left: return "left"
    case .right: return "right"
    case .fill: return "fill"
    case .leading: return "leading"
    case .trailing: return "trailing"
    @unknown default: return "unknown:\(alignment.rawValue)"
    }
}

private func verticalAlignmentName(_ alignment: UIControl.ContentVerticalAlignment) -> String {
    switch alignment {
    case .center: return "center"
    case .top: return "top"
    case .bottom: return "bottom"
    case .fill: return "fill"
    @unknown default: return "unknown:\(alignment.rawValue)"
    }
}

private func keyboardTypeName(_ type: UIKeyboardType) -> String {
    switch type {
    case .default: return "default"
    case .asciiCapable: return "asciiCapable"
    case .numbersAndPunctuation: return "numbersAndPunctuation"
    case .URL: return "url"
    case .numberPad: return "numberPad"
    case .phonePad: return "phonePad"
    case .namePhonePad: return "namePhonePad"
    case .emailAddress: return "emailAddress"
    case .decimalPad: return "decimalPad"
    case .twitter: return "twitter"
    case .webSearch: return "webSearch"
    case .asciiCapableNumberPad: return "asciiCapableNumberPad"
    @unknown default: return "unknown:\(type.rawValue)"
    }
}

private func axisName(_ axis: NSLayoutConstraint.Axis) -> String {
    switch axis {
    case .horizontal: return "horizontal"
    case .vertical: return "vertical"
    @unknown default: return "unknown:\(axis.rawValue)"
    }
}

private func alignmentName(_ alignment: UIStackView.Alignment) -> String {
    switch alignment {
    case .fill: return "fill"
    case .leading: return "leading"
    case .top: return "top"
    case .firstBaseline: return "firstBaseline"
    case .center: return "center"
    case .trailing: return "trailing"
    case .bottom: return "bottom"
    case .lastBaseline: return "lastBaseline"
    @unknown default: return "unknown:\(alignment.rawValue)"
    }
}

private func distributionName(_ distribution: UIStackView.Distribution) -> String {
    switch distribution {
    case .fill: return "fill"
    case .fillEqually: return "fillEqually"
    case .fillProportionally: return "fillProportionally"
    case .equalSpacing: return "equalSpacing"
    case .equalCentering: return "equalCentering"
    @unknown default: return "unknown:\(distribution.rawValue)"
    }
}
#endif
