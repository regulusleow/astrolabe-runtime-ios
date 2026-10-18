#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore
import UIKit

/// Read-only public AX traversal with snapshot-local identities and frozen Text details.
@MainActor
struct UIKitSemanticAccessibilityCollector {
    struct Capture {
        /// AX container tree, including containers without semantic content.
        let roots: [RuntimeSemanticNode]
        /// Frozen detail values for every retained semantic node.
        let details: [RuntimeNodeDetailPayload]
        /// Direct object-identity witnesses into this capture's render roots.
        let relations: [RuntimeNodeRelation]
        /// Local omissions and traversal failures.
        let issues: [RuntimeInspectionIssue]
        /// Unique AX objects actually visited, including containers.
        let visits: Int
        /// Number of nodes with public AX content.
        let semanticCount: Int
        /// Whether work was refused by any budget.
        let truncated: Bool
    }

    /// Shared native registry; semantic IDs never use its identifiers.
    let registry: RuntimeNodeRegistry

    /// Bounded readiness only: no AX value, private attachments, or output objects are read/created.
    func publicSemanticTreeIsReady(in window: UIWindow) -> Bool {
        var budget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 2_000)
        var pending: [(object: NSObject, depth: Int)] = [(window, 0)]
        var seen = Set<ObjectIdentifier>()
        while let entry = pending.popLast() {
            guard seen.insert(ObjectIdentifier(entry.object)).inserted,
                  budget.consume(depth: entry.depth) else { continue }
            let object = entry.object
            if object.isAccessibilityElement || object.accessibilityLabel?.isEmpty == false ||
                object.accessibilityHint?.isEmpty == false || !UIKitRuntimeAccessibilityMapper().runtimeTraits(object.accessibilityTraits).isEmpty { return true }
            func enqueue(_ value: Any) {
                guard let child = value as? NSObject else { return }
                guard pending.count + budget.visits < 2_000 else { budget.markTruncated(); return }
                pending.append((child, entry.depth + 1))
            }
            if let elements = object.accessibilityElements, !elements.isEmpty {
                for child in elements.prefix(budget.boundedChildCount(elements.count)).reversed() { enqueue(child) }
            } else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound && count > 0 {
                    for index in (0..<budget.boundedChildCount(count)).reversed() {
                        if let child = object.accessibilityElement(at: index) { enqueue(child) }
                    }
                } else if let view = object as? UIView {
                    for child in view.subviews.prefix(budget.boundedChildCount(view.subviews.count)).reversed() { enqueue(child) }
                }
            }
        }
        return false
    }

    func capture(window: UIWindow, snapshotID: RuntimeOpaqueIdentifier, capturedAt: Double,
                 renderRoots: [RuntimeNode], privacyIssue: RuntimeInspectionIssue?) throws -> Capture {
        var budget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 2_000)
        var textBudget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 10_000)
        var seen = Set<ObjectIdentifier>()
        var details: [RuntimeNodeDetailPayload] = []
        var relations: [RuntimeNodeRelation] = []
        var issues = privacyIssue.map { [$0] } ?? []
        var semanticCount = 0
        var attachmentObjects = 0
        var outputBytes = 0
        var outputStopped = false
        var renderIDs = Set<RuntimeOpaqueIdentifier>()
        func index(_ node: RuntimeNode) { renderIDs.insert(node.nodeID); node.children.forEach(index) }
        renderRoots.forEach(index)
        let prefix = "semantic-" + UUID().uuidString + "-"

        func bounded(_ value: String?, path: String) -> String? {
            guard let value, !value.isEmpty else { return nil }
            guard value.utf8.count <= 16_384 else {
                issues.append(semanticIssue("valueTooLarge", path: path)); return nil
            }
            return value
        }

        func walk(_ object: NSObject, parent: RuntimeOpaqueIdentifier?, sibling: Int, depth: Int) throws -> RuntimeSemanticNode? {
            guard !outputStopped else { return nil }
            guard seen.insert(ObjectIdentifier(object)).inserted else {
                issues.append(semanticIssue("repeatedReference")); return nil
            }
            guard budget.consume(depth: depth) else { return nil }
            let nodeID = try RuntimeOpaqueIdentifier(rawValue: prefix + String(budget.visits))
            let label = bounded(object.accessibilityLabel, path: "accessibility.label")
            let value = privacyIssue == nil ? bounded(object.accessibilityValue, path: "accessibility.value") : nil
            let hint = bounded(object.accessibilityHint, path: "accessibility.hint")
            let identifier: String?
            if let view = object as? UIView { identifier = bounded(view.accessibilityIdentifier, path: "accessibility.identifier") }
            else if object.responds(to: NSSelectorFromString("accessibilityIdentifier")) {
                identifier = bounded(object.value(forKey: "accessibilityIdentifier") as? String, path: "accessibility.identifier")
            } else { identifier = nil }
            let traits = UIKitRuntimeAccessibilityMapper().runtimeTraits(object.accessibilityTraits)
            let isElement = object.isAccessibilityElement
            let hasContent = isElement || label != nil || value != nil || hint != nil || identifier != nil || !traits.isEmpty
            if hasContent {
                guard semanticCount < 500 else { budget.markTruncated(); return nil }
                semanticCount += 1
            }
            let ax = hasContent ? RuntimeAccessibility(element: isElement, identifier: identifier, label: label, value: value, hint: hint, traits: traits) : nil
            let frame = object.accessibilityFrame
            let validFrame = frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite && frame.width >= 0 && frame.height >= 0
            if !validFrame { issues.append(semanticIssue("invalidFrame")) }
            var projectionIssues: [RuntimeInspectionIssue] = []
            var candidates: [RuntimeSemanticTextCandidate] = []
            var attributes: [RuntimeAttribute] = []
            var projectionTruncated = false
            let projectionStartBytes = outputBytes
            if NSStringFromClass(type(of: object)) == "SwiftUI.AccessibilityNode" {
                if let privacyIssue { projectionIssues.append(privacyIssue) }
                else if attachmentObjects >= 30 {
                    projectionIssues.append(semanticIssue("attachmentLimit")); projectionTruncated = true
                } else {
                    let started = textBudget.visits
                    let projection = try SwiftUITextAttachmentProjector.project(node: object, budget: &textBudget, outputBytes: &outputBytes)
                    if textBudget.visits > started { attachmentObjects += 1 }
                    candidates = projection.candidates
                    attributes = projection.canonicalAttributes
                    projectionIssues = projection.issues
                    projectionTruncated = projection.truncated
                }
            }
            let detail = RuntimeNodeDetailPayload(nodeID: nodeID,
                sections: attributes.isEmpty ? [] : [.init(category: try .init(rawValue: "common.text"), attributes: attributes)],
                semanticContext: try RuntimeSemanticDetailContext(snapshotID: snapshotID, capturedAtUnixTime: capturedAt,
                    source: semanticName("ios.accessibility"), availability: projectionIssues.isEmpty ? .complete : (candidates.isEmpty ? .unavailable : .partial),
                    issues: projectionIssues, wasTruncated: projectionTruncated, textCandidates: candidates))
            let runtimeType = RuntimeType(name: String(reflecting: type(of: object)), ancestors: [])
            let role = traits.contains("button") ? "button" : (traits.contains("staticText") ? "text" : "container")
            let ownNode = try RuntimeSemanticNode(nodeID: nodeID, parentID: parent, siblingIndex: sibling, role: role,
                runtimeType: runtimeType, accessibility: ax, frameInScreen: validFrame ? runtimeRect(frame, space: .screen) : nil,
                availableDetailCategories: attributes.isEmpty ? [] : [semanticName("common.text")], children: [])
            let ownBytes = try JSONEncoder().encode(ownNode).count + JSONEncoder().encode(detail).count
            let alreadyCounted = outputBytes - projectionStartBytes
            guard outputBytes + ownBytes - alreadyCounted <= 4 * 1024 * 1024 else {
                outputStopped = true
                budget.markTruncated()
                issues.append(semanticIssue("outputBudgetExceeded"))
                return nil
            }
            outputBytes += ownBytes - alreadyCounted
            details.append(detail)
            issues.append(contentsOf: projectionIssues)
            if projectionTruncated { budget.markTruncated() }
            if let view = object as? UIView {
                let nativeID = registry.nodeID(for: view)
                if renderIDs.contains(nativeID) {
                    relations.append(RuntimeNodeRelation(type: semanticName("ios.accessibility.representsView"), sourceNodeID: nodeID, targetNodeID: nativeID, extensions: try .init()))
                }
            }
            var children: [RuntimeSemanticNode] = []
            func append(_ child: Any) throws {
                guard let child = child as? NSObject else {
                    issues.append(semanticIssue("unsupportedObject")); return
                }
                if let node = try walk(child, parent: nodeID, sibling: children.count, depth: depth + 1) { children.append(node) }
            }
            if let elements = object.accessibilityElements, !elements.isEmpty {
                for (index, child) in elements.prefix(budget.boundedChildCount(elements.count)).enumerated() {
                    try append(child)
                    if outputStopped || budget.visits == 2_000 {
                        if index + 1 < elements.count { budget.markTruncated() }
                        break
                    }
                }
            } else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound && count > 0 {
                    for index in 0..<budget.boundedChildCount(count) {
                        if let child = object.accessibilityElement(at: index) { try append(child) }
                        else { issues.append(semanticIssue("missingChild")) }
                        if outputStopped || budget.visits == 2_000 {
                            if index + 1 < count { budget.markTruncated() }
                            break
                        }
                    }
                } else if let view = object as? UIView {
                    for (index, child) in view.subviews.prefix(budget.boundedChildCount(view.subviews.count)).enumerated() {
                        try append(child)
                        if outputStopped || budget.visits == 2_000 {
                            if index + 1 < view.subviews.count { budget.markTruncated() }
                            break
                        }
                    }
                }
            }
            return try RuntimeSemanticNode(nodeID: ownNode.nodeID, parentID: parent, siblingIndex: sibling, role: role,
                runtimeType: runtimeType, accessibility: ax, frameInScreen: ownNode.frameInScreen,
                availableDetailCategories: ownNode.availableDetailCategories, children: children)
        }
        let root = try walk(window, parent: nil, sibling: 0, depth: 0)
        if budget.truncated { issues.append(semanticIssue("budgetExceeded")) }
        // Capture-level diagnostics are deduplicated; per-node contexts retain their paths.
        var unique: [RuntimeInspectionIssue] = []
        for issue in issues where !unique.contains(issue) {
            guard unique.count < 1_998 else { budget.markTruncated(); break }
            unique.append(issue)
        }
        if budget.truncated && !unique.contains(semanticIssue("budgetExceeded")) { unique.append(semanticIssue("budgetExceeded")) }
        return Capture(roots: root.map { [$0] } ?? [], details: details, relations: relations,
                       issues: unique, visits: budget.visits, semanticCount: semanticCount, truncated: budget.truncated || textBudget.truncated)
    }
}
#endif
