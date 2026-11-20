//
//  RuntimeInspectionServices.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol

package struct RuntimeInspectionServices: Sendable {
    /// Provider exposing application, device, and screen metadata.
    package let appInfoProvider: any RuntimeAppInfoProviding

    /// Provider capturing the runtime hierarchy for one connection session.
    package let hierarchyProvider: any RuntimeHierarchyProviding

    /// Provider resolving node details within the same connection session.
    package let nodeDetailProvider: any RuntimeNodeDetailProviding

    /// Optional provider managing Debug-only temporary attribute patches.
    package let attributePatchProvider: (any RuntimeAttributePatchProviding)?

    /// Optional provider capturing and resolving frozen semantic values.
    package let semanticProvider: (any RuntimeSemanticInspectionProviding)?

    /// Capabilities describing payload extensions rather than request handlers.
    package let additionalCapabilities: Set<RuntimeCapability>

    package init(
        appInfoProvider: any RuntimeAppInfoProviding,
        hierarchyProvider: any RuntimeHierarchyProviding,
        nodeDetailProvider: any RuntimeNodeDetailProviding,
        attributePatchProvider: (any RuntimeAttributePatchProviding)? = nil,
        semanticProvider: (any RuntimeSemanticInspectionProviding)? = nil,
        additionalCapabilities: Set<RuntimeCapability> = []
    ) {
        self.appInfoProvider = appInfoProvider
        self.hierarchyProvider = hierarchyProvider
        self.nodeDetailProvider = nodeDetailProvider
        self.attributePatchProvider = attributePatchProvider
        self.semanticProvider = semanticProvider
        self.additionalCapabilities = additionalCapabilities
    }

    package func capture(parameters: RuntimeHierarchySnapshotParameters) async throws -> RuntimeHierarchySnapshotPayload {
        if let options = parameters.semanticCapture {
            guard let semanticProvider else { throw semanticUnavailable() }
            return try await semanticProvider.capture(options: options)
        }
        return try await hierarchyProvider.hierarchySnapshot()
    }

    package func detail(parameters: RuntimeNodeDetailParameters) async throws -> RuntimeNodeDetailPayload {
        if let snapshotID = parameters.snapshotID {
            guard let semanticProvider else { throw semanticUnavailable() }
            return try await semanticProvider.detail(nodeID: parameters.nodeID, snapshotID: snapshotID)
        }
        guard !parameters.nodeID.rawValue.hasPrefix("semantic-") else {
            throw RuntimeError(code: .invalidParameters, message: "语义详情需要快照身份。", recoverySuggestion: nil)
        }
        return try await nodeDetailProvider.nodeDetail(for: parameters.nodeID)
    }

    private func semanticUnavailable() -> RuntimeError {
        RuntimeError(code: .capabilityUnavailable, message: "当前运行时不支持语义检查。", recoverySuggestion: nil)
    }
}

/// Creates a fresh inspection service graph for one accepted connection.
package typealias RuntimeInspectionServicesFactory =
    @MainActor @Sendable () -> RuntimeInspectionServices
