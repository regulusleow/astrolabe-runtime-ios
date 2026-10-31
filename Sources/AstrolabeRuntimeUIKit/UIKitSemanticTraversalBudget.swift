import AstrolabeProtocol

/// Counts actual visits; an exact boundary is truncated only when more work is attempted.
struct UIKitSemanticTraversalBudget {
    /// Exclusive depth boundary.
    let maxDepth: Int
    /// Maximum visited values or objects.
    let maxVisits: Int
    /// Actual allowed visits.
    private(set) var visits = 0
    /// Whether pending work was refused.
    private(set) var truncated = false

    mutating func consume(depth: Int) -> Bool {
        guard depth >= 0, depth < maxDepth, visits < maxVisits else {
            truncated = true
            return false
        }
        visits += 1
        return true
    }

    mutating func markTruncated() { truncated = true }

    /// Child slots are bounded independently of unique object visits, including repeated references.
    mutating func boundedChildCount(_ totalCount: Int) -> Int {
        if totalCount > 2_000 { truncated = true }
        return min(totalCount, 2_000)
    }
}

/// Pure proof state shared by the actual private Text adapter and algorithm tests.
struct SwiftUITextScopeProof {
    /// Observed original Text scopes; combined-cache scopes never enter this set.
    private var originalPaths = Set<String>()
    /// Whether an original branch or field could not be identified completely.
    private var originalLayoutUnproven = false
    /// Explicit original Color presence blocks inheritance even when its value is refused.
    private var originalHasColor = false
    /// Explicit original Font presence blocks inheritance even when resolution fails.
    private var originalHasFont = false

    /// Whether exactly one original Text scope has been completely identified.
    var canPromote: Bool { originalPaths.count == 1 && !originalLayoutUnproven }
    /// An unambiguous original Text without any explicit Color may use its own environment.
    var canInheritColor: Bool { canPromote && !originalHasColor }
    /// An unambiguous original Text without an explicit Font may use its environment font.
    var canInheritFont: Bool { canPromote && !originalHasFont }

    mutating func recordOriginalText(path: String) { originalPaths.insert(path) }
    mutating func recordOriginalColor() { originalHasColor = true }
    mutating func recordOriginalFont() { originalHasFont = true }
    mutating func markUnknownOriginalBranch() { originalLayoutUnproven = true }

    mutating func allowsField(_ label: String?, permitted: Set<String>, isArray: Bool, isOriginal: Bool) -> Bool {
        if isArray || label.map(permitted.contains) == true { return true }
        if isOriginal { originalLayoutUnproven = true }
        return false
    }
}

/// iOS 27.0 type-only evidence: these exact metadata fields cannot add another original Text.
enum SwiftUITextMetadataPolicy {
    static func isColorBox(_ type: String) -> Bool {
        type == "SwiftUI.ColorBox<SwiftUI.SystemColorType>" ||
        type == "SwiftUI.ColorBox<SwiftUI.ResolvedColorProvider>" ||
        type == "SwiftUI.ColorBox<SwiftUI.Color.OpacityColor>"
    }

    static func isDefaultHierarchyOffsetBox(_ type: String) -> Bool {
        isShapeStyleBox(type, style: "SwiftUI.OffsetShapeStyle<SwiftUI.SystemColorsStyle>")
    }

    static func isSupportedHierarchyLevel(_ level: Int) -> Bool {
        level == 1 || level == 2
    }

    static func isHierarchyOffsetBox(_ type: String) -> Bool {
        isShapeStyleBox(type, style: "SwiftUI.OffsetShapeStyle<SwiftUI.AnyShapeStyle>")
    }

    static func isHierarchyModifierBox(_ type: String) -> Bool {
        isShapeStyleBox(type, style: "SwiftUI.HierarchicalShapeStyleModifier<SwiftUI.Color>")
    }

    static func isHierarchyPackBox(_ type: String) -> Bool {
        isShapeStyleBox(type, style: "SwiftUI.ShapeStylePair<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>") ||
        isShapeStyleBox(type, style: "SwiftUI.ShapeStyleTriple<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>")
    }

    static func isTintKey(_ type: String) -> Bool {
        isEnvironmentKey(type, name: "TintKey")
    }

    static func isTintStyleBox(_ type: String) -> Bool {
        isShapeStyleBox(type, style: "SwiftUI.TintShapeStyle")
    }

    private static func isShapeStyleBox(_ type: String, style: String) -> Bool {
        let prefix = "SwiftUI.(unknown context at $"
        let suffix = ").ShapeStyleBox<" + style + ">"
        guard type.hasPrefix(prefix), type.hasSuffix(suffix) else { return false }
        let context = type.dropFirst(prefix.count).dropLast(suffix.count)
        return !context.isEmpty && context.allSatisfy(\.isHexDigit)
    }

