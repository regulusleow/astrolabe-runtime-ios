#if canImport(UIKit)
import AstrolabeProtocol
import Foundation
import SwiftUI

/// Reads proven Text storage, then freezes public values without traversing Foundation's private rope.
@available(iOS 26.0, *)
@MainActor
enum SwiftUITextRunProjector {
    struct Projection {
        /// Complete bounded source runs, or nil when the storage was refused.
        let field: RuntimeSemanticTextField?
        /// Paths identify missing styles without including business values.
        let issues: [RuntimeInspectionIssue]
    }

    private struct Style {
        /// Resolved current font, absent when unknown or unavailable.
        var font: [RuntimeAttribute]?
        /// Resolved pure foreground, absent for unsupported styles.
        var color: RuntimeColor?
        /// Proven source of the current font.
        var fontPath: String?
        /// Proven source of the current pure color.
        var colorPath: String?
    }

    /// shortcut: storage fields are verified on iOS27.0 arm64 simulators/devices; validate other targets before widening.
    private static var supportsCurrentLayout: Bool {
        #if arch(arm64) && !targetEnvironment(macCatalyst)
        guard !ProcessInfo.processInfo.isiOSAppOnMac else { return false }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion == 27 && version.minorVersion == 0
        #else
        return false
        #endif
    }

