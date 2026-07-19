//
//  RuntimeAttributePatchServiceTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/13.
//

@testable import AstrolabeRuntimeCore
import AstrolabeProtocol
import XCTest

final class RuntimeAttributePatchServiceTests: XCTestCase {
    @MainActor
    func testPatchableAttributesComeFromMutatorCatalog() async throws {
        let expected = RuntimePatchableAttributesPayload(
            attributes: [
                try RuntimePatchableAttribute(
                    attributePattern: "test.value",
                    valueType: RuntimePatchValueType(rawValue: "number"),
                    targetRoles: ["value"],
                    valueConstraints: nil,
                    extensions: RuntimeExtensionMap()
                )
            ]
        )
        let service = RuntimeAttributePatchService(
            nodeRegistry: RuntimeNodeRegistry(),
            mutator: PatchValueMutator(patchableAttributeCatalog: expected)
        )

        let actual = await service.patchableAttributes()
        XCTAssertEqual(actual, expected)
    }

    @MainActor
    func testRepeatedPatchReusesIdentifierAndRestoresInitialValue() async throws {
        let registry = RuntimeNodeRegistry()
        let object = PatchValueBox(value: 1)
        let nodeID = registry.nodeID(for: object)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator()
        )

        let first = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 2)
        )
        let second = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 3)
        )

        XCTAssertEqual(first.patchID, second.patchID)
        XCTAssertEqual(second.originalValue, .number(1))
        XCTAssertEqual(second.actualValue, .number(3))
        XCTAssertEqual(object.value, 3)
        let list = await service.activeAttributePatches()
        XCTAssertEqual(list.patches, [second])

        let response = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: second.patchID)
        )
        XCTAssertEqual(response.restoredValue, .number(1))
        XCTAssertEqual(response.remainingPatchCount, 0)
        XCTAssertEqual(object.value, 1)
    }

    @MainActor
    func testOverlappingAttributeRequiresExplicitRevert() async throws {
        let registry = RuntimeNodeRegistry()
        let object = PatchValueBox(value: 1)
        let nodeID = registry.nodeID(for: object)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator()
        )
        _ = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 2)
        )

        do {
            _ = try await service.applyAttributePatch(
                request(nodeID: nodeID, attribute: "test.alias", value: 3)
            )
            XCTFail("Overlapping attributes must require reverting the existing patch first")
        } catch let error as RuntimeError {
            XCTAssertEqual(error.code, .patchConflict)
        }
    }

    @MainActor
    func testIndependentAttributesInSameDomainComposeAndRevertIndependently() async throws {
        let registry = RuntimeNodeRegistry()
        let object = PatchValueBox(value: 1, secondaryValue: 10)
        let nodeID = registry.nodeID(for: object)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator()
        )

        let valuePatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 2)
        )
        let secondaryPatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.secondary", value: 20)
        )

        XCTAssertEqual(object.value, 2)
        XCTAssertEqual(object.secondaryValue, 20)
        let activePatches = await service.activeAttributePatches().patches
        XCTAssertEqual(
            activePatches,
            [valuePatch, secondaryPatch]
        )

        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: valuePatch.patchID)
        )
        XCTAssertEqual(object.value, 1)
        XCTAssertEqual(object.secondaryValue, 20)

        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: secondaryPatch.patchID)
        )
        XCTAssertEqual(object.secondaryValue, 10)
    }

    @MainActor
    func testIndependentAttributesCanBeUpdatedRepeatedlyWithoutLosingBaseline() async throws {
        let registry = RuntimeNodeRegistry()
        let object = PatchValueBox(value: 1, secondaryValue: 10)
        let nodeID = registry.nodeID(for: object)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator()
        )

        let firstValuePatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 2)
        )
        let firstSecondaryPatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.secondary", value: 20)
        )
        let updatedValuePatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 3)
        )
        let updatedSecondaryPatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.secondary", value: 15)
        )

        XCTAssertEqual(updatedValuePatch.patchID, firstValuePatch.patchID)
        XCTAssertEqual(updatedSecondaryPatch.patchID, firstSecondaryPatch.patchID)
        XCTAssertEqual(updatedValuePatch.originalValue, .number(1))
        XCTAssertEqual(updatedSecondaryPatch.originalValue, .number(10))
        XCTAssertEqual(object.value, 3)
        XCTAssertEqual(object.secondaryValue, 15)

        let clear = try await service.clearAttributePatches()
        XCTAssertEqual(Set(clear.revertedPatchIDs), [
            firstValuePatch.patchID,
            firstSecondaryPatch.patchID
        ])
        XCTAssertEqual(object.value, 1)
        XCTAssertEqual(object.secondaryValue, 10)
    }

    @MainActor
    func testRejectedCombinedUpdateRestoresPreviousPatchCombination() async throws {
        let registry = RuntimeNodeRegistry()
        let object = PatchValueBox(value: 1, secondaryValue: 10)
        let nodeID = registry.nodeID(for: object)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator(rejectedValues: [99])
        )
        let valuePatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 2)
        )
        let secondaryPatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.secondary", value: 20)
        )

        do {
            _ = try await service.applyAttributePatch(
                request(nodeID: nodeID, attribute: "test.value", value: 99)
            )
            XCTFail("A failed combined patch update must not register new state")
        } catch let error as RuntimeError {
            XCTAssertEqual(error.code, .invalidAttributeValue)
        }

        XCTAssertEqual(object.value, 2)
        XCTAssertEqual(object.secondaryValue, 20)
        let activePatches = await service.activeAttributePatches().patches
        XCTAssertEqual(activePatches, [valuePatch, secondaryPatch])
    }

    @MainActor
    func testPartialRewindFailureRestoresPreviouslyActiveCombination() async throws {
        let registry = RuntimeNodeRegistry()
        let object = PatchValueBox(value: 1, secondaryValue: 10)
        let nodeID = registry.nodeID(for: object)
        let failureControl = PatchMutationFailureControl()
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator(
                failureControl: failureControl
            )
        )
        let valuePatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 2)
        )
        let secondaryPatch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.secondary", value: 20)
        )
        failureControl.nonRestoringAttributes = ["test.value"]

        do {
            _ = try await service.applyAttributePatch(
                request(nodeID: nodeID, attribute: "test.secondary", value: 30)
            )
            XCTFail("An update must not continue after reverting the existing combination fails")
        } catch let error as RuntimeError {
            XCTAssertEqual(error.code, .patchRestorationFailed)
        }

        XCTAssertEqual(object.value, 2)
        XCTAssertEqual(object.secondaryValue, 20)
        let activePatches = await service.activeAttributePatches().patches
        XCTAssertEqual(activePatches, [valuePatch, secondaryPatch])
    }

    @MainActor
    func testRejectedMutationRestoresValueAndDoesNotRegisterPatch() async throws {
        let registry = RuntimeNodeRegistry()
        let object = PatchValueBox(value: 1)
        let nodeID = registry.nodeID(for: object)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator(
                acceptsMutation: false,
                invalidValueRecoverySuggestion: "Test platform recovery suggestion"
            )
        )

        do {
            _ = try await service.applyAttributePatch(
                request(nodeID: nodeID, attribute: "test.value", value: 2)
            )
            XCTFail("A patch that was not applied must not be registered as successful")
        } catch let error as RuntimeError {
            XCTAssertEqual(error.code, .invalidAttributeValue)
            XCTAssertEqual(error.recoverySuggestion, "Test platform recovery suggestion")
        }

        XCTAssertEqual(object.value, 1)
        let list = await service.activeAttributePatches()
        XCTAssertTrue(list.patches.isEmpty)
    }

    @MainActor
    func testFailedRestorationKeepsPatchActive() async throws {
        let registry = RuntimeNodeRegistry()
        let object = PatchValueBox(value: 1)
        let nodeID = registry.nodeID(for: object)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator(restoresMutation: false)
        )
        let patch = try await service.applyAttributePatch(
            request(nodeID: nodeID, attribute: "test.value", value: 2)
        )

        do {
            _ = try await service.revertAttributePatch(
                RuntimeRevertAttributePatchParameters(patchID: patch.patchID)
            )
            XCTFail("A patch must not be removed when the restored value does not match")
        } catch let error as RuntimeError {
            XCTAssertEqual(error.code, .patchRestorationFailed)
        }

        XCTAssertEqual(object.value, 2)
        let list = await service.activeAttributePatches()
        XCTAssertEqual(list.patches, [patch])
    }

    @MainActor
    func testClearAndSessionEndRestoreAllValues() async throws {
        let registry = RuntimeNodeRegistry()
        let firstObject = PatchValueBox(value: 1)
        let secondObject = PatchValueBox(value: 10)
        let firstNodeID = registry.nodeID(for: firstObject)
        let secondNodeID = registry.nodeID(for: secondObject)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: PatchValueMutator()
        )
        let first = try await service.applyAttributePatch(
            request(nodeID: firstNodeID, attribute: "test.value", value: 2)
        )
        _ = try await service.applyAttributePatch(
            request(nodeID: secondNodeID, attribute: "test.value", value: 20)
        )

        let clear = try await service.clearAttributePatches()
        XCTAssertEqual(clear.revertedPatchIDs.count, 2)
        XCTAssertEqual(clear.remainingPatchCount, 0)
        XCTAssertEqual(firstObject.value, 1)
        XCTAssertEqual(secondObject.value, 10)

        _ = try await service.applyAttributePatch(
            request(nodeID: firstNodeID, attribute: "test.value", value: 4)
        )
        _ = try await service.clearAttributePatches()
        XCTAssertEqual(firstObject.value, 1)
        do {
            _ = try await service.revertAttributePatch(
                RuntimeRevertAttributePatchParameters(patchID: first.patchID)
            )
            XCTFail("No patches should remain after clearing")
        } catch let error as RuntimeError {
            XCTAssertEqual(error.code, .patchNotFound)
        }
    }

    private func request(
        nodeID: RuntimeOpaqueIdentifier,
        attribute: String,
        value: Double
    ) throws -> RuntimeApplyAttributePatchParameters {
        RuntimeApplyAttributePatchParameters(
            nodeID: nodeID,
            attributeIdentifier: try RuntimeAttributeIdentifier(
                rawValue: attribute
            ),
            value: .number(value)
        )
    }
}

