#if canImport(UIKit)
import AstrolabeProtocol
import CoreText
import SwiftUI
import UIKit

/// Only the iOS 27.0 type/field layouts verified by the standalone probe are reflected.
@MainActor
enum SwiftUITextAttachmentProjector {
    struct Projection {
        /// Frozen candidates, preserving original and combined-cache sources.
        let candidates: [RuntimeSemanticTextCandidate]
        /// Proven unambiguous original Text attributes, never combined-cache styles.
        let canonicalAttributes: [RuntimeAttribute]
        /// Missing or refused fields; paths contain no business values.
        let issues: [RuntimeInspectionIssue]
        /// Whether local or shared traversal/output work was refused.
        let truncated: Bool
    }

    static func project(node: NSObject, budget: inout UIKitSemanticTraversalBudget, outputBytes: inout Int) throws -> Projection {
        var local = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 1_500)
        var issues: [RuntimeInspectionIssue] = []
        var fields: [String: [RuntimeSemanticTextField]] = [:]
        var scopeProof = SwiftUITextScopeProof()
        var outputStopped = false
        var pending: [(value: Any, path: String, depth: Int, ancestors: Set<ObjectIdentifier>)] = []
        guard NSStringFromClass(type(of: node)) == "SwiftUI.AccessibilityNode",
              ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27,
              ProcessInfo.processInfo.operatingSystemVersion.minorVersion == 0 else {
            return Projection(candidates: [], canonicalAttributes: [], issues: [semanticIssue("unsupportedLayout")], truncated: false)
        }
        guard local.consume(depth: 0), budget.consume(depth: 0) else {
            return Projection(candidates: [], canonicalAttributes: [], issues: [semanticIssue("budgetExceeded")], truncated: true)
        }
        // The public label getter is read by the AX collector before this bounded reflection.
        let nodeFields = Array(Mirror(reflecting: node).children.prefix(51))
        if nodeFields.count > 50 { local.markTruncated(); scopeProof.markUnknownOriginalBranch() }
        let environment = nodeFields.prefix(50).first { $0.label == "environment" }?.value as? EnvironmentValues
        for field in nodeFields.prefix(50) {
            if let name = field.label, name == "attachmentsStorage" || name == "cachedCombinedAttachment" {
                pending.append((field.value, name, 1, []))
            }
        }
        if pending.isEmpty { issues.append(semanticIssue("unsupportedLayout")) }
        var cursor = 0
        while cursor < pending.count {
            let entry = pending[cursor]
            cursor += 1
            guard local.consume(depth: entry.depth), budget.consume(depth: entry.depth) else {
                if local.visits >= local.maxVisits || budget.visits >= budget.maxVisits { break }
                continue
            }
            let typeName = String(reflecting: type(of: entry.value))
            let isOriginal = entry.path.hasPrefix("attachmentsStorage/")
            if isOriginal && typeName == "SwiftUI.Text" { scopeProof.recordOriginalText(path: entry.path) }
            // Proven bit-set metadata is a leaf, never projected as render visibility or traits.
            if SwiftUITextMetadataPolicy.isLeaf(typeName) { continue }
            let isTextField = entry.path.contains("/texts/") || entry.path.contains("/layoutProperties/")
            var attributes: [RuntimeAttribute] = []
            var isLeaf = false
            func attribute(_ name: String, _ value: RuntimeAttributeValue) -> RuntimeAttribute {
                RuntimeAttribute(identifier: try! .init(rawValue: name), value: value)
            }
            if isTextField, typeName == "SwiftUI.Font", let font = entry.value as? Font {
                isLeaf = true
                if #available(iOS 26.0, *), let environment {
                    let resolved = font.resolve(in: environment.fontResolutionContext)
                    let size = Double(resolved.pointSize)
                    if size.isFinite && size > 0 {
                        attributes = [attribute("common.text.fontName", .string(CTFontCopyPostScriptName(resolved.ctFont) as String)),
                                      attribute("common.text.fontSize", .measurement(.init(value: size, unit: .scaledLogical))),
                                      attribute("ios.swiftui.text.isBold", .boolean(resolved.isBold)),
                                      attribute("ios.swiftui.text.isMonospaced", .boolean(resolved.isMonospaced))]
                    } else { issues.append(semanticIssue("invalidValue", path: entry.path)) }
                } else { issues.append(semanticIssue("environmentUnavailable", path: entry.path)) }
            } else if isTextField, typeName == "SwiftUI.Color", let color = entry.value as? Color {
                isLeaf = true
                if #available(iOS 17.0, *), let environment {
                    let resolved = color.resolve(in: environment)
                    let rgba = [resolved.red, resolved.green, resolved.blue, resolved.opacity].map(Double.init)
                    if rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                        attributes = [attribute("common.text.color", .color(.init(colorSpace: "srgb", red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])))]
                    } else { issues.append(semanticIssue("colorOutOfRange", path: entry.path)) }
                } else { issues.append(semanticIssue("environmentUnavailable", path: entry.path)) }
            } else if isTextField, typeName == "Swift.String", let string = entry.value as? String {
                isLeaf = true
                if string.utf8.count <= 16_384 {
                    let name = entry.path.contains("/key/") ? "ios.swiftui.text.localizedKey" :
                        (entry.path.contains("/verbatim") ? "common.text.content" : "ios.swiftui.text.unknownString")
                    attributes = [attribute(name, .string(string))]
                } else { issues.append(semanticIssue("valueTooLarge", path: entry.path)) }
            } else if isTextField, typeName == "Swift.Bool", let value = entry.value as? Bool {
                isLeaf = true
                attributes = [attribute("ios.swiftui.text." + fieldName(entry.path), .boolean(value))]
            } else if isTextField, ["Swift.Double", "CoreGraphics.CGFloat", "Swift.Int"].contains(typeName) {
                isLeaf = true
                let value = (entry.value as? Double) ?? (entry.value as? CGFloat).map(Double.init) ?? (entry.value as? Int).map(Double.init)
                if let value, value.isFinite, !entry.path.hasSuffix("/lineLimit/some") || value >= 0 {
                    attributes = [attribute("ios.swiftui.text." + fieldName(entry.path), .number(value))]
                } else { issues.append(semanticIssue("invalidValue", path: entry.path)) }
            }
            let parts = entry.path.split(separator: "/")
            let root = parts.first == "attachmentsStorage" ? parts.prefix(2).joined(separator: "/") + "/attachment" : "cachedCombinedAttachment/some"
            for attribute in attributes {
                let field = try RuntimeSemanticTextField(path: entry.path, attribute: attribute)
                let size = try JSONEncoder().encode(field).count
                guard outputBytes + size <= 4 * 1024 * 1024, fields[root, default: []].count < 1_500 else {
                    local.markTruncated()
                    outputStopped = true
                    break
                }
                outputBytes += size
                fields[root, default: []].append(field)
            }
            if outputStopped { break }
            if isLeaf { continue }
            guard let allowedFields = fieldsForTraversal(typeName: typeName) else {
                issues.append(semanticIssue("unsupportedLayout", path: entry.path))
                if isOriginal { scopeProof.markUnknownOriginalBranch() }
                continue
            }
            // Empty field sets mean scalar/Font/Color leaves; only verified arrays expose all items.
            if allowedFields.isEmpty && !typeName.hasPrefix("Swift.Array<") { continue }
            // Whitelist is checked before constructing Mirror for private values.
            let mirror = Mirror(reflecting: entry.value)
            if String(describing: mirror.displayStyle).contains("foreignReference") {
                issues.append(semanticIssue("unsupportedLayout", path: entry.path))
                if isOriginal { scopeProof.markUnknownOriginalBranch() }
                continue
            }
            var ancestors = entry.ancestors
            if mirror.displayStyle == .class {
                let allowed = typeName == "SwiftUI.MutableBox<SwiftUI.TextLayoutProperties>" ||
                    (typeName.hasPrefix("SwiftUI.") && typeName.hasSuffix(".LocalizedTextStorage"))
                guard allowed else {
                    issues.append(semanticIssue("unsupportedLayout", path: entry.path))
                    if isOriginal { scopeProof.markUnknownOriginalBranch() }
                    continue
                }
                guard ancestors.insert(ObjectIdentifier(entry.value as AnyObject)).inserted else {
                    issues.append(semanticIssue("repeatedReference", path: entry.path)); continue
                }
            }
            let children = Array(mirror.children.prefix(51))
            if typeName == "SwiftUI.LocalizedStringKey" {
                let formattingValue = children.prefix(50).first { $0.label == "hasFormatting" }?.value
                let formatting = formattingValue.flatMap { String(reflecting: type(of: $0)) == "Swift.Bool" ? $0 as? Bool : nil }
                let arguments = children.prefix(50).first { $0.label == "arguments" }?.value
                let argumentType = arguments.map { String(reflecting: type(of: $0)) }
                // Only collection shape is read. FormatArgument values are never reflected or evaluated.
                let empty = argumentType == "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>" ? (arguments as? [Any])?.isEmpty : nil
                if !SwiftUITextMetadataPolicy.localizedKeyHasNoHiddenText(hasFormatting: formatting, argumentsType: argumentType, argumentsAreEmpty: empty) {
                    issues.append(semanticIssue("unsupportedLayout", path: entry.path))
                    if isOriginal { scopeProof.markUnknownOriginalBranch() }
                }
            }
            for (index, child) in children.enumerated() {
                guard index < 50, pending.count < 1_500 else { local.markTruncated(); break }
                let childType = String(reflecting: type(of: child.value))
                let isEmpty = childType == "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>" ? (child.value as? [Any])?.isEmpty : nil
                if SwiftUITextMetadataPolicy.canIgnoreField(container: typeName, field: child.label, type: childType,
                                                            isEmptyCollection: isEmpty, booleanValue: childType == "Swift.Bool" ? child.value as? Bool : nil) { continue }
                guard scopeProof.allowsField(child.label, permitted: allowedFields, isArray: typeName.hasPrefix("Swift.Array<"), isOriginal: isOriginal) else {
                    issues.append(semanticIssue("unsupportedLayout", path: entry.path + "/" + (child.label ?? String(index))))
                    continue
                }
                pending.append((child.value, entry.path + "/" + (child.label ?? String(index)), entry.depth + 1, ancestors))
            }
        }
        if local.truncated || budget.truncated { issues.append(semanticIssue("budgetExceeded")) }
        let candidates = try fields.keys.sorted().map { path -> RuntimeSemanticTextCandidate in
            let values = fields[path] ?? []
            var missing: [RuntimeInspectionIssue] = []
            let hasText = values.contains { ["common.text.content", "ios.swiftui.text.localizedKey"].contains($0.attribute.identifier.rawValue) }
            if hasText && !values.contains(where: { $0.attribute.identifier.rawValue == "common.text.fontSize" }) { missing.append(semanticIssue("fontUnavailable", path: path)) }
            if hasText && !values.contains(where: { $0.attribute.identifier.rawValue == "common.text.color" }) { missing.append(semanticIssue("colorUnavailable", path: path)) }
            return try RuntimeSemanticTextCandidate(source: semanticName(path.hasPrefix("attachmentsStorage/") ? "ios.swiftui.attachmentsStorage" : "ios.swiftui.cachedCombinedAttachment"), path: path, fields: values, issues: missing)
        }
        // All fields must belong to one proven original Text scope. Cached fields never vote.
        let originalFields = candidates.filter { $0.source == semanticName("ios.swiftui.attachmentsStorage") }.flatMap(\.fields)
        var canonical: [RuntimeAttribute] = []
        if scopeProof.canPromote && !local.truncated && !budget.truncated {
            for name in ["common.text.content", "common.text.fontName", "common.text.fontSize", "common.text.color"] {
                let matches = originalFields.filter { $0.attribute.identifier.rawValue == name }
                if let first = matches.first, matches.allSatisfy({ $0.attribute == first.attribute }) {
                    canonical.append(first.attribute)
                } else if !matches.isEmpty { issues.append(semanticIssue("ambiguousTextScope")) }
            }
        } else if !originalFields.isEmpty { issues.append(semanticIssue("ambiguousTextScope")) }
        if candidates.isEmpty { issues.append(semanticIssue("textAttachmentUnavailable")) }
        issues.append(contentsOf: candidates.flatMap(\.issues))
        return Projection(candidates: candidates, canonicalAttributes: canonical, issues: issues, truncated: local.truncated || budget.truncated)
    }

    private static func fieldName(_ path: String) -> String {
        path.split(separator: "/").last(where: { $0 != "some" }).map(String.init) ?? "unknown"
    }

    private static func fieldsForTraversal(typeName: String, wrapperDepth: Int = 0) -> Set<String>? {
        guard wrapperDepth < 20 else { return nil }
        if typeName.hasPrefix("Swift.Optional<"), typeName.hasSuffix(">") {
            let inner = String(typeName.dropFirst("Swift.Optional<".count).dropLast())
            return fieldsForTraversal(typeName: inner, wrapperDepth: wrapperDepth + 1) == nil ? nil : ["some"]
        }
        if typeName.hasPrefix("Swift.Array<"), typeName.hasSuffix(">") {
            let inner = String(typeName.dropFirst("Swift.Array<".count).dropLast())
            let permitted = ["SwiftUI.AccessibilityNodeAttachmentStorage", "SwiftUI.Text", "SwiftUI.Text.Modifier"].contains(inner) || (inner.hasPrefix("SwiftUI.AccessibilityProperties.") && inner.hasSuffix(".Entry"))
            return permitted ? [] : nil
        }
        if typeName.hasPrefix("SwiftUI.AccessibilityProperties."), typeName.hasSuffix(".Entry") { return ["value"] }
        if typeName.hasPrefix("SwiftUI."), typeName.hasSuffix(".LocalizedTextStorage") { return ["key"] }
        switch typeName {
        case "SwiftUI.AccessibilityNodeAttachmentStorage": return ["attachment"]
        case "SwiftUI.AccessibilityAttachment": return ["properties"]
        case "SwiftUI.AccessibilityProperties": return ["storage"]
        case "SwiftUI.AccessibilityLabelStorage": return ["texts", "layoutProperties"]
        case "SwiftUI.Text": return ["storage", "modifiers"]
        case "SwiftUI.Text.Storage": return ["verbatim", "anyTextStorage"]
        case "SwiftUI.Text.Modifier": return ["font", "color", "tracking", "kerning"]
        case "SwiftUI.LocalizedStringKey": return ["key"]
        case "SwiftUI.Indirect<SwiftUI.TextLayoutProperties>": return ["box"]
        case "SwiftUI.MutableBox<SwiftUI.TextLayoutProperties>": return ["value"]
        case "SwiftUI.TextLayoutProperties": return ["lineSpacing", "lineLimit", "lowerLineLimit", "minimumLineHeight", "maximumLineHeight", "lineHeightMultiple", "hyphenationFactor", "hyphenationDisabled", "minScaleFactor"]
        case "SwiftUI.Font", "SwiftUI.Color", "Swift.String", "Swift.Bool", "Swift.Int", "Swift.Double", "CoreGraphics.CGFloat": return []
        default: return nil
        }
    }
}
#endif