    static func project(_ text: Text, path: String, depth: Int, environment: EnvironmentValues,
                        local: inout UIKitSemanticTraversalBudget,
                        budget: inout UIKitSemanticTraversalBudget) throws -> Projection? {
        guard supportsCurrentLayout else { return nil }

        func fields(_ value: Any, depth: Int) -> [Mirror.Child]? {
            guard local.consume(depth: depth), budget.consume(depth: depth) else { return nil }
            let children = Array(Mirror(reflecting: value).children.prefix(51))
            guard children.count <= 50 else { local.markTruncated(); return nil }
            return children
        }
        guard let textFields = fields(text, depth: depth),
              let storage = textFields.first(where: { $0.label == "storage" })?.value,
              let storageFields = fields(storage, depth: depth + 1), storageFields.count == 1,
              storageFields[0].label == "anyTextStorage" else { return nil }
        let storageType = String(reflecting: type(of: storageFields[0].value))
        guard storageType == "SwiftUI.AttributedStringTextStorage" || SwiftUITextRunPolicy.isConcatenatedStorage(storageType) else { return nil }

        var issues: [RuntimeInspectionIssue] = []
        var runs: [RuntimeTextRun] = []
        var bytes = 0
        var location: Int64 = 0
        func issue(_ code: String, _ path: String) { issues.append(semanticIssue(code, path: path)) }
        func color(_ value: Color, path: String, depth: Int) throws -> RuntimeColor? {
            guard let provider = SwiftUIEnvironmentStyleReader.field(value, "provider", depth: depth, local: &local, budget: &budget),
                  SwiftUIEnvironmentColorReader.supportsColorProvider(provider, depth: depth + 1, local: &local, budget: &budget),
                  local.consume(depth: depth + 2), budget.consume(depth: depth + 2),
                  let field = try SwiftUIEnvironmentColorReader.resolvedField(value.resolve(in: environment), path: path),
                  case let .color(result) = field.attribute.value else { return nil }
            return result
        }
        func font(_ value: Font, depth: Int) -> [RuntimeAttribute]? {
            guard local.consume(depth: depth), budget.consume(depth: depth) else { return nil }
            return SwiftUIFontProjector.attributes(value, environment: environment)
        }
        func modifiers(_ values: [Any], inherited: Style, path: String, depth: Int) throws -> Style? {
            guard values.count <= 32 else { local.markTruncated(); return nil }
            var result = inherited
            var hasColor = false
            var hasForeground = false
            for (index, value) in values.enumerated() {
                let modifierPath = path + "/\(index)"
                guard String(reflecting: type(of: value)) == "SwiftUI.Text.Modifier",
                      let children = fields(value, depth: depth), children.count == 1,
                      let name = children[0].label else { return nil }
                let payload = children[0].value
                switch name {
                case "font":
                    guard String(reflecting: type(of: payload)) == "Swift.Optional<SwiftUI.Font>",
                          let entries = fields(payload, depth: depth + 1), entries.count <= 1 else { return nil }
                    result.font = entries.first.flatMap { $0.value as? Font }.flatMap { font($0, depth: depth + 2) }
                    result.fontPath = modifierPath + "/font"
                case "color":
                    hasColor = true
                    guard String(reflecting: type(of: payload)) == "Swift.Optional<SwiftUI.Color>",
                          let entries = fields(payload, depth: depth + 1), entries.count <= 1 else { return nil }
                    result.color = try entries.first.flatMap { $0.value as? Color }.flatMap { try color($0, path: modifierPath + "/color", depth: depth + 2) }
                    result.colorPath = modifierPath + "/color"
                case "anyTextModifier":
                    hasForeground = true
                    guard String(reflecting: type(of: payload)) == "SwiftUI.TextForegroundStyleModifier" else { return nil }
                    let source = modifierPath + "/anyTextModifier"
                    let projected = SwiftUITextRunPolicy.canUseEnvironmentForeground(path: inherited.colorPath) ?
                        try SwiftUIForegroundStyleProjector.projectModifier(payload, path: source,
                            depth: depth + 1, environment: environment, local: &local, budget: &budget) : nil
                    if case let .color(value) = projected?.attribute.value { result.color = value } else { result.color = nil }
                    result.colorPath = projected?.path ?? source
                case "kerning", "tracking", "baseline":
                    guard let value = payload as? CGFloat, value.isFinite else { return nil }
                default: return nil
                }
            }
            if hasColor && hasForeground {
                result.color = nil
                issue("ambiguousTextScope", path)
            }
            return result
        }
        func append(_ text: String, style: Style, path: String, depth: Int) throws -> Bool {
            guard !text.isEmpty else { return true }
            guard runs.count < SwiftUITextRunPolicy.maximumRuns,
                  text.utf8.count <= SwiftUITextRunPolicy.maximumUTF8Bytes - bytes,
                  local.consume(depth: depth), budget.consume(depth: depth) else { local.markTruncated(); return false }
            var name: String?
            var size: RuntimeMeasurement?
            for attribute in style.font ?? [] {
                if attribute.identifier.rawValue == "common.text.fontName", case let .string(value) = attribute.value { name = value }
                if attribute.identifier.rawValue == "common.text.fontSize", case let .measurement(value) = attribute.value { size = value }
            }
            var extensions: [String: RuntimeJSONValue] = ["ios.swiftui.rangeUnit": .string("utf16"), "ios.swiftui.sourcePath": .string(path)]
            if size != nil, let path = style.fontPath { extensions["ios.swiftui.fontSourcePath"] = .string(path) }
            if style.color != nil, let path = style.colorPath { extensions["ios.swiftui.colorSourcePath"] = .string(path) }
            runs.append(RuntimeTextRun(range: .init(location: location, length: Int64(text.utf16.count)), text: text,
                fontName: name, fontFamilyName: nil, fontSize: size, color: style.color, extensions: try .init(values: extensions)))
            if size == nil { issue("fontUnavailable", path) }
            if style.color == nil { issue("colorUnavailable", path) }
            bytes += text.utf8.count
            location += Int64(text.utf16.count)
            return true
        }
        func visit(_ text: Text, inherited: Style, path: String, depth: Int, ancestors: Set<ObjectIdentifier>) throws -> Bool {
            guard let entries = fields(text, depth: depth), entries.count == 2,
                  let storage = entries.first(where: { $0.label == "storage" })?.value,
                  let values = entries.first(where: { $0.label == "modifiers" })?.value as? [Any],
                  let style = try modifiers(values, inherited: inherited, path: path + "/modifiers", depth: depth + 1),
                  let contents = fields(storage, depth: depth + 1), contents.count == 1 else { return false }
            if contents[0].label == "verbatim", let value = contents[0].value as? String {
                return try append(value, style: style, path: path + "/storage/verbatim", depth: depth + 2)
            }
            guard contents[0].label == "anyTextStorage" else { return false }
            let value = contents[0].value
            let type = String(reflecting: Swift.type(of: value))
            guard type == "SwiftUI.AttributedStringTextStorage" || SwiftUITextRunPolicy.isConcatenatedStorage(type) else { return false }
            let identity = ObjectIdentifier(value as AnyObject)
            guard !ancestors.contains(identity), let children = fields(value, depth: depth + 2) else { return false }
            var ancestors = ancestors
            ancestors.insert(identity)
            let storagePath = path + "/storage/anyTextStorage"
            if type == "SwiftUI.AttributedStringTextStorage" {
                guard children.count == 1, children[0].label == "str", let attributed = children[0].value as? AttributedString else { return false }
                guard attributed.utf8.prefix(SwiftUITextRunPolicy.maximumUTF8Bytes + 1).count <= SwiftUITextRunPolicy.maximumUTF8Bytes else {
                    local.markTruncated(); return false
                }
                for (index, run) in attributed.runs.enumerated() {
                    guard index < SwiftUITextRunPolicy.maximumRuns else { local.markTruncated(); return false }
                    var current = style
                    let runPath = storagePath + "/str/runs/\(index)"
                    if let value = run.swiftUI.font {
                        current.font = font(value, depth: depth + 4)
                        current.fontPath = runPath + "/font"
                    }
                    if let value = run.swiftUI.foregroundColor {
                        current.color = try color(value, path: runPath + "/foregroundColor", depth: depth + 4)
                        current.colorPath = runPath + "/foregroundColor"
                    }
                    // Other framework scopes may affect Text; never substitute an inherited value for an unverified explicit one.
                    if run.swiftUI.font == nil && run.uiKit.font != nil { current.font = nil }
                    if run.swiftUI.foregroundColor == nil && run.uiKit.foregroundColor != nil { current.color = nil }
                    if run.inlinePresentationIntent != nil { current.font = nil }
                    if run.link != nil { current.color = nil }
                    guard try append(String(attributed[run.range].characters), style: current, path: runPath, depth: depth + 4) else { return false }
                }
                return true
            }
            guard children.count == 2,
                  let first = children.first(where: { $0.label == "first" })?.value as? Text,
                  let second = children.first(where: { $0.label == "second" })?.value as? Text else { return false }
            return try visit(first, inherited: style, path: storagePath + "/first", depth: depth + 3, ancestors: ancestors) &&
                visit(second, inherited: style, path: storagePath + "/second", depth: depth + 3, ancestors: ancestors)
        }
        var inherited = Style()
        if let value = environment.font {
            inherited.font = font(value, depth: 1)
            inherited.fontPath = "environment/font"
        }
        if let field = try SwiftUIForegroundStyleProjector.projectEnvironment(environment, local: &local, budget: &budget),
           case let .color(value) = field.attribute.value {
            inherited.color = value
            inherited.colorPath = field.path
        }
        guard try visit(text, inherited: inherited, path: path, depth: depth, ancestors: []),
              SwiftUITextRunPolicy.valid(runs), !local.truncated, !budget.truncated else {
            issue(local.truncated || budget.truncated ? "budgetExceeded" : "unsupportedLayout", path)
            return Projection(field: nil, issues: issues)
        }
        let attribute = RuntimeAttribute(identifier: try .init(rawValue: "ios.swiftui.text.attributedTextRuns"), value: .textRuns(runs))
        return Projection(field: try RuntimeSemanticTextField(path: path + "/storage", attribute: attribute), issues: issues)
    }
}
#endif
