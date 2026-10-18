#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore
import UIKit

/// Selects one valid window, freezes AX/Text values, then atomically stores the capture.
@MainActor
package final class UIKitRuntimeSemanticInspectionProvider: RuntimeSemanticInspectionProviding {
    private struct Context {
        /// Selected live window, held only during capture.
        let window: UIWindow
        /// Original scene identity.
        let scene: UIWindowScene
        /// Original screen identity.
        let screen: UIScreen
        /// Window geometry at selection.
        let bounds: CGRect
        /// Window placement at selection.
        let frame: CGRect
        /// Window transform at selection.
        let transform: CGAffineTransform
        /// Screen geometry at selection.
        let screenBounds: CGRect
        /// Original native pixel geometry used by the existing display mapper.
        let nativeBounds: CGRect
        /// Original logical screen geometry used by the existing display mapper.
        let logicalBounds: CGRect
        /// Original logical-to-pixel scale.
        let scale: CGFloat
        /// Original interface orientation.
        let orientation: UIInterfaceOrientation
    }

    /// Shared native object identity registry.
    private let registry: RuntimeNodeRegistry
    /// Existing render collector, used only with the selected context.
    private let hierarchyProvider: UIKitRuntimeHierarchyProvider
    /// Process-local typed frozen values, shared across connections.
    private let store: RuntimeSemanticSnapshotStore

    package init(registry: RuntimeNodeRegistry, hierarchyProvider: UIKitRuntimeHierarchyProvider, store: RuntimeSemanticSnapshotStore) {
        self.registry = registry
        self.hierarchyProvider = hierarchyProvider
        self.store = store
    }

    package func capture(options: RuntimeSemanticCaptureOptions) async throws -> RuntimeHierarchySnapshotPayload {
        let context = try select(options: options)
        try validate(context)
        let collector = UIKitSemanticAccessibilityCollector(registry: registry)
        // Public AX getters may become ready asynchronously. No activation or global notification.
        // Readiness never reads AX value or Text attachments, and produces no frozen payload.
        for _ in 0..<3 {
            if collector.publicSemanticTreeIsReady(in: context.window) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
            try validate(context)
        }
        try Task.checkCancellation()
        try validate(context)
        // The safety proof is taken after the last suspension; final reads below are synchronous.
        let privacyIssue = securityIssue(in: context.window)
        let render = try hierarchyProvider.hierarchySnapshot(context: .init(scene: context.scene, windows: [context.window]), redactAccessibilityValues: privacyIssue != nil)
        let ax = try collector.capture(window: context.window, snapshotID: render.snapshotID, capturedAt: render.capturedAtUnixTime, renderRoots: render.roots, privacyIssue: privacyIssue)
        try Task.checkCancellation()
        try validate(context)
        let issues = ax.semanticCount == 0 ? ax.issues + [semanticIssue("treeUnavailable")] : ax.issues
        let semantic = try RuntimeSemanticCapture(windowID: registry.nodeID(for: context.window), source: semanticName("ios.accessibility"),
            availability: ax.semanticCount == 0 ? .unavailable : (issues.isEmpty && !ax.truncated ? .complete : .partial),
            issues: issues, visitedNodeCount: ax.visits, wasTruncated: ax.truncated, roots: ax.roots)
        let payload = RuntimeHierarchySnapshotPayload(snapshotID: render.snapshotID, capturedAtUnixTime: render.capturedAtUnixTime,
            targetIdentifier: render.targetIdentifier, orientation: render.orientation, display: render.display, viewport: render.viewport,
            roots: render.roots, relations: (render.relations ?? []) + ax.relations, extensions: render.extensions, semanticCapture: semantic)
        try store.insert(capture: payload, details: ax.details)
        return payload
    }

    package func detail(nodeID: RuntimeOpaqueIdentifier, snapshotID: RuntimeOpaqueIdentifier) async throws -> RuntimeNodeDetailPayload {
        guard UIApplication.shared.applicationState == .active else { throw failure("inspection.applicationInactive") }
        return try store.detail(nodeID: nodeID, snapshotID: snapshotID)
    }

    private func select(options: RuntimeSemanticCaptureOptions) throws -> Context {
        guard UIApplication.shared.applicationState == .active else { throw failure("inspection.applicationInactive") }
        var inventory: [RuntimeInspectionWindow] = []
        var candidates: [UIWindow] = []
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .sorted { $0.session.persistentIdentifier < $1.session.persistentIdentifier }
        for scene in scenes {
            for window in scene.windows {
                guard inventory.count < 64 else { throw failure("inspection.targetUnavailable", windows: inventory) }
                let reason = exclusion(window, scene: scene)
                if reason == nil { candidates.append(window) }
                inventory.append(try RuntimeInspectionWindow(windowID: registry.nodeID(for: window),
                    sceneID: RuntimeOpaqueIdentifier(rawValue: scene.session.persistentIdentifier),
                    runtimeType: .init(name: String(reflecting: type(of: window)), ancestors: []),
                    bounds: validBounds(window.bounds) ? runtimeRect(window.bounds, space: .local) : nil,
                    level: window.windowLevel.rawValue.isFinite ? Double(window.windowLevel.rawValue) : nil,
                    exclusionReason: reason))
            }
        }
        let window: UIWindow
        if let requested = options.windowID {
            guard let selected = candidates.first(where: { registry.nodeID(for: $0) == requested }) else {
                throw failure("inspection.targetUnavailable", windows: inventory)
            }
            window = selected
        } else {
            guard candidates.count == 1 else {
                throw failure(candidates.isEmpty ? "inspection.targetUnavailable" : "inspection.targetAmbiguous", windows: inventory)
            }
            window = candidates[0]
        }
        guard let scene = window.windowScene else { throw failure("inspection.targetUnavailable", windows: inventory) }
        return Context(window: window, scene: scene, screen: window.screen, bounds: window.bounds, frame: window.frame,
                       transform: window.transform, screenBounds: window.screen.coordinateSpace.bounds,
                       nativeBounds: window.screen.nativeBounds, logicalBounds: window.screen.bounds,
                       scale: window.screen.scale, orientation: scene.interfaceOrientation)
    }

    private func validate(_ context: Context) throws {
        guard UIApplication.shared.applicationState == .active,
              UIApplication.shared.connectedScenes.contains(context.scene),
              context.window.windowScene === context.scene,
              context.scene.windows.contains(where: { $0 === context.window }),
              context.window.screen === context.screen,
              context.scene.screen === context.screen,
              exclusion(context.window, scene: context.scene) == nil,
              context.window.bounds == context.bounds, context.window.frame == context.frame,
              context.window.transform == context.transform,
              context.screen.coordinateSpace.bounds == context.screenBounds,
              context.screen.nativeBounds == context.nativeBounds, context.screen.bounds == context.logicalBounds,
              context.screen.scale == context.scale, context.scene.interfaceOrientation == context.orientation else {
            throw failure("inspection.contextChanged")
        }
    }

    private func exclusion(_ window: UIWindow, scene: UIWindowScene) -> RuntimeNamespacedIdentifier? {
        if scene.activationState != .foregroundActive { return semanticName("inspection.applicationInactive") }
        if window.isHidden || !window.alpha.isFinite || window.alpha <= 0 { return semanticName("inspection.windowNotVisible") }
        if !validBounds(window.bounds) || !validBounds(window.frame) || !validBounds(window.screen.coordinateSpace.bounds) ||
            !validBounds(window.screen.bounds) || !validBounds(window.screen.nativeBounds) ||
            !window.screen.scale.isFinite || window.screen.scale <= 0 || !window.windowLevel.rawValue.isFinite {
            return semanticName("inspection.invalidGeometry")
        }
        if window.windowLevel != .normal { return semanticName("inspection.nonNormalWindow") }
        return nil
    }

    private func securityIssue(in window: UIWindow) -> RuntimeInspectionIssue? {
        var budget = UIKitSemanticTraversalBudget(maxDepth: 32, maxVisits: 2_000)
        var pending: [(view: UIView, depth: Int)] = [(window, 0)]
        var secure = false
        while let entry = pending.popLast() {
            guard budget.consume(depth: entry.depth) else { continue }
            if (entry.view as? UITextField)?.isSecureTextEntry == true ||
                (entry.view as? UITextView)?.isSecureTextEntry == true ||
                (entry.view as? UISearchBar)?.searchTextField.isSecureTextEntry == true { secure = true }
            if entry.view.subviews.count > 100 { budget.markTruncated() }
            for child in entry.view.subviews.prefix(100).reversed() {
                guard pending.count + budget.visits < 2_000 else { budget.markTruncated(); break }
                pending.append((child, entry.depth + 1))
            }
            if budget.visits == 2_000 {
                if !pending.isEmpty { budget.markTruncated() }
                break
            }
        }
        return secure ? semanticIssue("secureInputContext") : (budget.truncated ? semanticIssue("securityScanIncomplete") : nil)
    }

    private func validBounds(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }

    private func failure(_ code: String, windows: [RuntimeInspectionWindow]? = nil) -> RuntimeError {
        RuntimeError(code: try! .init(rawValue: code), message: "语义检查目标或上下文不可用。", recoverySuggestion: nil,
                     extensions: windows.flatMap { try? RuntimeExtensionMap(inspectionTargets: $0) })
    }
}
#endif
