//
//  AutomaticRuntimeInstaller.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
import AstrolabeRuntimeCore
import OSLog

@MainActor
package final class AutomaticRuntimeInstaller {
    package static let shared = makeProduction()

    private let factsProvider: () -> RuntimeProcessFacts
    private let eligibilityPolicy: RuntimeProcessEligibilityPolicy
    private let coordinator: RuntimeProcessCoordinator

    package init(
        factsProvider: @escaping () -> RuntimeProcessFacts,
        eligibilityPolicy: RuntimeProcessEligibilityPolicy,
        coordinator: RuntimeProcessCoordinator
    ) {
        self.factsProvider = factsProvider
        self.eligibilityPolicy = eligibilityPolicy
        self.coordinator = coordinator
    }

    package func install() {
        guard eligibilityPolicy.isEligible(factsProvider()) else {
            return
        }
        coordinator.install()
    }

    private static func makeProduction() -> AutomaticRuntimeInstaller {
        let logger = Logger(
            subsystem: "com.astrolabe.runtime",
            category: "Lifecycle"
        )
        let coordinator = RuntimeProcessCoordinator(
            applicationLifecycleSource:
                UIKitRuntimeApplicationLifecycleSource(),
            lifecycleFactory: {
                try UIKitRuntimeLifecycle(
                    configuration: RuntimeServerConfiguration(
                        runtimeVersion: AstrolabeRuntimeSDK.runtimeVersion
                    )
                )
            },
            failureReporter: { error in
                logger.error(
                    "Astrolabe Runtime startup failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        )
        return AutomaticRuntimeInstaller(
            factsProvider: { .current },
            eligibilityPolicy: RuntimeProcessEligibilityPolicy(),
            coordinator: coordinator
        )
    }
}
#endif
