import AstrolabeProtocol
import Foundation

/// Stores only typed values. No live object, resolver, or fallback is retained.
@MainActor
package final class RuntimeSemanticSnapshotStore {
    private struct Entry {
        /// Original immutable capture, including its identity and timestamp.
        let capture: RuntimeHierarchySnapshotPayload
        /// Encoded capture and detail byte count.
        let byteCount: Int
        /// Immutable details keyed by semantic identity.
        let details: [RuntimeOpaqueIdentifier: RuntimeNodeDetailPayload]
    }

    /// Clock used for expiry, injectable without platform dependencies.
    private let now: @Sendable () -> Double
    /// Entries ordered by capture time, oldest first.
    private var entries: [Entry] = []

    package init(now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.now = now
    }

    package func insert(capture: RuntimeHierarchySnapshotPayload, details: [RuntimeNodeDetailPayload]) throws {
        guard let semantic = capture.semanticCapture else { throw invalidParameters() }
        var nodeIDs = Set<RuntimeOpaqueIdentifier>()
        func visit(_ node: RuntimeSemanticNode) {
            nodeIDs.insert(node.nodeID)
            node.children.forEach(visit)
        }
        semantic.roots.forEach(visit)
        guard details.count == nodeIDs.count,
              Set(details.map(\.nodeID)) == nodeIDs,
              details.allSatisfy({
                  $0.semanticContext?.snapshotID == capture.snapshotID &&
                  $0.semanticContext?.capturedAtUnixTime == capture.capturedAtUnixTime
              }), !entries.contains(where: { $0.capture.snapshotID == capture.snapshotID }) else {
            throw invalidParameters()
        }
        let encoder = JSONEncoder()
        let byteCount = try encoder.encode(capture).count + encoder.encode(details).count
        guard byteCount <= 4 * 1024 * 1024 else {
            throw RuntimeError(code: try RuntimeErrorCode(rawValue: "inspection.captureTooLarge"), message: "语义捕获超过值预算。", recoverySuggestion: nil)
        }
        let entry = Entry(capture: capture,
                          byteCount: byteCount, details: Dictionary(uniqueKeysWithValues: details.map { ($0.nodeID, $0) }))
        removeExpired()
        entries.append(entry)
        entries.sort { $0.capture.capturedAtUnixTime < $1.capture.capturedAtUnixTime }
        while entries.count > 4 || entries.reduce(0, { $0 + $1.byteCount }) > 16 * 1024 * 1024 {
            entries.removeFirst()
        }
    }

    package func detail(nodeID: RuntimeOpaqueIdentifier, snapshotID: RuntimeOpaqueIdentifier) throws -> RuntimeNodeDetailPayload {
        removeExpired()
        guard let entry = entries.first(where: { $0.capture.snapshotID == snapshotID }) else {
            throw RuntimeError(code: try RuntimeErrorCode(rawValue: "inspection.snapshotUnavailable"), message: "语义快照已失效。", recoverySuggestion: nil)
        }
        guard let detail = entry.details[nodeID] else { throw invalidParameters() }
        return detail
    }

    private func removeExpired() {
        let time = now()
        entries.removeAll { time - $0.capture.capturedAtUnixTime >= 300 }
    }

    private func invalidParameters() -> RuntimeError {
        RuntimeError(code: .invalidParameters, message: "语义节点与捕获身份不匹配。", recoverySuggestion: nil)
    }
}
