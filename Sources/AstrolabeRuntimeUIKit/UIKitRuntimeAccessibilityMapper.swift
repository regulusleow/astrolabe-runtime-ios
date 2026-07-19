//
//  UIKitRuntimeAccessibilityMapper.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import UIKit

@MainActor
struct UIKitRuntimeAccessibilityMapper {
    func accessibilityInfo(for view: UIView) -> RuntimeAccessibility? {
        let traits = runtimeTraits(view.accessibilityTraits)
        let value = isSecureTextInput(view) ? nil : nonempty(view.accessibilityValue)
        let hasMetadata = view.isAccessibilityElement ||
            nonempty(view.accessibilityIdentifier) != nil ||
            nonempty(view.accessibilityLabel) != nil ||
            value != nil ||
            nonempty(view.accessibilityHint) != nil ||
            !traits.isEmpty
        guard hasMetadata else {
            return nil
        }

        return RuntimeAccessibility(
            element: view.isAccessibilityElement,
            identifier: nonempty(view.accessibilityIdentifier),
            label: nonempty(view.accessibilityLabel),
            value: value,
            hint: nonempty(view.accessibilityHint),
            traits: traits
        )
    }

    private func isSecureTextInput(_ view: UIView) -> Bool {
        if let textField = view as? UITextField {
            return textField.isSecureTextEntry
        }
        if let textView = view as? UITextView {
            return textView.isSecureTextEntry
        }
        if let searchBar = view as? UISearchBar {
            return searchBar.searchTextField.isSecureTextEntry
        }
        return false
    }

    func runtimeTraits(_ traits: UIAccessibilityTraits) -> [String] {
        let mappings: [(UIAccessibilityTraits, String)] = [
            (.button, "button"),
            (.link, "link"),
            (.header, "header"),
            (.selected, "selected"),
            (.image, "image"),
            (.searchField, "searchField"),
            (.keyboardKey, "keyboardKey"),
            (.staticText, "staticText"),
            (.notEnabled, "notEnabled"),
            (.adjustable, "adjustable")
        ]
        return mappings.compactMap { source, target in
            traits.contains(source) ? target : nil
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
#endif