@MainActor
private final class PatchValueBox {
    /// Mutable value used to verify patch and restoration behavior.
    var value: Double

    /// Independent mutable value sharing the same mutation scope.
    var secondaryValue: Double

    init(value: Double, secondaryValue: Double = 0) {
        self.value = value
        self.secondaryValue = secondaryValue
    }
}

@MainActor
private final class PatchMutationFailureControl {
    /// Semantic attributes whose captured restoration intentionally does nothing.
    var nonRestoringAttributes = Set<String>()
}

@MainActor
private struct PatchValueMutator: RuntimeAttributeMutating {
    /// Attributes the test mutator advertises as patchable.
    let patchableAttributeCatalog: RuntimePatchableAttributesPayload

    /// Whether the test target accepts the requested mutation.
    let acceptsMutation: Bool

    /// Whether restoration writes the captured original value.
    let restoresMutation: Bool

    /// Recovery guidance returned for rejected test values.
    let invalidValueRecoverySuggestion: String?

    /// Requested numeric values that the test target rejects.
    let rejectedValues: Set<Double>

    /// Mutable failure injection shared with restoration closures.
    let failureControl: PatchMutationFailureControl

    init(
        patchableAttributeCatalog: RuntimePatchableAttributesPayload = RuntimePatchableAttributesPayload(
            attributes: []
        ),
        acceptsMutation: Bool = true,
        restoresMutation: Bool = true,
        invalidValueRecoverySuggestion: String? = nil,
        rejectedValues: Set<Double> = [],
        failureControl: PatchMutationFailureControl? = nil
    ) {
        self.patchableAttributeCatalog = patchableAttributeCatalog
        self.acceptsMutation = acceptsMutation
        self.restoresMutation = restoresMutation
        self.invalidValueRecoverySuggestion = invalidValueRecoverySuggestion
        self.rejectedValues = rejectedValues
        self.failureControl = failureControl ?? PatchMutationFailureControl()
    }

