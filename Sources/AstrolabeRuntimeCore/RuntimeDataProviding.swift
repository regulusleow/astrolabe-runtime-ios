//
//  RuntimeDataProviding.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol

@MainActor
package protocol RuntimeAppInfoProviding: AnyObject, Sendable {
    func appInfo(runtime: RuntimeDescriptor) async throws -> RuntimeApplicationInfoPayload
}

@MainActor
package protocol RuntimeHierarchyProviding: AnyObject, Sendable {
    func hierarchySnapshot() async throws -> RuntimeHierarchySnapshotPayload
}

@MainActor
package protocol RuntimeNodeDetailProviding: AnyObject, Sendable {
    func nodeDetail(
        for nodeID: RuntimeOpaqueIdentifier
    ) async throws -> RuntimeNodeDetailPayload
}

@MainActor
package protocol RuntimeAttributePatchProviding: AnyObject, Sendable {
    func patchableAttributes() async -> RuntimePatchableAttributesPayload

    func applyAttributePatch(
        _ request: RuntimeApplyAttributePatchParameters
    ) async throws -> RuntimeAttributePatch

    func activeAttributePatches() async -> RuntimeAttributePatchListPayload

    func revertAttributePatch(
        _ request: RuntimeRevertAttributePatchParameters
    ) async throws -> RuntimeRevertAttributePatchPayload

    func clearAttributePatches() async throws -> RuntimeClearAttributePatchesPayload
}
