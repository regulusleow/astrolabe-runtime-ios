#if canImport(UIKit)
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
}

func semanticName(_ value: String) -> RuntimeNamespacedIdentifier { try! .init(rawValue: value) }
func semanticIssue(_ code: String, path: String? = nil) -> RuntimeInspectionIssue {
    try! RuntimeInspectionIssue(code: semanticName("ios.swiftui." + code), path: path)
}
#endif
