import AstrolabeProtocol

/// Explicit semantic capture seam; implementations return frozen snapshot values.
@MainActor
package protocol RuntimeSemanticInspectionProviding: AnyObject, Sendable {
    func capture(options: RuntimeSemanticCaptureOptions) async throws -> RuntimeHierarchySnapshotPayload
    func detail(nodeID: RuntimeOpaqueIdentifier, snapshotID: RuntimeOpaqueIdentifier) async throws -> RuntimeNodeDetailPayload
}
