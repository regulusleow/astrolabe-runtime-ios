import AstrolabeProtocol
import AstrolabeRuntimeCore
import Foundation
import XCTest

final class RuntimeSemanticSnapshotStoreTests: XCTestCase {
    @MainActor func testFrozenAIsUnchangedAfterBAndWrongIdentitiesReject() throws {
        let store = RuntimeSemanticSnapshotStore(now: { 100 })
        let a = try fixture("A", time: 100)
        let b = try fixture("B", time: 100)
        try store.insert(capture: a.0, details: [a.1])
        try store.insert(capture: b.0, details: [b.1])
        XCTAssertEqual(try store.detail(nodeID: a.1.nodeID, snapshotID: a.0.snapshotID), a.1)
        assertError(.invalidParameters) { try store.detail(nodeID: b.1.nodeID, snapshotID: a.0.snapshotID) }
        assertError(try RuntimeErrorCode(rawValue: "inspection.snapshotUnavailable")) {
            try store.detail(nodeID: a.1.nodeID, snapshotID: id("missing"))
        }
    }

    @MainActor func testExpiryAt300SecondsAndReadDoesNotRenew() throws {
        let clock = Clock()
        let store = RuntimeSemanticSnapshotStore(now: { clock.time })
        let a = try fixture("A", time: 100)
        try store.insert(capture: a.0, details: [a.1])
        clock.time = 399
        XCTAssertEqual(try store.detail(nodeID: a.1.nodeID, snapshotID: a.0.snapshotID), a.1)
        clock.time = 400
        assertError(try RuntimeErrorCode(rawValue: "inspection.snapshotUnavailable")) {
            try store.detail(nodeID: a.1.nodeID, snapshotID: a.0.snapshotID)
        }
    }

    @MainActor func testFifthCaptureEvictsOldestRegardlessOfReads() throws {
        let store = RuntimeSemanticSnapshotStore(now: { 100 })
        let first = try fixture("0", time: 100)
        for index in 0..<4 {
            let value = try fixture(String(index), time: 100)
            try store.insert(capture: value.0, details: [value.1])
        }
        _ = try store.detail(nodeID: first.1.nodeID, snapshotID: first.0.snapshotID)
        let fifth = try fixture("4", time: 100)
        try store.insert(capture: fifth.0, details: [fifth.1])
        assertError(try RuntimeErrorCode(rawValue: "inspection.snapshotUnavailable")) {
            try store.detail(nodeID: first.1.nodeID, snapshotID: first.0.snapshotID)
        }
        XCTAssertEqual(try store.detail(nodeID: fifth.1.nodeID, snapshotID: fifth.0.snapshotID), fifth.1)
    }

    @MainActor func testEncodedDetailsCountTowardSingleCaptureLimitAndFailureIsAtomic() throws {
        let store = RuntimeSemanticSnapshotStore(now: { 100 })
        let a = try fixture("A", time: 100)
        try store.insert(capture: a.0, details: [a.1])
        let huge = try fixture("huge", time: 100, sectionValue: String(repeating: "x", count: 4 * 1024 * 1024))
        assertError(try RuntimeErrorCode(rawValue: "inspection.captureTooLarge")) {
            try store.insert(capture: huge.0, details: [huge.1])
        }
        XCTAssertEqual(try store.detail(nodeID: a.1.nodeID, snapshotID: a.0.snapshotID), a.1)
    }

    @MainActor func testMismatchedFrozenContextCannotBeInserted() throws {
        let store = RuntimeSemanticSnapshotStore(now: { 100 })
        let a = try fixture("A", time: 100)
        let b = try fixture("B", time: 100)
        assertError(.invalidParameters) { try store.insert(capture: a.0, details: [b.1]) }
        assertError(.invalidParameters) { try store.insert(capture: a.0, details: []) }
    }

