//
//  RuntimeAttributePatchService.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/13.
//

import AstrolabeProtocol
import Foundation

@MainActor
package protocol RuntimeAttributeMutating: Sendable {
    /// Attributes accepted by this mutator implementation.
    var patchableAttributeCatalog: RuntimePatchableAttributesPayload { get }

    /// Platform-owned recovery guidance for a rejected mutation.
    var invalidValueRecoverySuggestion: String? { get }

    func mutationDescriptor(
        for object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> RuntimeAttributeMutationDescriptor

    func apply(
        value: RuntimeAttributeValue,
        to object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> RuntimeAttributeMutation
}

@MainActor
package struct RuntimeAttributeMutationDomain: Hashable {
    /// Identity of the runtime object whose state is replayed as one unit.
    package let objectIdentifier: ObjectIdentifier

    /// Stable key grouping independently addressable writes that must replay together.
    package let domainIdentifier: String

    package init(
        objectIdentifier: ObjectIdentifier,
        domainIdentifier: String
    ) {
        self.objectIdentifier = objectIdentifier
        self.domainIdentifier = domainIdentifier
    }
}

@MainActor
package struct RuntimeAttributeMutationDescriptor: Hashable {
    /// State domain whose active commands must be replayed together.
    package let domain: RuntimeAttributeMutationDomain

    /// Logical presentation effects controlled by this semantic attribute.
    package let effectIdentifiers: Set<String>

    package init(
        domain: RuntimeAttributeMutationDomain,
        effectIdentifiers: Set<String>
    ) {
        self.domain = domain
        self.effectIdentifiers = effectIdentifiers
    }
}

@MainActor
package struct RuntimeAttributeMutation {
    /// Value observed immediately before the mutation.
    package let originalValue: RuntimeAttributeValue?

    /// Value read back immediately after the mutation.
    package let actualValue: RuntimeAttributeValue?

    /// Requested value normalized into the same representation as the readback.
    package let comparisonValue: RuntimeAttributeValue?

    /// Repeatedly restores the value captured immediately before this mutation.
    package let restore: @MainActor () throws -> RuntimeAttributeValue?

    package init(
        originalValue: RuntimeAttributeValue?,
        actualValue: RuntimeAttributeValue?,
        comparisonValue: RuntimeAttributeValue? = nil,
        restore: @escaping @MainActor () throws -> RuntimeAttributeValue?
    ) {
        self.originalValue = originalValue
        self.actualValue = actualValue
        self.comparisonValue = comparisonValue
        self.restore = restore
    }
}

@MainActor
package final class RuntimeAttributePatchService: RuntimeAttributePatchProviding {
    private struct ActivePatch {
        /// Public protocol record returned to the Host.
        let record: RuntimeAttributePatch

        /// Platform descriptor used to compose and validate mutations.
        let descriptor: RuntimeAttributeMutationDescriptor

        /// Restores the state that existed immediately before this command.
        let restore: @MainActor () throws -> RuntimeAttributeValue?
    }

    private struct PatchIntent {
        /// Stable identifier retained when the same attribute is updated.
        let patchID: RuntimeOpaqueIdentifier

        /// Runtime node used to resolve the platform object during replay.
        let nodeID: RuntimeOpaqueIdentifier

        /// Semantic attribute requested by the Host.
        let attributeIdentifier: RuntimeAttributeIdentifier

        /// Value to apply whenever this state domain is replayed.
        let requestedValue: RuntimeAttributeValue

        /// Value captured before this attribute was first patched.
        let originalValue: RuntimeAttributeValue?

        /// Timestamp of the most recent explicit update to this attribute.
        let appliedAtUnixTime: TimeInterval

        /// Platform descriptor resolved for this attribute and object.
        let descriptor: RuntimeAttributeMutationDescriptor
    }

    private let nodeRegistry: RuntimeNodeRegistry
    private let mutator: any RuntimeAttributeMutating
    private var patchesByID = [RuntimeOpaqueIdentifier: ActivePatch]()
    private var patchIDsByDomain = [RuntimeAttributeMutationDomain: [RuntimeOpaqueIdentifier]]()
    private var patchOrder = [RuntimeOpaqueIdentifier]()

    package init(
        nodeRegistry: RuntimeNodeRegistry,
        mutator: any RuntimeAttributeMutating
    ) {
        self.nodeRegistry = nodeRegistry
        self.mutator = mutator
    }

    package func applyAttributePatch(
        _ request: RuntimeApplyAttributePatchParameters
    ) async throws -> RuntimeAttributePatch {
        guard let object = nodeRegistry.object(for: request.nodeID) else {
            throw RuntimeError(
                code: .nodeNotFound,
                message: "The requested patch node is unavailable.",
                recoverySuggestion: "Capture a fresh hierarchy and retry with its node ID."
            )
        }
        let descriptor = try mutator.mutationDescriptor(
            for: object,
            attributeIdentifier: request.attributeIdentifier
        )
        let domain = descriptor.domain
        let currentPatches = activePatches(for: domain)
        let existingIndex = currentPatches.firstIndex {
            $0.record.attributeIdentifier == request.attributeIdentifier
        }
        if existingIndex == nil,
           currentPatches.contains(where: {
               !$0.descriptor.effectIdentifiers.isDisjoint(
                   with: descriptor.effectIdentifiers
               )
           }) {
            throw RuntimeError(
                code: .patchConflict,
                message: "The requested attribute overlaps an active patch.",
                recoverySuggestion: "Revert the conflicting patch before applying this attribute."
            )
        }

        let patchID = try existingIndex.map {
            currentPatches[$0].record.patchID
        } ?? makePatchID()
        let appliedAtUnixTime = Date().timeIntervalSince1970
        var candidateIntents = currentPatches.map(intent)
        let candidateIntent = PatchIntent(
            patchID: patchID,
            nodeID: request.nodeID,
            attributeIdentifier: request.attributeIdentifier,
            requestedValue: request.value,
            originalValue: existingIndex.map {
                currentPatches[$0].record.originalValue
            } ?? nil,
            appliedAtUnixTime: appliedAtUnixTime,
            descriptor: descriptor
        )
        if let existingIndex {
            candidateIntents[existingIndex] = candidateIntent
        } else {
            candidateIntents.append(candidateIntent)
        }

        let rewrittenPatches = try rewrite(
            domain: domain,
            currentPatches: currentPatches,
            candidateIntents: candidateIntents,
            newPatchIDs: existingIndex == nil ? [patchID] : []
        )
        store(rewrittenPatches, for: domain)
        if existingIndex == nil {
            patchOrder.append(patchID)
        }
        guard let patch = patchesByID[patchID]?.record else {
            throw RuntimeError(
                code: .internalFailure,
                message: "The Runtime could not read the patch that was just applied.",
                recoverySuggestion: nil
            )
        }
        return patch
    }

    package func patchableAttributes() async -> RuntimePatchableAttributesPayload {
        mutator.patchableAttributeCatalog
    }

    package func activeAttributePatches() async -> RuntimeAttributePatchListPayload {
        RuntimeAttributePatchListPayload(
            patches: patchOrder.compactMap { patchesByID[$0]?.record }
        )
    }

    package func revertAttributePatch(
        _ request: RuntimeRevertAttributePatchParameters
    ) async throws -> RuntimeRevertAttributePatchPayload {
        guard let activePatch = patchesByID[request.patchID] else {
            throw RuntimeError(
                code: .patchNotFound,
                message: "The requested patch is not active in this Runtime session.",
                recoverySuggestion: nil
            )
        }
        let domain = activePatch.descriptor.domain
        let currentPatches = activePatches(for: domain)
        let candidateIntents = currentPatches
            .filter { $0.record.patchID != request.patchID }
            .map(intent)
        let rewrittenPatches = try rewrite(
            domain: domain,
            currentPatches: currentPatches,
            candidateIntents: candidateIntents,
            newPatchIDs: []
        )
        store(rewrittenPatches, for: domain)
        patchOrder.removeAll { $0 == request.patchID }
        return RuntimeRevertAttributePatchPayload(
            revertedPatchID: request.patchID,
            restoredValue: activePatch.record.originalValue,
            remainingPatchCount: patchesByID.count
        )
    }

    package func clearAttributePatches() async throws -> RuntimeClearAttributePatchesPayload {
        let revertedPatchIDs = try restoreAll()
        return RuntimeClearAttributePatchesPayload(
            revertedPatchIDs: revertedPatchIDs,
            remainingPatchCount: patchesByID.count
        )
    }

    private func makePatchID() throws -> RuntimeOpaqueIdentifier {
        do {
            return try RuntimeOpaqueIdentifier(rawValue: UUID().uuidString)
        } catch {
            throw RuntimeError(
                code: .internalFailure,
                message: "The Runtime could not generate a patch identifier.",
                recoverySuggestion: nil
            )
        }
    }

    private func activePatches(
        for domain: RuntimeAttributeMutationDomain
    ) -> [ActivePatch] {
        patchIDsByDomain[domain, default: []].compactMap { patchesByID[$0] }
    }

    private func intent(_ activePatch: ActivePatch) -> PatchIntent {
        PatchIntent(
            patchID: activePatch.record.patchID,
            nodeID: activePatch.record.nodeID,
            attributeIdentifier: activePatch.record.attributeIdentifier,
            requestedValue: activePatch.record.requestedValue,
            originalValue: activePatch.record.originalValue,
            appliedAtUnixTime: activePatch.record.appliedAtUnixTime,
            descriptor: activePatch.descriptor
        )
    }

    private func rewrite(
        domain: RuntimeAttributeMutationDomain,
        currentPatches: [ActivePatch],
        candidateIntents: [PatchIntent],
        newPatchIDs: Set<RuntimeOpaqueIdentifier>
    ) throws -> [ActivePatch] {
        try rewind(
            currentPatches,
            in: domain
        )
        do {
            return try replay(
                candidateIntents,
                newPatchIDs: newPatchIDs
            )
        } catch {
            let candidateError = error
            do {
                _ = try replay(
                    currentPatches.map(intent),
                    newPatchIDs: []
                )
                store(currentPatches, for: domain)
            } catch {
                throw RuntimeError(
                    code: .patchRestorationFailed,
                    message: "The Runtime could not restore the original state after the patch set failed.",
                    recoverySuggestion: String(describing: error)
                )
            }
            throw candidateError
        }
    }

    private func rewind(
        _ activePatches: [ActivePatch],
        in domain: RuntimeAttributeMutationDomain
    ) throws {
        do {
            for activePatch in activePatches.reversed() {
                _ = try restore(activePatch)
            }
        } catch {
            let rewindError = error
            do {
                _ = try replay(
                    activePatches.map(intent),
                    newPatchIDs: []
                )
                store(activePatches, for: domain)
            } catch {
                throw RuntimeError(
                    code: .patchRestorationFailed,
                    message: "The Runtime could not restore the pre-call state after reverting the patch set failed.",
                    recoverySuggestion: String(describing: error)
                )
            }
            throw rewindError
        }
    }

    private func replay(
        _ intents: [PatchIntent],
        newPatchIDs: Set<RuntimeOpaqueIdentifier>
    ) throws -> [ActivePatch] {
        var replayedPatches = [ActivePatch]()
        do {
            for intent in intents {
                guard let object = nodeRegistry.object(for: intent.nodeID) else {
                    throw RuntimeError(
                        code: .nodeNotFound,
                        message: "The requested patch node is unavailable.",
                        recoverySuggestion: "Capture a fresh hierarchy and retry with its node ID."
                    )
                }
                let mutation = try mutator.apply(
                    value: intent.requestedValue,
                    to: object,
                    attributeIdentifier: intent.attributeIdentifier
                )
                try validate(
                    mutation,
                    requestedValue: intent.requestedValue
                )
                let record = RuntimeAttributePatch(
                    patchID: intent.patchID,
                    nodeID: intent.nodeID,
                    attributeIdentifier: intent.attributeIdentifier,
                    originalValue: newPatchIDs.contains(intent.patchID)
                        ? mutation.originalValue
                        : intent.originalValue,
                    requestedValue: intent.requestedValue,
                    actualValue: mutation.actualValue,
                    appliedAtUnixTime: intent.appliedAtUnixTime
                )
                replayedPatches.append(
                    ActivePatch(
                        record: record,
                        descriptor: intent.descriptor,
                        restore: mutation.restore
                    )
                )
            }
            return replayedPatches
        } catch {
            let replayError = error
            do {
                try restore(replayedPatches)
            } catch {
                throw RuntimeError(
                    code: .patchRestorationFailed,
                    message: "The Runtime could not fully revert the failed patch set.",
                    recoverySuggestion: String(describing: error)
                )
            }
            throw replayError
        }
    }

    private func restore(_ activePatches: [ActivePatch]) throws {
        for activePatch in activePatches.reversed() {
            _ = try restore(activePatch)
        }
    }

    private func store(
        _ activePatches: [ActivePatch],
        for domain: RuntimeAttributeMutationDomain
    ) {
        for patchID in patchIDsByDomain[domain, default: []] {
            patchesByID.removeValue(forKey: patchID)
        }
        guard !activePatches.isEmpty else {
            patchIDsByDomain.removeValue(forKey: domain)
            return
        }
        patchIDsByDomain[domain] = activePatches.map(\.record.patchID)
        for activePatch in activePatches {
            patchesByID[activePatch.record.patchID] = activePatch
        }
    }

    private func restoreAll() throws -> [RuntimeOpaqueIdentifier] {
        var revertedPatchIDs = [RuntimeOpaqueIdentifier]()
        var firstError: Error?
        for patchID in patchOrder.reversed() {
            guard let activePatch = patchesByID[patchID] else {
                continue
            }
            do {
                _ = try restore(activePatch)
                remove(activePatch)
                revertedPatchIDs.append(patchID)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw RuntimeError(
                code: .patchRestorationFailed,
                message: "One or more temporary attributes could not be restored.",
                recoverySuggestion: String(describing: firstError)
            )
        }
        return revertedPatchIDs
    }

    private func restore(_ activePatch: ActivePatch) throws -> RuntimeAttributeValue? {
        do {
            let restoredValue = try activePatch.restore()
            guard optionalValuesMatch(
                restoredValue,
                activePatch.record.originalValue
            ) else {
                throw RuntimeError(
                    code: .patchRestorationFailed,
                    message: "The temporary attribute did not return to its original value.",
                    recoverySuggestion: nil
                )
            }
            return restoredValue
        } catch let error as RuntimeError {
            throw error
        } catch {
            throw RuntimeError(
                code: .patchRestorationFailed,
                message: "The temporary attribute could not be restored.",
                recoverySuggestion: nil
            )
        }
    }

    private func validate(
        _ mutation: RuntimeAttributeMutation,
        requestedValue: RuntimeAttributeValue
    ) throws {
        let expectedValue = mutation.comparisonValue ?? requestedValue
        guard let actualValue = mutation.actualValue,
              valuesMatch(actualValue, expectedValue) else {
            let restoredValue: RuntimeAttributeValue?
            do {
                restoredValue = try mutation.restore()
            } catch {
                throw RuntimeError(
                    code: .patchRestorationFailed,
                    message: "The Runtime could not revert the unapplied temporary attribute.",
                    recoverySuggestion: String(describing: error)
                )
            }
            guard optionalValuesMatch(restoredValue, mutation.originalValue) else {
                throw RuntimeError(
                    code: .patchRestorationFailed,
                    message: "The Runtime could not restore the original value after attribute validation failed.",
                    recoverySuggestion: nil
                )
            }
            throw RuntimeError(
                code: .invalidAttributeValue,
                message: "The target did not accept the requested temporary attribute value.",
                recoverySuggestion: mutator.invalidValueRecoverySuggestion
            )
        }
    }

    private func valuesMatch(
        _ lhs: RuntimeAttributeValue,
        _ rhs: RuntimeAttributeValue
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.number(lhs), .number(rhs)):
            return approximatelyEqual(lhs, rhs)
        case let (.size(lhs), .size(rhs)):
            return lhs.unit == rhs.unit
                && approximatelyEqual(lhs.width, rhs.width)
                && approximatelyEqual(lhs.height, rhs.height)
        case let (.vector(lhs), .vector(rhs)):
            return lhs.unit == rhs.unit
                && approximatelyEqual(lhs.dx, rhs.dx)
                && approximatelyEqual(lhs.dy, rhs.dy)
        case let (.color(lhs), .color(rhs)):
            return colorSpacesMatch(lhs.colorSpace, rhs.colorSpace)
                && approximatelyEqual(lhs.red, rhs.red)
                && approximatelyEqual(lhs.green, rhs.green)
                && approximatelyEqual(lhs.blue, rhs.blue)
                && approximatelyEqual(lhs.alpha, rhs.alpha)
        default:
            return lhs == rhs
        }
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_001
    }

    private func optionalValuesMatch(
        _ lhs: RuntimeAttributeValue?,
        _ rhs: RuntimeAttributeValue?
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return valuesMatch(lhs, rhs)
        case (.none, .none):
            return true
        default:
            return false
        }
    }

    private func colorSpacesMatch(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        if lhs == rhs {
            return true
        }
        let normalizedSpaces: Set<String> = ["srgb", "extended-srgb"]
        return normalizedSpaces.contains(lhs) && normalizedSpaces.contains(rhs)
    }

    private func remove(_ activePatch: ActivePatch) {
        let patchID = activePatch.record.patchID
        let domain = activePatch.descriptor.domain
        patchesByID.removeValue(forKey: patchID)
        patchIDsByDomain[domain]?.removeAll { $0 == patchID }
        if patchIDsByDomain[domain]?.isEmpty == true {
            patchIDsByDomain.removeValue(forKey: domain)
        }
        patchOrder.removeAll { $0 == patchID }
    }
}
