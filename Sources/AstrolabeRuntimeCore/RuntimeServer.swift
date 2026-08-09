//
//  RuntimeServer.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol
import Foundation

package actor RuntimeServer {
    private struct Feature: Sendable {
        /// Capability advertised when this feature is registered.
        let capability: RuntimeCapability

        /// Request handler implementing the feature.
        let handler: any RuntimeRequestHandling
    }

    private struct ActiveConnection {
        /// Session coordinating requests for the transport connection.
        let session: RuntimeConnectionSession

        /// Task processing framed requests for the connection.
        let task: Task<Void, Never>
    }

    private let transport: any RuntimeTransport
    private let configuration: RuntimeServerConfiguration
    private let inspectionServicesFactory: RuntimeInspectionServicesFactory
    private let inspectionSessionCleanup: @MainActor @Sendable () async -> Void
    private let frameCodec: RuntimeFrameCodec
    private let requestTimeoutNanoseconds: UInt64
    private let maximumConcurrentRequests: Int
    private var acceptTask: Task<Void, Never>?
    private var runID: UUID?
    private var activeConnections = [UUID: ActiveConnection]()

    package init(
        configuration: RuntimeServerConfiguration,
        transport: any RuntimeTransport,
        inspectionServicesFactory: @escaping RuntimeInspectionServicesFactory,
        inspectionSessionCleanup: @escaping @MainActor @Sendable () async -> Void = {}
    ) throws {
        self.transport = transport
        self.configuration = configuration
        self.inspectionServicesFactory = inspectionServicesFactory
        self.inspectionSessionCleanup = inspectionSessionCleanup
        guard configuration.supportedProtocolRange == .v2 else {
            throw RuntimeServerError.unsupportedProtocolRange
        }
        guard configuration.requestTimeoutNanoseconds > 0 else {
            throw RuntimeServerError.invalidRequestTimeout
        }
        guard configuration.maximumConcurrentRequests > 0 else {
            throw RuntimeServerError.invalidMaximumConcurrentRequests
        }
        frameCodec = try RuntimeFrameCodec(
            maximumPayloadSize: configuration.maximumPayloadSize
        )
        requestTimeoutNanoseconds = configuration.requestTimeoutNanoseconds
        maximumConcurrentRequests = configuration.maximumConcurrentRequests
    }

    package func start() async throws {
        guard acceptTask == nil else {
            throw RuntimeServerError.alreadyRunning
        }

        let connections = try await transport.start()
        let runID = UUID()
        self.runID = runID
        acceptTask = Task { [weak self] in
            do {
                for try await connection in connections {
                    guard !Task.isCancelled else {
                        break
                    }
                    await self?.accept(connection, runID: runID)
                }
                await self?.transportStopped(runID: runID)
            } catch {
                await self?.transportStopped(runID: runID)
            }
        }
    }

    package func stop() async {
        let task = acceptTask
        acceptTask = nil
        runID = nil
        task?.cancel()
        await transport.stop()
        await stopActiveConnections()
        await inspectionSessionCleanup()
    }

    private func accept(
        _ connection: any RuntimeConnection,
        runID: UUID
    ) async {
        let inspectionServices = await inspectionServicesFactory()
        guard self.runID == runID else {
            await connection.close()
            return
        }
        let router = makeRouter(inspectionServices: inspectionServices)
        let session = RuntimeConnectionSession(
            connection: connection,
            router: router,
            frameCodec: frameCodec,
            requestTimeoutNanoseconds: requestTimeoutNanoseconds,
            maximumConcurrentRequests: maximumConcurrentRequests
        )
        let task = Task { [weak self] in
            await session.run()
            await self?.connectionEnded(connection.id, runID: runID)
        }
        activeConnections[connection.id] = ActiveConnection(
            session: session,
            task: task
        )
    }

    private func stopActiveConnections() async {
        let connections = Array(activeConnections.values)
        activeConnections.removeAll()
        for activeConnection in connections {
            activeConnection.task.cancel()
            await activeConnection.session.stop()
        }
    }

    private func connectionEnded(_ connectionID: UUID, runID: UUID) {
        guard self.runID == runID else {
            return
        }
        activeConnections.removeValue(forKey: connectionID)
    }

    private func transportStopped(runID: UUID) async {
        guard self.runID == runID else {
            return
        }
        self.runID = nil
        acceptTask = nil
        await stopActiveConnections()
        await inspectionSessionCleanup()
    }

    private func makeRouter(
        inspectionServices: RuntimeInspectionServices
    ) -> RuntimeRequestRouter {
        let appInfoHandler = TypedRuntimeRequestHandler<
            RuntimeApplicationInfoParameters,
            RuntimeApplicationInfoPayload
        >(method: .applicationInfo) { [configuration] _ in
            try await inspectionServices.appInfoProvider.appInfo(
                runtime: RuntimeDescriptor(
                    identifier: configuration.runtimeIdentifier,
                    version: configuration.runtimeVersion,
                    instanceID: configuration.runtimeInstanceIdentifier
                )
            )
        }
        let hierarchyHandler = TypedRuntimeRequestHandler<
            RuntimeHierarchySnapshotParameters,
            RuntimeHierarchySnapshotPayload
        >(method: .hierarchySnapshot) { _ in
            try await inspectionServices.hierarchyProvider.hierarchySnapshot()
        }
        let nodeDetailHandler = TypedRuntimeRequestHandler<
            RuntimeNodeDetailParameters,
            RuntimeNodeDetailPayload
        >(method: .nodeDetail) { request in
            try await inspectionServices.nodeDetailProvider.nodeDetail(
                for: request.parameters.nodeID
            )
        }
        var features = [
            Feature(capability: .applicationInfo, handler: appInfoHandler),
            Feature(capability: .hierarchySnapshot, handler: hierarchyHandler),
            Feature(capability: .nodeDetail, handler: nodeDetailHandler),
            Feature(
                capability: .requestCancellation,
                handler: ControlRuntimeRequestHandler(method: .cancelRequest)
            )
        ]
        if let patchProvider = inspectionServices.attributePatchProvider {
            let patchableAttributesHandler = TypedRuntimeRequestHandler<
                RuntimePatchableAttributesParameters,
                RuntimePatchableAttributesPayload
            >(method: .patchableAttributes) { _ in
                await patchProvider.patchableAttributes()
            }
            let applyPatchHandler = TypedRuntimeRequestHandler<
                RuntimeApplyAttributePatchParameters,
                RuntimeAttributePatch
            >(method: .applyAttributePatch) { request in
                try await patchProvider.applyAttributePatch(request.parameters)
            }
            let listPatchesHandler = TypedRuntimeRequestHandler<
                RuntimeListAttributePatchesParameters,
                RuntimeAttributePatchListPayload
            >(method: .listAttributePatches) { _ in
                await patchProvider.activeAttributePatches()
            }
            let revertPatchHandler = TypedRuntimeRequestHandler<
                RuntimeRevertAttributePatchParameters,
                RuntimeRevertAttributePatchPayload
            >(method: .revertAttributePatch) { request in
                try await patchProvider.revertAttributePatch(request.parameters)
            }
            let clearPatchesHandler = TypedRuntimeRequestHandler<
                RuntimeClearAttributePatchesParameters,
                RuntimeClearAttributePatchesPayload
            >(method: .clearAttributePatches) { _ in
                try await patchProvider.clearAttributePatches()
            }
            features.append(contentsOf: [
                Feature(
                    capability: .attributePatchDiscovery,
                    handler: patchableAttributesHandler
                ),
                Feature(capability: .attributePatching, handler: applyPatchHandler),
                Feature(capability: .attributePatching, handler: listPatchesHandler),
                Feature(capability: .attributePatching, handler: revertPatchHandler),
                Feature(capability: .attributePatching, handler: clearPatchesHandler)
            ])
        }
        let capabilities = Array(
            Set(features.map(\.capability)).union(
                inspectionServices.additionalCapabilities
            )
        ).sorted {
            $0.rawValue < $1.rawValue
        }
        let handshakeHandler = TypedRuntimeRequestHandler<
            RuntimeHandshakeParameters,
            RuntimeHandshakePayload
        >(method: .handshake) { [configuration] request in
            guard request.parameters.supportedProtocolRange.contains(
                request.protocolVersion
            ) else {
                throw RuntimeError(
                    code: .invalidParameters,
                    message: "The handshake envelope version is outside the client range.",
                    recoverySuggestion: nil
                )
            }
            guard let negotiatedVersion = configuration.supportedProtocolRange
                .highestCommonVersion(with: request.parameters.supportedProtocolRange) else {
                throw RuntimeError(
                    code: .unsupportedProtocolVersion,
                    message: "Client and runtime protocol ranges do not overlap.",
                    recoverySuggestion: nil
                )
            }

            return RuntimeHandshakePayload(
                runtime: RuntimeDescriptor(
                    identifier: configuration.runtimeIdentifier,
                    version: configuration.runtimeVersion,
                    instanceID: configuration.runtimeInstanceIdentifier
                ),
                platform: configuration.platform,
                negotiatedProtocolVersion: negotiatedVersion,
                capabilities: capabilities,
                extensions: nil
            )
        }
        return RuntimeRequestRouter(
            supportedProtocolRange: configuration.supportedProtocolRange,
            handlers: [handshakeHandler] + features.map(\.handler)
        )
    }
}

package enum RuntimeServerError: Error, Equatable, Sendable {
    case alreadyRunning
    case invalidRequestTimeout
    case invalidMaximumConcurrentRequests
    case unsupportedProtocolRange
}
