import AstrolabeProtocol
import Foundation

/// Complete source runs only; ranges use UTF-16 units, matching the existing text-run contract.
enum SwiftUITextRunPolicy {
    static func sourceText(in attributed: AttributedString, range: Range<AttributedString.Index>) -> String {
        // Attribute boundaries can split one grapheme; CharacterView would move source scalars between runs.
        String(String.UnicodeScalarView(attributed[range].unicodeScalars))
    }

    static func canUseEnvironmentForeground(path: String?) -> Bool {
        path == nil || path!.hasPrefix("environment/")
    }

    /// Maximum complete style segments in one Text.
    static let maximumRuns = 64
    /// Maximum total source text, before output encoding.
    static let maximumUTF8Bytes = 16_384

    static func valid(_ runs: [RuntimeTextRun]) -> Bool {
        guard !runs.isEmpty, runs.count <= maximumRuns else { return false }
        var location: Int64 = 0
        var bytes = 0
        for run in runs {
            guard !run.text.isEmpty, run.range.location == location,
                  run.range.length == Int64(run.text.utf16.count),
                  run.text.utf8.count <= maximumUTF8Bytes - bytes else { return false }
            let end = location.addingReportingOverflow(run.range.length)
            guard !end.overflow else { return false }
            location = end.partialValue
            bytes += run.text.utf8.count
        }
        return true
    }

    static func isConcatenatedStorage(_ type: String) -> Bool {
        let prefix = "SwiftUI.(unknown context at $"
        let suffix = ").ConcatenatedTextStorage"
        guard type.hasPrefix(prefix), type.hasSuffix(suffix) else { return false }
        let address = type.dropFirst(prefix.count).dropLast(suffix.count)
        return !address.isEmpty && address.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
}