    @MainActor func testFourLargeCapturesRespectTotalBudgetAndRetainFrozenValues() throws {
        let store = RuntimeSemanticSnapshotStore(now: { 100 })
        var captures: [(RuntimeHierarchySnapshotPayload, RuntimeNodeDetailPayload)] = []
        for index in 0..<4 {
            let value = try fixture(String(index), time: 100, sectionValue: String(repeating: String(index), count: 4 * 1024 * 1024 - 4_096))
            try store.insert(capture: value.0, details: [value.1])
            captures.append(value)
        }
        // Four legal captures can approach 16 MiB; neither reads nor new captures increase capacity.
        for value in captures {
            XCTAssertEqual(try store.detail(nodeID: value.1.nodeID, snapshotID: value.0.snapshotID), value.1)
        }
        let fifth = try fixture("fifth", time: 100)
        try store.insert(capture: fifth.0, details: [fifth.1])
        assertError(try RuntimeErrorCode(rawValue: "inspection.snapshotUnavailable")) {
            try store.detail(nodeID: captures[0].1.nodeID, snapshotID: captures[0].0.snapshotID)
        }
    }

    @MainActor func testSupportedRouteUsesOriginalFrozenDetailAndNeverFallsBackAfterExpiry() async throws {
        let clock = Clock()
        let a = try fixture("A", time: 100)
        let b = try fixture("B", time: 100)
        let provider = FrozenProvider(capture: a.0, details: [a.1], store: RuntimeSemanticSnapshotStore(now: { clock.time }))
        let live = LiveProvider()
        let services = RuntimeInspectionServices(appInfoProvider: live, hierarchyProvider: live, nodeDetailProvider: live, semanticProvider: provider)
        _ = try await services.capture(parameters: .init(semanticCapture: .init()))
        provider.currentCapture = b.0
        provider.currentDetails = [b.1]
        _ = try await services.capture(parameters: .init(semanticCapture: .init()))
        let frozen = try await services.detail(parameters: .init(nodeID: a.1.nodeID, snapshotID: a.0.snapshotID))
        XCTAssertEqual(frozen, a.1)
        XCTAssertEqual(frozen.sections.first?.attributes.first?.value, .string("A"))
        clock.time = 400
        do {
            _ = try await services.detail(parameters: .init(nodeID: a.1.nodeID, snapshotID: a.0.snapshotID))
            XCTFail("Expired semantic detail cannot fall back to live provider")
        } catch let error as RuntimeError { XCTAssertEqual(error.code.rawValue, "inspection.snapshotUnavailable") }
        XCTAssertEqual(live.calls, 0)
    }

    @MainActor func testSemanticRouteRejectsUnsupportedAndMissingSnapshotWithoutLiveFallback() async throws {
        let live = LiveProvider()
        let services = RuntimeInspectionServices(appInfoProvider: live, hierarchyProvider: live, nodeDetailProvider: live)
        do {
            _ = try await services.capture(parameters: RuntimeHierarchySnapshotParameters(semanticCapture: .init()))
            XCTFail("Semantic capture must reject unsupported provider")
        } catch let error as RuntimeError { XCTAssertEqual(error.code, .capabilityUnavailable) }
        do {
            _ = try await services.detail(parameters: RuntimeNodeDetailParameters(nodeID: id("semantic-A"), snapshotID: id("A")))
            XCTFail("Frozen detail must reject unsupported provider")
        } catch let error as RuntimeError { XCTAssertEqual(error.code, .capabilityUnavailable) }
        do {
            _ = try await services.detail(parameters: RuntimeNodeDetailParameters(nodeID: id("semantic-A")))
            XCTFail("Semantic ID requires snapshot")
        } catch let error as RuntimeError { XCTAssertEqual(error.code, .invalidParameters) }
        XCTAssertEqual(live.calls, 0)
    }