    static func isForegroundStyleKey(_ type: String) -> Bool {
        isEnvironmentKey(type, name: "ForegroundStyleKey")
    }

    static func isFontKey(_ type: String) -> Bool {
        isEnvironmentKey(type, name: "FontKey")
    }

    private static func isEnvironmentKey(_ type: String, name: String) -> Bool {
        let prefix = "SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $"
        let suffix = ")." + name + ">"
        guard type.hasPrefix(prefix), type.hasSuffix(suffix) else { return false }
        let context = type.dropFirst(prefix.count).dropLast(suffix.count)
        return !context.isEmpty && context.allSatisfy(\.isHexDigit)
    }

    static func isLeaf(_ type: String) -> Bool {
        type == "SwiftUI.AccessibilityNullableOptionSet<SwiftUI.AccessibilityTraitSet>" ||
        type == "SwiftUI.AccessibilityNullableOptionSet<SwiftUI.AccessibilityVisibility>"
    }

    static func localizedKeyHasNoHiddenText(hasFormatting: Bool?, argumentsType: String?, argumentsAreEmpty: Bool?) -> Bool {
        hasFormatting == false && argumentsType == "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>" && argumentsAreEmpty == true
    }

    static func canIgnoreField(container: String, field: String?, type: String,
                               isEmptyCollection: Bool? = nil, booleanValue: Bool? = nil) -> Bool {
        guard let field else { return false }
        if container.hasPrefix("SwiftUI.AccessibilityProperties."), container.hasSuffix(".Entry"), field == "key" {
            return ["SwiftUI.AccessibilityProperties.TraitsKey.Type", "SwiftUI.AccessibilityProperties.LabelKey.Type", "SwiftUI.AccessibilityProperties.VisibilityKey.Type"].contains(type)
        }
        if container.hasPrefix("SwiftUI."), container.hasSuffix(".LocalizedTextStorage") {
            return (field == "table" && type == "Swift.Optional<Swift.String>") ||
                (field == "bundle" && type == "Swift.Optional<__C.NSBundle>")
        }
        switch container {
        case "SwiftUI.AccessibilityNodeAttachmentStorage":
            return ["modified": "Swift.Bool", "token": "Swift.Optional<SwiftUI.AccessibilityAttachmentToken>",
                    "geometry": "Swift.Optional<SwiftUI.AccessibilityGeometryStorage>"][field] == type
        case "SwiftUI.AccessibilityAttachment":
            return field == "platformElement" && type == "Swift.Optional<__C.NSObject & SwiftUI.PlatformAccessibilityElementProtocol>"
        case "SwiftUI.AccessibilityLabelStorage":
            return field == "placement" && type == "SwiftUI.AccessibilityLabelStorage.Placement"
        case "SwiftUI.LocalizedStringKey":
            return (field == "hasFormatting" && type == "Swift.Bool" && booleanValue == false) ||
                (field == "arguments" && type == "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>" && isEmptyCollection == true)
        case "SwiftUI.TextLayoutProperties":
            if field == "flags" {
                // Only the compiler's anonymous-context identity varies; owner and nested type stay exact.
                let prefix = "(extension in SwiftUI):SwiftUI.TextLayoutProperties.(unknown context at $"
                let suffix = ").Flags"
                guard type.hasPrefix(prefix), type.hasSuffix(suffix) else { return false }
                let context = type.dropFirst(prefix.count).dropLast(suffix.count)
                return !context.isEmpty && context.allSatisfy(\.isHexDigit)
            }
            return ["truncationMode": "SwiftUI.Text.TruncationMode", "multilineTextAlignment": "SwiftUI.TextAlignment",
                    "layoutDirection": "SwiftUI.LayoutDirection", "transitionStyle": "SwiftUI.ContentTransition.Style",
                    "writingMode": "SwiftUI.Text.WritingMode", "bodyHeadOutdent": "CoreGraphics.CGFloat",
                    "pixelLength": "CoreGraphics.CGFloat", "textSizing": "SwiftUI.Text.Sizing",
                    "textBaseline": "(extension in SwiftUI):SwiftUI.Text.Baseline", "textShape": "SwiftUI.TextShape"][field] == type
        default: return false
        }
    }
}

func semanticName(_ value: String) -> RuntimeNamespacedIdentifier { try! .init(rawValue: value) }
func semanticIssue(_ code: String, path: String? = nil) -> RuntimeInspectionIssue {
    try! RuntimeInspectionIssue(code: semanticName("ios.swiftui." + code), path: path)
}
