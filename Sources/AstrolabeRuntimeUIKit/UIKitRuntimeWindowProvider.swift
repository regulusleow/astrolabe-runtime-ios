//
//  UIKitRuntimeWindowProvider.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import UIKit

struct UIKitRuntimeWindowContext {
    /// Foreground scene used by the hierarchy capture.
    let scene: UIWindowScene

    /// Windows ordered as exposed by the scene.
    let windows: [UIWindow]
}

@MainActor
protocol UIKitRuntimeWindowProviding: Sendable {
    func activeWindowContext() throws -> UIKitRuntimeWindowContext
}

@MainActor
struct UIKitRuntimeWindowProvider: UIKitRuntimeWindowProviding {
    private let sceneProvider: any UIKitRuntimeSceneProviding

    init(sceneProvider: any UIKitRuntimeSceneProviding) {
        self.sceneProvider = sceneProvider
    }

    func activeWindowContext() throws -> UIKitRuntimeWindowContext {
        let scenes = sceneProvider.activeWindowScenes()
        guard let scene = scenes.first else {
            throw RuntimeError(
                code: .internalFailure,
                message: "No foreground UIWindowScene is available.",
                recoverySuggestion: nil
            )
        }
        return UIKitRuntimeWindowContext(
            scene: scene,
            windows: scenes.flatMap(\.windows)
        )
    }
}
#endif
