//
//  UIKitRuntimeLifecycle.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import AstrolabeRuntimeCore
import AstrolabeRuntimeUIKit
import UIKit

public enum UIKitRuntimeLifecycleState: Equatable, Sendable {
    /// Runtime has no active listener.
    case stopped

    /// Runtime is selecting and binding an endpoint.
    case starting

    /// Runtime is accepting requests at the associated endpoint.
    case running(RuntimeTransportEndpoint)

    /// Runtime is closing its listener, connections, and request tasks.
    case stopping
}

public enum UIKitRuntimeLifecycleError: Error, Equatable, Sendable {
    /// Runtime activation is compiled out for the current build configuration.
    case unavailableInCurrentBuild

    /// The App-specific inspection policy rejected activation.
    case inspectionNotAllowed

    /// The requested transition is invalid for the current lifecycle state.
    case invalidState

    /// Transport started without publishing its bound endpoint.
    case missingEndpoint

}

@MainActor
public final class UIKitRuntimeLifecycle: Sendable {
    /// Current lifecycle state for diagnostics and integration coordination.
    public private(set) var state: UIKitRuntimeLifecycleState = .stopped

    private let transport: LocalTCPRuntimeTransport
    private let server: RuntimeServer
    private let inspectionAuthorization: @MainActor @Sendable () -> Bool

    public init(
        configuration: RuntimeServerConfiguration,
        portSelection: LocalTCPRuntimePortSelection = .platformDefault,
        inspectionAuthorization: @escaping @MainActor @Sendable () -> Bool = {
            UIApplication.shared.applicationState != .background
        }
    ) throws {
        let transport = LocalTCPRuntimeTransport(
            portSelection: portSelection
        )
        let inspectionServicesFactory = UIKitRuntimeInspectionServicesFactory(
            targetIdentifier: configuration.runtimeInstanceIdentifier
        )
        self.transport = transport
        server = try RuntimeServer(
            configuration: configuration,
            transport: transport,
            inspectionServicesFactory: {
                inspectionServicesFactory.makeServices()
            },
            inspectionSessionCleanup: {
                await inspectionServicesFactory.clearAttributePatches()
            }
        )
        self.inspectionAuthorization = inspectionAuthorization
    }

    @discardableResult
    public func start() async throws -> RuntimeTransportEndpoint {
        guard state == .stopped else {
            throw UIKitRuntimeLifecycleError.invalidState
        }
        #if DEBUG
        guard inspectionAuthorization() else {
            throw UIKitRuntimeLifecycleError.inspectionNotAllowed
        }

        state = .starting
        do {
            try await server.start()
            guard state == .starting else {
                throw UIKitRuntimeLifecycleError.invalidState
            }
            guard let endpoint = await transport.boundEndpoint else {
                throw UIKitRuntimeLifecycleError.missingEndpoint
            }
            state = .running(endpoint)
            return endpoint
        } catch {
            await server.stop()
            state = .stopped
            throw error
        }
        #else
        throw UIKitRuntimeLifecycleError.unavailableInCurrentBuild
        #endif
    }

    public func stop() async {
        guard state != .stopped, state != .stopping else {
            return
        }
        state = .stopping
        await server.stop()
        state = .stopped
    }
}
#endif