    private func fixture(_ name: String, time: Double, sectionValue: String? = nil) throws -> (RuntimeHierarchySnapshotPayload, RuntimeNodeDetailPayload) {
        let nodeID = id("semantic-" + name)
        let capture = RuntimeHierarchySnapshotPayload(
            snapshotID: id(name), capturedAtUnixTime: time, targetIdentifier: id("target"), orientation: "portrait",
            display: RuntimeDisplayInfo(logicalSize: .init(width: 1, height: 1, unit: .logical), pixelSize: .init(width: 1, height: 1, unit: .pixel), logicalToPixelScale: .init(x: 1, y: 1), maximumRefreshRate: 60),
            viewport: .init(x: 0, y: 0, width: 1, height: 1, coordinateSpace: .screen, unit: .logical), roots: [],
            semanticCapture: try RuntimeSemanticCapture(windowID: id("window"), source: nameID("ios.accessibility"), availability: .complete, issues: [], visitedNodeCount: 1, wasTruncated: false, roots: [RuntimeSemanticNode(nodeID: nodeID, parentID: nil, siblingIndex: 0, role: "text", runtimeType: .init(name: "NSObject", ancestors: []), availableDetailCategories: [], children: [])])
        )
        let detail = RuntimeNodeDetailPayload(nodeID: nodeID,
            sections: [.init(category: try RuntimeAttributeCategory(rawValue: "common.text"), attributes: [.init(identifier: try RuntimeAttributeIdentifier(rawValue: "common.text.content"), value: .string(sectionValue ?? name))])],
            semanticContext: try RuntimeSemanticDetailContext(snapshotID: id(name), capturedAtUnixTime: time, source: nameID("ios.accessibility"), availability: .complete, issues: [], wasTruncated: false, textCandidates: []))
        return (capture, detail)
    }

    private func assertError<T>(_ code: RuntimeErrorCode, operation: () throws -> T) {
        XCTAssertThrowsError(try operation()) { XCTAssertEqual(($0 as? RuntimeError)?.code, code) }
    }

    private func id(_ value: String) -> RuntimeOpaqueIdentifier { try! .init(rawValue: value) }
    private func nameID(_ value: String) -> RuntimeNamespacedIdentifier { try! .init(rawValue: value) }
}

@MainActor private final class FrozenProvider: RuntimeSemanticInspectionProviding {
    /// Next capture value, simulating application state changes without UI dependencies.
    var currentCapture: RuntimeHierarchySnapshotPayload
    /// Next details, frozen at capture rather than resolved during lookup.
    var currentDetails: [RuntimeNodeDetailPayload]
    /// Real bounded store exercised by the service route.
    let store: RuntimeSemanticSnapshotStore
    init(capture: RuntimeHierarchySnapshotPayload, details: [RuntimeNodeDetailPayload], store: RuntimeSemanticSnapshotStore) {
        currentCapture = capture
        currentDetails = details
        self.store = store
    }
    func capture(options: RuntimeSemanticCaptureOptions) async throws -> RuntimeHierarchySnapshotPayload {
        try store.insert(capture: currentCapture, details: currentDetails)
        return currentCapture
    }
    func detail(nodeID: RuntimeOpaqueIdentifier, snapshotID: RuntimeOpaqueIdentifier) async throws -> RuntimeNodeDetailPayload {
        try store.detail(nodeID: nodeID, snapshotID: snapshotID)
    }
}

private final class Clock: @unchecked Sendable {
    /// Test-owned monotonic capture clock.
    var time = 100.0
}

@MainActor private final class LiveProvider: RuntimeAppInfoProviding, RuntimeHierarchyProviding, RuntimeNodeDetailProviding {
    /// Number of forbidden live fallbacks.
    var calls = 0
    func appInfo(runtime: RuntimeDescriptor) async throws -> RuntimeApplicationInfoPayload { fatalError() }
    func hierarchySnapshot() async throws -> RuntimeHierarchySnapshotPayload { calls += 1; throw CancellationError() }
    func nodeDetail(for nodeID: RuntimeOpaqueIdentifier) async throws -> RuntimeNodeDetailPayload { calls += 1; throw CancellationError() }
}
