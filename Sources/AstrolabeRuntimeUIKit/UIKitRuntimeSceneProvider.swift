//
//  UIKitRuntimeSceneProvider.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import UIKit

@MainActor
protocol UIKitRuntimeSceneProviding: Sendable {
    func activeWindowScenes() -> [UIWindowScene]
}

@MainActor
struct UIKitRuntimeSceneProvider: UIKitRuntimeSceneProviding {
    func activeWindowScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter {
                $0.activationState == .foregroundActive ||
                    $0.activationState == .foregroundInactive
            }
            .sorted { lhs, rhs in
                let lhsRank = activationRank(lhs.activationState)
                let rhsRank = activationRank(rhs.activationState)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.session.persistentIdentifier < rhs.session.persistentIdentifier
            }
    }

    private func activationRank(_ state: UIScene.ActivationState) -> Int {
        state == .foregroundActive ? 0 : 1
    }
}
#endif
