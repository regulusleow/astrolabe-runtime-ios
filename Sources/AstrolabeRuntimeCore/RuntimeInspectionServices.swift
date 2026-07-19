//
//  RuntimeInspectionServices.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

package struct RuntimeInspectionServices: Sendable {
    /// Provider exposing application, device, and screen metadata.
    package let appInfoProvider: any RuntimeAppInfoProviding

    /// Provider capturing the runtime hierarchy for one connection session.
    package let hierarchyProvider: any RuntimeHierarchyProviding

    /// Provider resolving node details within the same connection session.
    package let nodeDetailProvider: any RuntimeNodeDetailProviding

    /// Optional provider managing Debug-only temporary attribute patches.
    package let attributePatchProvider: (any RuntimeAttributePatchProviding)?

    package init(
        appInfoProvider: any RuntimeAppInfoProviding,
        hierarchyProvider: any RuntimeHierarchyProviding,
        nodeDetailProvider: any RuntimeNodeDetailProviding,
        attributePatchProvider: (any RuntimeAttributePatchProviding)? = nil
    ) {
        self.appInfoProvider = appInfoProvider
        self.hierarchyProvider = hierarchyProvider
        self.nodeDetailProvider = nodeDetailProvider
        self.attributePatchProvider = attributePatchProvider
    }
}

/// Creates a fresh inspection service graph for one accepted connection.
package typealias RuntimeInspectionServicesFactory =
    @MainActor @Sendable () -> RuntimeInspectionServices
