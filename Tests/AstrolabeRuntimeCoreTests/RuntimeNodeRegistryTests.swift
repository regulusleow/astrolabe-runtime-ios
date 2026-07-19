//
//  RuntimeNodeRegistryTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeRuntimeCore
import Foundation
import XCTest

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}

@MainActor
final class RuntimeNodeRegistryTests: XCTestCase {
    func testRegistryReturnsStableIDForSameObject() {
        let registry = RuntimeNodeRegistry()
        let object = NSObject()

        let firstID = registry.nodeID(for: object)
        let secondID = registry.nodeID(for: object)

        XCTAssertEqual(firstID, secondID)
        XCTAssertTrue(registry.object(for: firstID) === object)
    }

    func testRegistryDoesNotRetainRuntimeObject() {
        let registry = RuntimeNodeRegistry()
        var object: NSObject? = NSObject()
        let nodeID = object.map { registry.nodeID(for: $0) }
        guard let nodeID else {
            return XCTFail("Expected runtime object.")
        }
        let weakObject = WeakReference(object)

        object = nil
        registry.pruneReleasedObjects()

        XCTAssertNil(weakObject.value)
        XCTAssertNil(registry.object(for: nodeID))
    }

    func testRegistryAssignsMonotonicIDs() {
        let registry = RuntimeNodeRegistry()

        let firstID = registry.nodeID(for: NSObject())
        let secondID = registry.nodeID(for: NSObject())

        guard let firstValue = Int(firstID.rawValue),
              let secondValue = Int(secondID.rawValue) else {
            return XCTFail("Node identifiers must use monotonically increasing integer text")
        }
        XCTAssertEqual(secondValue, firstValue + 1)
    }
}
