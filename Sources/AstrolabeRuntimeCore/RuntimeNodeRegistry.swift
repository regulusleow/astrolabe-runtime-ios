//
//  RuntimeNodeRegistry.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol
import Foundation

@MainActor
package final class RuntimeNodeRegistry: Sendable {
    private final class Entry {
        weak var object: AnyObject?
        let nodeID: RuntimeOpaqueIdentifier

        init(object: AnyObject, nodeID: RuntimeOpaqueIdentifier) {
            self.object = object
            self.nodeID = nodeID
        }
    }

    private var nextRawID: UInt64 = 1
    private var entriesByObjectID = [ObjectIdentifier: Entry]()
    private var entriesByNodeID = [RuntimeOpaqueIdentifier: Entry]()

    package init() {}

    package func nodeID(for object: AnyObject) -> RuntimeOpaqueIdentifier {
        let objectID = ObjectIdentifier(object)
        if let entry = entriesByObjectID[objectID], entry.object === object {
            return entry.nodeID
        }

        let nodeID: RuntimeOpaqueIdentifier
        do {
            nodeID = try RuntimeOpaqueIdentifier(rawValue: String(nextRawID))
        } catch {
            preconditionFailure("The Runtime generated an invalid node identifier: \(nextRawID)")
        }
        nextRawID += 1
        let entry = Entry(object: object, nodeID: nodeID)
        entriesByObjectID[objectID] = entry
        entriesByNodeID[nodeID] = entry
        return nodeID
    }

    package func object(for nodeID: RuntimeOpaqueIdentifier) -> AnyObject? {
        entriesByNodeID[nodeID]?.object
    }

    package func pruneReleasedObjects() {
        let releasedNodeIDs = entriesByNodeID.compactMap { nodeID, entry in
            entry.object == nil ? nodeID : nil
        }
        for nodeID in releasedNodeIDs {
            entriesByNodeID.removeValue(forKey: nodeID)
        }

        entriesByObjectID = entriesByObjectID.filter { _, entry in
            entry.object != nil
        }
    }
}
