import Foundation
import XCTest
@testable import AstrolabeRuntimeUIKit

/// Pure traversal accounting and diagnostics; no UIKit object or running UI is created.
final class UIKitSemanticTraversalBudgetTests: XCTestCase {
    func testRepeatedReferencesExhaustWorkWithoutGrowingVisitedIdentities() {
        let object = NSObject()
        var seen = Set<ObjectIdentifier>()
        var budget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 2_000)
        XCTAssertEqual(budget.admitObject(ObjectIdentifier(object), depth: 0, seen: &seen), .accepted)
        for _ in 1..<2_000 {
            XCTAssertEqual(budget.admitObject(ObjectIdentifier(object), depth: 1, seen: &seen), .repeated)
        }
        XCTAssertEqual(budget.attempts, 2_000)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(budget.admitObject(ObjectIdentifier(object), depth: 1, seen: &seen), .refused)
        XCTAssertTrue(budget.truncated)
    }

    func testRejectedDepthDoesNotPoisonLaterShallowIdentity() {
        let object = NSObject()
        var seen = Set<ObjectIdentifier>()
        var budget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 2_000)
        XCTAssertEqual(budget.admitObject(ObjectIdentifier(object), depth: 20, seen: &seen), .refused)
        XCTAssertTrue(seen.isEmpty)
        XCTAssertEqual(budget.admitObject(ObjectIdentifier(object), depth: 1, seen: &seen), .accepted)
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(budget.attempts, 2)
        XCTAssertEqual(budget.visits, 1)
    }

    func testInvalidDepthAndMissingObjectsStillConsumeTheTotalWorkLimit() {
        var seen = Set<ObjectIdentifier>()
        var budget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 4)
        XCTAssertEqual(budget.admitObject(nil, depth: 1, seen: &seen), .unsupported)
        XCTAssertEqual(budget.admitObject(nil, depth: 20, seen: &seen), .refused)
        XCTAssertEqual(budget.admitObject(nil, depth: -1, seen: &seen), .refused)
        XCTAssertEqual(budget.admitObject(nil, depth: 1, seen: &seen), .unsupported)
        XCTAssertTrue(budget.exhausted)
        XCTAssertEqual(budget.admitObject(nil, depth: 1, seen: &seen), .refused)
        XCTAssertEqual(budget.attempts, 4)
        XCTAssertTrue(seen.isEmpty)
    }

    func testQueuedChildrenReserveWorkBeforeNewSlotsAreEnumerated() {
        var budget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 10)
        XCTAssertTrue(budget.consume(depth: 0))
        XCTAssertEqual(budget.boundedChildCount(20, reserved: 4), 5)
        XCTAssertTrue(budget.truncated)
        XCTAssertEqual(budget.boundedChildCount(20, reserved: 9), 0)
    }

    func testDiagnosticsDeduplicateDuringAppendAndStopAtCapacity() {
        var buffer = UIKitSemanticIssueBuffer()
        for _ in 0..<10_000 { buffer.append(semanticIssue("repeatedReference")) }
        XCTAssertEqual(buffer.values.count, 1)
        XCTAssertFalse(buffer.truncated)
        for index in 0..<2_100 {
            buffer.append(semanticIssue("unsupportedLayout", path: "node/\(index)"))
        }
        XCTAssertEqual(buffer.values.count, 1_998)
        XCTAssertTrue(buffer.truncated)
    }
}
