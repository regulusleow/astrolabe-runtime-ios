import AstrolabeProtocol
import Foundation

/// Counts every work attempt; an exact boundary is truncated only when more work is refused.
struct UIKitSemanticTraversalBudget {
    /// Exclusive depth boundary.
    let maxDepth: Int
    /// Maximum work attempts, including repeats and refused depths.
    let maxVisits: Int
    /// Actual allowed visits.
    private(set) var visits = 0
    /// Work attempts, including refused objects and invalid depths.
    private(set) var attempts = 0
    /// Whether pending work was refused.
    private(set) var truncated = false

    /// Whether another object attempt would exceed the work limit.
    var exhausted: Bool { attempts >= maxVisits }

    enum Admission: Equatable {
        case accepted, repeated, unsupported, refused
    }

    mutating func admitObject(_ identity: ObjectIdentifier?, depth: Int,
                             seen: inout Set<ObjectIdentifier>) -> Admission {
        guard consume(depth: depth) else { return .refused }
        guard let identity else { return .unsupported }
        guard seen.insert(identity).inserted else { return .repeated }
        return .accepted
    }

    mutating func consume(depth: Int) -> Bool {
        guard !exhausted else {
            truncated = true
            return false
        }
        attempts += 1
        guard depth >= 0, depth < maxDepth else {
            truncated = true
            return false
        }
        visits += 1
        return true
    }

    mutating func markTruncated() { truncated = true }

    /// Queued child slots reserve work before another container enumerates its children.
    mutating func boundedChildCount(_ totalCount: Int, reserved: Int = 0) -> Int {
        let remaining = max(0, maxVisits - attempts - reserved)
        if totalCount > remaining { truncated = true }
        return min(totalCount, remaining)
    }
}

/// Capture diagnostics stay bounded while appending, rather than after traversal.
struct UIKitSemanticIssueBuffer {
    private struct Key: Hashable {
        /// Stable namespaced failure identifier.
        let code: String
        /// Optional source path, without business values.
        let path: String?
    }
    /// Retained distinct diagnostics in capture order.
    private(set) var values: [RuntimeInspectionIssue] = []
    /// Whether a distinct diagnostic exceeded the reserved output capacity.
    private(set) var truncated = false
    /// Keys only for retained diagnostics, bounded with the output array.
    private var keys = Set<Key>()

    mutating func append(_ issue: RuntimeInspectionIssue) {
        let key = Key(code: issue.code.rawValue, path: issue.path)
        guard !keys.contains(key) else { return }
        guard values.count < 1_998 else { truncated = true; return }
        keys.insert(key)
        values.append(issue)
    }

    mutating func append(contentsOf issues: [RuntimeInspectionIssue]) {
        for issue in issues { append(issue) }
    }
}

/// Pure proof state shared by the actual private Text adapter and algorithm tests.
struct SwiftUITextScopeProof {
    /// Segmented content cannot claim one whole-node font or foreground without a separate uniformity proof.
    private(set) var hasOriginalTextRuns = false

    mutating func recordOriginalTextRuns() { hasOriginalTextRuns = true }
    /// A direct Color and foreground modifier conflict even if one failed projection.
    var hasMixedForegroundStyles: Bool { originalHasColor && originalHasForegroundStyle }

    mutating func recordOriginalColor() { originalHasColor = true }

    /// Observed original Text scopes; combined-cache scopes never enter this set.
    private var originalPaths = Set<String>()
    /// Whether an original branch or field could not be identified completely.
    private var originalLayoutUnproven = false
    /// Explicit original foreground-style presence blocks inheritance even when its value is refused.
    private var originalHasForegroundStyle = false
    /// Explicit Color presence survives invalid or unavailable RGBA projection.
    private var originalHasColor = false
    /// Explicit original Font presence blocks inheritance even when resolution fails.
    private var originalHasFont = false

    /// Whether exactly one original Text scope has been completely identified.
    var canPromote: Bool { originalPaths.count == 1 && !originalLayoutUnproven }
    /// An unambiguous original Text without an explicit foreground style may use its own environment.
    var canInheritForegroundStyle: Bool { canPromote && !hasOriginalTextRuns && !originalHasForegroundStyle && !originalHasColor }
    /// An unambiguous original Text without an explicit Font may use its environment font.
    var canInheritFont: Bool { canPromote && !hasOriginalTextRuns && !originalHasFont }

    mutating func recordOriginalText(path: String) { originalPaths.insert(path) }
    mutating func recordOriginalForegroundStyle() { originalHasForegroundStyle = true }
    mutating func recordOriginalFont() { originalHasFont = true }
    mutating func markUnknownOriginalBranch() { originalLayoutUnproven = true }

    mutating func allowsField(_ label: String?, permitted: Set<String>, isArray: Bool, isOriginal: Bool) -> Bool {
        if isArray || label.map(permitted.contains) == true { return true }
        if isOriginal { originalLayoutUnproven = true }
        return false
    }
}

/// Verified Text metadata layouts; unknown versions and types fail closed.
enum SwiftUITextMetadataPolicy {
    static func isDirectHierarchyBox(_ type: String) -> Bool {
        isShapeStyleBox(type, style: "SwiftUI.HierarchicalShapeStyle")
    }

    /// Direct Text style modifiers need four more bounded slots than inherited styles.
    static let maxTextProjectionDepth = 24

    /// Bound before traversing or allocating resolved gradient stops.
    static let maxLinearGradientStops = 32

    static func isLinearGradientBox(_ type: String) -> Bool {
        isShapeStyleBox(type, style: "SwiftUI.LinearGradient")
    }

    static func validLinearGradientLocations(_ locations: [Double]) -> Bool {
        !locations.isEmpty && locations.count <= maxLinearGradientStops &&
            locations.allSatisfy { $0.isFinite && (0...1).contains($0) } &&
            zip(locations, locations.dropFirst()).allSatisfy { $0 <= $1 }
    }

    static func supportsLinearGradientLayout(major: Int, minor: Int, simulator: Bool) -> Bool {
        major == 27 && minor == 0
    }

    static var supportsCurrentLayout: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS) && arch(arm64) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
        let physicalDevice = !ProcessInfo.processInfo.isiOSAppOnMac
        #else
        let physicalDevice = false
        #endif
        return supportsLayout(major: version.majorVersion, minor: version.minorVersion, physicalDevice: physicalDevice)
    }

    static func supportsLayout(major: Int, minor: Int, physicalDevice: Bool) -> Bool {
        major == 27 && (minor == 0 || (minor == 2 && physicalDevice))
    }

    /// shortcut: hierarchy/palette evidence covers these targets only; validate others before widening.
    static func supportsHierarchyLayout(major: Int, minor: Int, simulator: Bool) -> Bool {
        major == 27 && (minor == 0 || (minor == 2 && !simulator))
    }

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