    func mutationDescriptor(
        for object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> RuntimeAttributeMutationDescriptor {
        guard let object = object as? PatchValueBox,
              ["test.value", "test.alias", "test.secondary"].contains(
                  attributeIdentifier.rawValue
              ) else {
            throw RuntimeError(
                code: .unsupportedAttribute,
                message: "Test attribute is unsupported",
                recoverySuggestion: nil
            )
        }
        return RuntimeAttributeMutationDescriptor(
            domain: RuntimeAttributeMutationDomain(
                objectIdentifier: ObjectIdentifier(object),
                domainIdentifier: "values"
            ),
            effectIdentifiers: [
                attributeIdentifier.rawValue == "test.secondary"
                    ? "secondaryValue"
                    : "value"
            ]
        )
    }

    func apply(
        value: RuntimeAttributeValue,
        to object: AnyObject,
        attributeIdentifier: RuntimeAttributeIdentifier
    ) throws -> RuntimeAttributeMutation {
        guard let object = object as? PatchValueBox,
              case let .number(requestedValue) = value else {
            throw RuntimeError(
                code: .invalidAttributeValue,
                message: "Test value is invalid",
                recoverySuggestion: nil
            )
        }
        let usesSecondaryValue = attributeIdentifier.rawValue == "test.secondary"
        let originalValue = usesSecondaryValue ? object.secondaryValue : object.value
        if acceptsMutation && !rejectedValues.contains(requestedValue) {
            if usesSecondaryValue {
                object.secondaryValue = requestedValue
            } else {
                object.value = requestedValue
            }
        }
        return RuntimeAttributeMutation(
            originalValue: .number(originalValue),
            actualValue: .number(usesSecondaryValue ? object.secondaryValue : object.value),
            restore: { [weak object] in
                guard let object else {
                    return nil
                }
                if restoresMutation
                    && !failureControl.nonRestoringAttributes.contains(
                        attributeIdentifier.rawValue
                    ) {
                    if usesSecondaryValue {
                        object.secondaryValue = originalValue
                    } else {
                        object.value = originalValue
                    }
                }
                return .number(usesSecondaryValue ? object.secondaryValue : object.value)
            }
        )
    }
}
