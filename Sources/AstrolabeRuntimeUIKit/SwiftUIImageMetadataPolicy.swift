import Foundation

/// Closed provider set and numeric boundaries for the verified image profile.
enum SwiftUIImageMetadataPolicy {
    enum ProviderKind: Equatable {
        case named, uiImage, cgImage, renderingMode, resizable, symbolOptions
    }

    /// Maximum modifier providers before a concrete source.
    static let maximumWrappers = 4
    /// Exclusive bound for the complete attachment/provider path.
    static let maximumDepth = 24

    static func providerKind(_ name: String) -> ProviderKind? {
        let prefix = "SwiftUI.ImageProviderBox<"
        guard name.hasPrefix(prefix), name.hasSuffix(">") else { return nil }
        let base = String(name.dropFirst(prefix.count).dropLast())
        switch base {
        case "SwiftUI.Image.NamedImageProvider": return .named
        case "__C.UIImage": return .uiImage
        case "SwiftUI.Image.ResizableProvider": return .resizable
        default:
            if privateType(base, prefix: "SwiftUI.Image.", suffix: "CGImageProvider") { return .cgImage }
            if privateType(base, prefix: "SwiftUI.Image.", suffix: "RenderingModeProvider") { return .renderingMode }
            if privateType(base, prefix: "(extension in SwiftUI):SwiftUI.Image.", suffix: "SymbolRenderingOptionsProvider") { return .symbolOptions }
            return nil
        }
    }

    static func privateType(_ type: String, prefix: String, suffix: String) -> Bool {
        let start = prefix + "(unknown context at $"
        let end = ")." + suffix
        guard type.hasPrefix(start), type.hasSuffix(end) else { return false }
        let address = type.dropFirst(start.count).dropLast(end.count)
        return !address.isEmpty && address.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    static func isSingleOriginalImage(_ counts: [Int]) -> Bool { counts == [1] }

    static func validSize(width: Double, height: Double, scale: Double) -> Bool {
        [width, height, scale].allSatisfy { $0.isFinite && $0 <= 9_007_199_254_740_991 } && width >= 0 && height >= 0 && scale > 0
    }

    static func validInsets(_ values: [Double]) -> Bool {
        values.count == 4 && values.allSatisfy { $0.isFinite && (0...9_007_199_254_740_991).contains($0) }
    }

    static func validWrapperCount(_ count: Int) -> Bool { (0...maximumWrappers).contains(count) }

    static func supportsLayout(major: Int, minor: Int, simulator: Bool) -> Bool { major == 27 && minor == 0 && simulator }
}
