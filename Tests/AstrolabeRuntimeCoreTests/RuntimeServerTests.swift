//
//  RuntimeServerTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeRuntimeCore
import AstrolabeProtocol
import Foundation
import Network
import XCTest

final class RuntimeServerTests: XCTestCase {
    func testServerAcceptsProtocolV2RequestFixtures() async throws {
        let expectedAppInfo = Self.makeAppInfo(displayName: "Fixture Demo")
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try await Self.makeServer(
            transport: transport,
            hierarchyProvider: await MainActor.run {
                StubHierarchyProvider(snapshot: Self.makeHierarchySnapshot())
            },
            appInfo: expectedAppInfo,
            requestTimeoutNanoseconds: 1_000_000_000
        )
        try await server.start()

        do {
            let client = try await Self.connectedClient(transport: transport)
            let handshakeResponse: RuntimeResponse<RuntimeHandshakePayload> = try await client
                .requestFixture(named: "handshake-request")
            guard case let .success(handshake) = handshakeResponse.outcome else {
                return XCTFail("Expected fixture handshake success.")
            }
            XCTAssertEqual(handshakeResponse.method, .handshake)
            XCTAssertEqual(handshake.negotiatedProtocolVersion, .v2)

            let appInfoResponse: RuntimeResponse<RuntimeApplicationInfoPayload> = try await client
                .requestFixture(named: "application-info-request")
            guard case let .success(appInfo) = appInfoResponse.outcome else {
                return XCTFail("Expected fixture application-info success.")
            }
            XCTAssertEqual(appInfoResponse.method, .applicationInfo)
            XCTAssertEqual(appInfo, expectedAppInfo)

            await client.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testAttributePatchPersistsAcrossConnectionsUntilServerStops() async throws {
        let appInfoProvider = await MainActor.run {
            StubAppInfoProvider(appInfo: Self.makeAppInfo())
        }
        let hierarchyProvider = await MainActor.run {
            StubHierarchyProvider(snapshot: Self.makeHierarchySnapshot())
        }
        let nodeDetailProvider = await MainActor.run {
            StubNodeDetailProvider(detail: Self.makeNodeDetail())
        }
        let patchProvider = await MainActor.run {
            StubAttributePatchProvider()
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try RuntimeServer(
            configuration: RuntimeServerConfiguration(runtimeVersion: "0.1.0"),
            transport: transport,
            inspectionServicesFactory: {
                RuntimeInspectionServices(
                    appInfoProvider: appInfoProvider,
                    hierarchyProvider: hierarchyProvider,
                    nodeDetailProvider: nodeDetailProvider,
                    attributePatchProvider: patchProvider
                )
            },
            inspectionSessionCleanup: {
                _ = try? await patchProvider.clearAttributePatches()
            }
        )
        try await server.start()

        do {
            let firstClient = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: firstClient)
            let applyResponse: RuntimeResponse<RuntimeAttributePatch> = try await firstClient.request(
                RuntimeRequest(
                    method: .applyAttributePatch,
                    parameters: RuntimeApplyAttributePatchParameters(
                        nodeID: Self.makeNodeDetail().nodeID,
                        attributeIdentifier: .testFontSize,
                        value: .number(18)
                    )
                )
            )
            guard case let .success(appliedPatch) = applyResponse.outcome else {
                return XCTFail("Expected attribute patch success.")
            }
            await firstClient.close()

            let secondClient = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: secondClient)
            let listResponse: RuntimeResponse<RuntimeAttributePatchListPayload> = try await secondClient.request(
                RuntimeRequest(
                    method: .listAttributePatches,
                    parameters: RuntimeListAttributePatchesParameters()
                )
            )
            guard case let .success(list) = listResponse.outcome else {
                return XCTFail("Expected attribute patch list success.")
            }
            XCTAssertEqual(list.patches, [appliedPatch])
            await secondClient.close()

            await server.stop()
            let remainingPatches = await patchProvider.activeAttributePatches()
            XCTAssertTrue(remainingPatches.patches.isEmpty)
        } catch {
            await server.stop()
            throw error
        }
    }

    func testLocalTCPServerHandlesHandshakeAppInfoAndErrors() async throws {
        let expectedAppInfo = Self.makeAppInfo()
        let provider = await MainActor.run {
            StubAppInfoProvider(appInfo: expectedAppInfo)
        }
        let expectedHierarchy = Self.makeHierarchySnapshot()
        let hierarchyProvider = await MainActor.run {
            StubHierarchyProvider(snapshot: expectedHierarchy)
        }
        let expectedNodeDetail = Self.makeNodeDetail()
        let nodeDetailProvider = await MainActor.run {
            StubNodeDetailProvider(detail: expectedNodeDetail)
        }
        let attributePatchProvider = await MainActor.run {
            StubAttributePatchProvider()
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try RuntimeServer(
            configuration: RuntimeServerConfiguration(runtimeVersion: "0.1.0"),
            transport: transport,
            inspectionServicesFactory: {
                RuntimeInspectionServices(
                    appInfoProvider: provider,
                    hierarchyProvider: hierarchyProvider,
                    nodeDetailProvider: nodeDetailProvider,
                    attributePatchProvider: attributePatchProvider
                )
            }
        )
        try await server.start()

        do {
            guard let port = await transport.boundEndpoint?.port else {
                throw TestClientError.missingBoundPort
            }
            let client = try TestTCPClient(port: port)
            await client.start()

            try await Self.withTimeout {
                let preHandshakeResponse: RuntimeResponse<RuntimeJSONValue> = try await client.request(
                    RuntimeRequest(
                        method: .applicationInfo,
                        parameters: RuntimeApplicationInfoParameters()
                    )
                )
                guard case let .failure(preHandshakeError) = preHandshakeResponse.outcome else {
                    return XCTFail("Expected handshake-required failure.")
                }
                XCTAssertEqual(preHandshakeError.code, .handshakeRequired)

                let handshakeResponse: RuntimeResponse<RuntimeHandshakePayload> = try await client.request(
                    RuntimeRequest(
                        method: .handshake,
                        parameters: RuntimeHandshakeParameters(
                            client: RuntimeClientDescriptor(
                                name: "AstrolabeTests",
                                version: "0.1.0"
                            ),
                            supportedProtocolRange: .v2
                        )
                    )
                )
                guard case let .success(handshake) = handshakeResponse.outcome else {
                    return XCTFail("Expected handshake success.")
                }
                XCTAssertEqual(handshake.runtime.version, "0.1.0")
                XCTAssertEqual(handshake.negotiatedProtocolVersion, .v2)
                XCTAssertEqual(
                    handshake.capabilities,
                    [
                        .applicationInfo,
                        .attributePatchDiscovery,
                        .attributePatching,
                        .hierarchySnapshot,
                        .nodeDetail,
                        .requestCancellation
                    ]
                )

                let appInfoResponse: RuntimeResponse<RuntimeApplicationInfoPayload> = try await client.request(
                    RuntimeRequest(
                        method: .applicationInfo,
                        parameters: RuntimeApplicationInfoParameters()
                    )
                )
                guard case let .success(appInfo) = appInfoResponse.outcome else {
                    return XCTFail("Expected AppInfo success.")
                }
                XCTAssertEqual(appInfo, expectedAppInfo)

                let hierarchyResponse: RuntimeResponse<RuntimeHierarchySnapshotPayload> = try await client.request(
                    RuntimeRequest(
                        method: .hierarchySnapshot,
                        parameters: RuntimeHierarchySnapshotParameters()
                    )
                )
                guard case let .success(hierarchy) = hierarchyResponse.outcome else {
                    return XCTFail("Expected hierarchy success.")
                }
                XCTAssertEqual(hierarchy, expectedHierarchy)

                let nodeDetailResponse: RuntimeResponse<RuntimeNodeDetailPayload> = try await client.request(
                    RuntimeRequest(
                        method: .nodeDetail,
                        parameters: RuntimeNodeDetailParameters(
                            nodeID: expectedNodeDetail.nodeID
                        )
                    )
                )
                guard case let .success(nodeDetail) = nodeDetailResponse.outcome else {
                    return XCTFail("Expected node-detail success.")
                }
                XCTAssertEqual(nodeDetail, expectedNodeDetail)

                let patchableAttributesResponse: RuntimeResponse<RuntimePatchableAttributesPayload> = try await client.request(
                    RuntimeRequest(
                        method: .patchableAttributes,
                        parameters: RuntimePatchableAttributesParameters()
                    )
                )
                guard case let .success(patchableAttributes) = patchableAttributesResponse.outcome else {
                    return XCTFail("Expected patchable-attribute catalog success.")
                }
                let expectedPatchableAttributes = await attributePatchProvider
                    .patchableAttributes()
                XCTAssertEqual(
                    patchableAttributes,
                    expectedPatchableAttributes
                )

                let applyPatchResponse: RuntimeResponse<RuntimeAttributePatch> = try await client.request(
                    RuntimeRequest(
                        method: .applyAttributePatch,
                        parameters: RuntimeApplyAttributePatchParameters(
                            nodeID: expectedNodeDetail.nodeID,
                            attributeIdentifier: .testFontSize,
                            value: .number(16)
                        )
                    )
                )
                guard case let .success(patch) = applyPatchResponse.outcome else {
                    return XCTFail("Expected attribute-patch success.")
                }
                XCTAssertEqual(patch.requestedValue, .number(16))

                let listPatchResponse: RuntimeResponse<RuntimeAttributePatchListPayload> = try await client.request(
                    RuntimeRequest(
                        method: .listAttributePatches,
                        parameters: RuntimeListAttributePatchesParameters()
                    )
                )
                guard case let .success(patchList) = listPatchResponse.outcome else {
                    return XCTFail("Expected attribute-patch list success.")
                }
                XCTAssertEqual(patchList.patches, [patch])

                let revertPatchResponse: RuntimeResponse<RuntimeRevertAttributePatchPayload> = try await client.request(
                    RuntimeRequest(
                        method: .revertAttributePatch,
                        parameters: RuntimeRevertAttributePatchParameters(
                            patchID: patch.patchID
                        )
                    )
                )
                guard case let .success(revert) = revertPatchResponse.outcome else {
                    return XCTFail("Expected attribute-patch revert success.")
                }
                XCTAssertEqual(revert.revertedPatchID, patch.patchID)
                XCTAssertEqual(revert.remainingPatchCount, 0)

                let unsupportedMethodResponse: RuntimeResponse<RuntimeJSONValue> = try await client.request(
                    RuntimeRequest(
                        method: try RuntimeMethod(rawValue: "futureMethod"),
                        parameters: UnboundEmptyParameters()
                    )
                )
                guard case let .failure(methodError) = unsupportedMethodResponse.outcome else {
                    return XCTFail("Expected unsupported method failure.")
                }
                XCTAssertEqual(methodError.code, .unsupportedMethod)
                XCTAssertEqual(unsupportedMethodResponse.protocolVersion, .v2)
            }

            await client.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testServerCreatesInspectionServicesForEachConnection() async throws {
        let probe = await MainActor.run {
            InspectionServicesFactoryProbe(
                appInfo: Self.makeAppInfo(),
                hierarchy: Self.makeHierarchySnapshot(),
                nodeDetail: Self.makeNodeDetail()
            )
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try RuntimeServer(
            configuration: RuntimeServerConfiguration(runtimeVersion: "0.1.0"),
            transport: transport,
            inspectionServicesFactory: {
                probe.makeServices()
            }
        )
        try await server.start()

        do {
            let firstClient = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: firstClient)
            let secondClient = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: secondClient)

            let creationCount = await MainActor.run {
                probe.creationCount
            }
            XCTAssertEqual(creationCount, 2)

            await firstClient.close()
            await secondClient.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testServerNegotiatesProtocolV2() async throws {
        let hierarchyProvider = await MainActor.run {
            StubHierarchyProvider(snapshot: Self.makeHierarchySnapshot())
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try await Self.makeServer(
            transport: transport,
            hierarchyProvider: hierarchyProvider,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        try await server.start()

        do {
            let client = try await Self.connectedClient(transport: transport)
            let response: RuntimeResponse<RuntimeHandshakePayload> =
                try await client.request(
                    RuntimeRequest(
                        method: .handshake,
                        parameters: RuntimeHandshakeParameters(
                            client: RuntimeClientDescriptor(
                                name: "AstrolabeTests",
                                version: "2.0.0"
                            ),
                            supportedProtocolRange: .v2
                        )
                    )
                )
            guard case let .success(payload) = response.outcome else {
                return XCTFail("Expected handshake success.")
            }
            XCTAssertEqual(payload.negotiatedProtocolVersion, .v2)
            XCTAssertEqual(response.method, .handshake)

            await client.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testServerAcceptsRequestsAfterRestart() async throws {
        let hierarchyProvider = await MainActor.run {
            StubHierarchyProvider(snapshot: Self.makeHierarchySnapshot())
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try await Self.makeServer(
            transport: transport,
            hierarchyProvider: hierarchyProvider,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        try await server.start()

        do {
            let firstClient = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: firstClient)
            await server.stop()
            await firstClient.close()

            try await server.start()
            let secondClient = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: secondClient)
            await secondClient.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testServerReturnsFrameTooLargeAndKeepsConnectionAlive() async throws {
        let hierarchyProvider = await MainActor.run {
            StubHierarchyProvider(snapshot: Self.makeHierarchySnapshot())
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try await Self.makeServer(
            transport: transport,
            hierarchyProvider: hierarchyProvider,
            appInfo: Self.makeAppInfo(
                displayName: String(repeating: "A", count: 2_048)
            ),
            maximumPayloadSize: 512,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        try await server.start()

        do {
            let client = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: client)
            let appInfoResponse: RuntimeResponse<RuntimeApplicationInfoPayload> = try await client.request(
                RuntimeRequest(
                    method: .applicationInfo,
                    parameters: RuntimeApplicationInfoParameters()
                )
            )
            guard case let .failure(error) = appInfoResponse.outcome else {
                return XCTFail("Expected oversized response failure.")
            }
            XCTAssertEqual(error.code, .frameTooLarge)

            let targetRequestID = UUID()
            let cancellationResponse: RuntimeResponse<RuntimeCancelRequestPayload> = try await client.request(
                RuntimeRequest(
                    method: .cancelRequest,
                    parameters: RuntimeCancelRequestParameters(
                        targetRequestID: targetRequestID
                    )
                )
            )
            guard case let .success(cancellation) = cancellationResponse.outcome else {
                return XCTFail("Expected connection to remain usable.")
            }
            XCTAssertEqual(cancellation.targetRequestID, targetRequestID)
            XCTAssertFalse(cancellation.cancellationAccepted)

            await client.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testOversizedHandshakeDoesNotAdvanceSessionState() async throws {
        let hierarchyProvider = await MainActor.run {
            StubHierarchyProvider(snapshot: Self.makeHierarchySnapshot())
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try await Self.makeServer(
            transport: transport,
            hierarchyProvider: hierarchyProvider,
            runtimeVersion: String(repeating: "1", count: 2_048),
            maximumPayloadSize: 512,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        try await server.start()

        do {
            let client = try await Self.connectedClient(transport: transport)
            let handshakeResponse: RuntimeResponse<RuntimeHandshakePayload> = try await client.request(
                RuntimeRequest(
                    method: .handshake,
                    parameters: RuntimeHandshakeParameters(
                        client: RuntimeClientDescriptor(
                            name: "AstrolabeTests",
                            version: "0.1.0"
                        ),
                        supportedProtocolRange: .v2
                    )
                )
            )
            guard case let .failure(handshakeError) = handshakeResponse.outcome else {
                return XCTFail("Expected oversized handshake failure.")
            }
            XCTAssertEqual(handshakeError.code, .frameTooLarge)

            let appInfoResponse: RuntimeResponse<RuntimeJSONValue> = try await client.request(
                RuntimeRequest(
                    method: .applicationInfo,
                    parameters: RuntimeApplicationInfoParameters()
                )
            )
            guard case let .failure(appInfoError) = appInfoResponse.outcome else {
                return XCTFail("Expected handshake-required failure.")
            }
            XCTAssertEqual(appInfoError.code, .handshakeRequired)

            await client.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testServerCancelsInFlightRequestFromSameConnection() async throws {
        let expectedHierarchy = Self.makeHierarchySnapshot()
        let hierarchyProvider = await MainActor.run {
            DelayedHierarchyProvider(
                snapshot: expectedHierarchy,
                delayNanoseconds: 5_000_000_000
            )
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try await Self.makeServer(
            transport: transport,
            hierarchyProvider: hierarchyProvider,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        try await server.start()

        do {
            let client = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: client)
            let hierarchyRequest = try RuntimeRequest(
                method: RuntimeMethod.hierarchySnapshot,
                parameters: RuntimeHierarchySnapshotParameters()
            )
            let cancelRequest = try RuntimeRequest(
                method: RuntimeMethod.cancelRequest,
                parameters: RuntimeCancelRequestParameters(
                    targetRequestID: hierarchyRequest.requestID
                )
            )
            try await client.sendRequest(hierarchyRequest)
            try await client.sendRequest(cancelRequest)

            var cancellationResponse: RuntimeResponse<RuntimeCancelRequestPayload>?
            var hierarchyResponse: RuntimeResponse<RuntimeHierarchySnapshotPayload>?
            for _ in 0..<2 {
                let payload = try await client.receiveResponsePayload()
                let header = try RuntimeMessageCodec().decode(
                    RuntimeResponseHeader.self,
                    from: payload
                )
                if header.requestID == cancelRequest.requestID {
                    cancellationResponse = try RuntimeMessageCodec().decode(
                        RuntimeResponse<RuntimeCancelRequestPayload>.self,
                        from: payload
                    )
                } else if header.requestID == hierarchyRequest.requestID {
                    hierarchyResponse = try RuntimeMessageCodec().decode(
                        RuntimeResponse<RuntimeHierarchySnapshotPayload>.self,
                        from: payload
                    )
                }
            }

            guard case let .success(cancellation)? = cancellationResponse?.outcome else {
                return XCTFail("Expected cancellation acknowledgement.")
            }
            XCTAssertEqual(cancellation.targetRequestID, hierarchyRequest.requestID)
            XCTAssertTrue(cancellation.cancellationAccepted)
            guard case let .failure(error)? = hierarchyResponse?.outcome else {
                return XCTFail("Expected cancelled request failure.")
            }
            XCTAssertEqual(error.code, .requestCancelled)

            let unknownTargetID = UUID()
            let unknownCancellation: RuntimeResponse<RuntimeCancelRequestPayload> = try await client.request(
                RuntimeRequest(
                    method: .cancelRequest,
                    parameters: RuntimeCancelRequestParameters(
                        targetRequestID: unknownTargetID
                    )
                )
            )
            guard case let .success(acknowledgement) = unknownCancellation.outcome else {
                return XCTFail("Expected unknown-target cancellation acknowledgement.")
            }
            XCTAssertEqual(acknowledgement.targetRequestID, unknownTargetID)
            XCTAssertFalse(acknowledgement.cancellationAccepted)

            await client.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testServerTimesOutSlowRequest() async throws {
        let hierarchyProvider = await MainActor.run {
            DelayedHierarchyProvider(
                snapshot: Self.makeHierarchySnapshot(),
                delayNanoseconds: 5_000_000_000
            )
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try await Self.makeServer(
            transport: transport,
            hierarchyProvider: hierarchyProvider,
            requestTimeoutNanoseconds: 20_000_000
        )
        try await server.start()

        do {
            let client = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: client)
            let response: RuntimeResponse<RuntimeHierarchySnapshotPayload> = try await client.request(
                RuntimeRequest(
                    method: .hierarchySnapshot,
                    parameters: RuntimeHierarchySnapshotParameters()
                )
            )
            guard case let .failure(error) = response.outcome else {
                return XCTFail("Expected request timeout failure.")
            }
            XCTAssertEqual(error.code, .requestTimedOut)

            await client.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testServerRejectsRequestsAboveConnectionLimit() async throws {
        let hierarchyProvider = await MainActor.run {
            DelayedHierarchyProvider(
                snapshot: Self.makeHierarchySnapshot(),
                delayNanoseconds: 5_000_000_000
            )
        }
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)
        let server = try await Self.makeServer(
            transport: transport,
            hierarchyProvider: hierarchyProvider,
            requestTimeoutNanoseconds: 10_000_000_000,
            maximumConcurrentRequests: 1
        )
        try await server.start()

        do {
            let client = try await Self.connectedClient(transport: transport)
            try await Self.performHandshake(client: client)
            let firstRequest = try RuntimeRequest(
                method: RuntimeMethod.hierarchySnapshot,
                parameters: RuntimeHierarchySnapshotParameters()
            )
            let secondRequest = try RuntimeRequest(
                method: RuntimeMethod.hierarchySnapshot,
                parameters: RuntimeHierarchySnapshotParameters()
            )
            try await client.sendRequest(firstRequest)
            try await client.sendRequest(secondRequest)

            let payload = try await client.receiveResponsePayload()
            let response = try RuntimeMessageCodec().decode(
                RuntimeResponse<RuntimeJSONValue>.self,
                from: payload
            )
            XCTAssertEqual(response.requestID, secondRequest.requestID)
            guard case let .failure(error) = response.outcome else {
                return XCTFail("Expected request-limit failure.")
            }
            XCTAssertEqual(error.code, .tooManyRequests)

            await client.close()
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testServerRejectsZeroRequestTimeout() async throws {
        let hierarchyProvider = await MainActor.run {
            StubHierarchyProvider(snapshot: Self.makeHierarchySnapshot())
        }
        do {
            _ = try await Self.makeServer(
                transport: LocalTCPRuntimeTransport(portSelection: .ephemeral),
                hierarchyProvider: hierarchyProvider,
                requestTimeoutNanoseconds: 0
            )
            XCTFail("Expected invalid timeout configuration.")
        } catch {
            XCTAssertEqual(
                error as? RuntimeServerError,
                .invalidRequestTimeout
            )
        }
    }

    func testServerRejectsProtocolRangeBeyondCurrentWireContract() async throws {
        let unsupportedRange = try RuntimeProtocolRange(
            minimum: .v2,
            maximum: RuntimeProtocolVersion(major: 2, minor: 1)
        )
        let transport = LocalTCPRuntimeTransport(portSelection: .ephemeral)

        do {
            _ = try RuntimeServer(
                configuration: RuntimeServerConfiguration(
                    runtimeVersion: "0.1.0",
                    supportedProtocolRange: unsupportedRange
                ),
                transport: transport,
                inspectionServicesFactory: {
                    preconditionFailure("An invalid protocol range must not create inspection services")
                }
            )
            XCTFail("Runtime must not declare a Wire Protocol version that is not implemented")
        } catch {
            XCTAssertEqual(
                error as? RuntimeServerError,
                .unsupportedProtocolRange
            )
        }
    }

    func testServerRejectsZeroConcurrentRequestLimit() async throws {
        let hierarchyProvider = await MainActor.run {
            StubHierarchyProvider(snapshot: Self.makeHierarchySnapshot())
        }
        do {
            _ = try await Self.makeServer(
                transport: LocalTCPRuntimeTransport(portSelection: .ephemeral),
                hierarchyProvider: hierarchyProvider,
                requestTimeoutNanoseconds: 10_000_000_000,
                maximumConcurrentRequests: 0
            )
            XCTFail("Expected invalid concurrent-request configuration.")
        } catch {
            XCTAssertEqual(
                error as? RuntimeServerError,
                .invalidMaximumConcurrentRequests
            )
        }
    }

    private static func makeServer(
        transport: LocalTCPRuntimeTransport,
        hierarchyProvider: any RuntimeHierarchyProviding,
        runtimeVersion: String = "0.1.0",
        supportedProtocolRange: RuntimeProtocolRange = .v2,
        appInfo: RuntimeApplicationInfoPayload? = nil,
        maximumPayloadSize: Int = RuntimeFrameCodec.defaultMaximumPayloadSize,
        requestTimeoutNanoseconds: UInt64,
        maximumConcurrentRequests: Int = 8
    ) async throws -> RuntimeServer {
        let appInfoProvider = await MainActor.run {
            StubAppInfoProvider(appInfo: appInfo ?? Self.makeAppInfo())
        }
        let nodeDetailProvider = await MainActor.run {
            StubNodeDetailProvider(detail: Self.makeNodeDetail())
        }
        return try RuntimeServer(
            configuration: RuntimeServerConfiguration(
                runtimeVersion: runtimeVersion,
                supportedProtocolRange: supportedProtocolRange,
                maximumPayloadSize: maximumPayloadSize,
                requestTimeoutNanoseconds: requestTimeoutNanoseconds,
                maximumConcurrentRequests: maximumConcurrentRequests
            ),
            transport: transport,
            inspectionServicesFactory: {
                RuntimeInspectionServices(
                    appInfoProvider: appInfoProvider,
                    hierarchyProvider: hierarchyProvider,
                    nodeDetailProvider: nodeDetailProvider
                )
            }
        )
    }

    private static func connectedClient(
        transport: LocalTCPRuntimeTransport
    ) async throws -> TestTCPClient {
        guard let port = await transport.boundEndpoint?.port else {
            throw TestClientError.missingBoundPort
        }
        let client = try TestTCPClient(port: port)
        await client.start()
        return client
    }

    private static func performHandshake(client: TestTCPClient) async throws {
        let response: RuntimeResponse<RuntimeHandshakePayload> = try await client.request(
            RuntimeRequest(
                method: .handshake,
                parameters: RuntimeHandshakeParameters(
                    client: RuntimeClientDescriptor(
                        name: "AstrolabeTests",
                        version: "0.1.0"
                    ),
                    supportedProtocolRange: .v2
                )
            )
        )
        guard case .success = response.outcome else {
            throw TestClientError.handshakeFailed
        }
    }

    private static func withTimeout<Value: Sendable>(
        nanoseconds: UInt64 = 5_000_000_000,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw TestClientError.timeout
            }

            guard let result = try await group.next() else {
                throw TestClientError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private static func makeAppInfo(
        displayName: String = "Demo"
    ) -> RuntimeApplicationInfoPayload {
        RuntimeApplicationInfoPayload(
            application: RuntimeApplication(
                identifier: "com.example.demo",
                displayName: displayName,
                version: "1.0.0",
                buildVersion: "1"
            ),
            target: RuntimeTarget(
                identifier: opaqueIdentifier("runtime-instance"),
                processIdentifier: "42",
                kind: "application",
                primary: true
            ),
            environment: RuntimeEnvironment(
                platform: "ios",
                operatingSystemVersion: "26.0",
                deviceCategory: "phone",
                deviceName: "iPhone",
                deviceModel: "iPhone17,1",
                virtualDevice: true,
                locale: "zh_CN",
                layoutDirection: .leftToRight,
                display: displayInfo(),
                extensions: nil
            ),
            extensions: nil
        )
    }

    private static func makeHierarchySnapshot() -> RuntimeHierarchySnapshotPayload {
        RuntimeHierarchySnapshotPayload(
            snapshotID: opaqueIdentifier("snapshot"),
            capturedAtUnixTime: 1_783_683_200,
            targetIdentifier: opaqueIdentifier("runtime-instance"),
            orientation: "portrait",
            display: displayInfo(),
            viewport: RuntimeCoordinateRect(
                x: 0,
                y: 0,
                width: 393,
                height: 852,
                coordinateSpace: .screen,
                unit: .logical
            ),
            roots: [],
            extensions: nil
        )
    }

    private static func makeNodeDetail() -> RuntimeNodeDetailPayload {
        RuntimeNodeDetailPayload(
            nodeID: opaqueIdentifier("1"),
            sections: [
                RuntimeAttributeSection(
                    category: attributeCategory("test.view"),
                    attributes: [
                        RuntimeAttribute(
                            identifier: attributeIdentifier("test.hidden"),
                            value: .boolean(false)
                        )
                    ]
                )
            ],
            extensions: nil
        )
    }

    private static func displayInfo() -> RuntimeDisplayInfo {
        RuntimeDisplayInfo(
            logicalSize: RuntimeMeasuredSize(
                width: 393,
                height: 852,
                unit: .logical
            ),
            pixelSize: RuntimeMeasuredSize(
                width: 1_179,
                height: 2_556,
                unit: .pixel
            ),
            logicalToPixelScale: RuntimeScale(x: 3, y: 3),
            maximumRefreshRate: 120
        )
    }
}

@MainActor
private final class InspectionServicesFactoryProbe {
    private(set) var creationCount = 0
    private let appInfo: RuntimeApplicationInfoPayload
    private let hierarchy: RuntimeHierarchySnapshotPayload
    private let nodeDetail: RuntimeNodeDetailPayload

    init(
        appInfo: RuntimeApplicationInfoPayload,
        hierarchy: RuntimeHierarchySnapshotPayload,
        nodeDetail: RuntimeNodeDetailPayload
    ) {
        self.appInfo = appInfo
        self.hierarchy = hierarchy
        self.nodeDetail = nodeDetail
    }

    func makeServices() -> RuntimeInspectionServices {
        creationCount += 1
        return RuntimeInspectionServices(
            appInfoProvider: StubAppInfoProvider(appInfo: appInfo),
            hierarchyProvider: StubHierarchyProvider(snapshot: hierarchy),
            nodeDetailProvider: StubNodeDetailProvider(detail: nodeDetail)
        )
    }
}

@MainActor
private final class StubAppInfoProvider: RuntimeAppInfoProviding {
    private let value: RuntimeApplicationInfoPayload

    init(appInfo: RuntimeApplicationInfoPayload) {
        value = appInfo
    }

    func appInfo(
        runtime: RuntimeDescriptor
    ) async throws -> RuntimeApplicationInfoPayload {
        value
    }
}

@MainActor
private final class StubHierarchyProvider: RuntimeHierarchyProviding {
    private let snapshot: RuntimeHierarchySnapshotPayload

    init(snapshot: RuntimeHierarchySnapshotPayload) {
        self.snapshot = snapshot
    }

    func hierarchySnapshot() async throws -> RuntimeHierarchySnapshotPayload {
        snapshot
    }
}

@MainActor
private final class DelayedHierarchyProvider: RuntimeHierarchyProviding {
    private let snapshot: RuntimeHierarchySnapshotPayload
    private let delayNanoseconds: UInt64

    init(snapshot: RuntimeHierarchySnapshotPayload, delayNanoseconds: UInt64) {
        self.snapshot = snapshot
        self.delayNanoseconds = delayNanoseconds
    }

    func hierarchySnapshot() async throws -> RuntimeHierarchySnapshotPayload {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return snapshot
    }
}

@MainActor
private final class StubNodeDetailProvider: RuntimeNodeDetailProviding {
    private let detail: RuntimeNodeDetailPayload

    init(detail: RuntimeNodeDetailPayload) {
        self.detail = detail
    }

    func nodeDetail(for nodeID: RuntimeOpaqueIdentifier) async throws -> RuntimeNodeDetailPayload {
        detail
    }
}

@MainActor
private final class StubAttributePatchProvider: RuntimeAttributePatchProviding {
    /// Active patch returned by the test provider.
    private var patch: RuntimeAttributePatch?

    func patchableAttributes() async -> RuntimePatchableAttributesPayload {
        RuntimePatchableAttributesPayload(
            attributes: [
                patchableTestAttribute(
                    attributePattern: "test.fontSize",
                    valueConstraints: RuntimePatchValueConstraints(
                        minimum: 0,
                        maximum: nil,
                        minimumExclusive: true,
                        maximumExclusive: false,
                        acceptedFormats: [],
                        allowedValues: []
                    )
                )
            ]
        )
    }

    func applyAttributePatch(
        _ request: RuntimeApplyAttributePatchParameters
    ) async throws -> RuntimeAttributePatch {
        let patch = RuntimeAttributePatch(
            patchID: opaqueIdentifier(UUID().uuidString),
            nodeID: request.nodeID,
            attributeIdentifier: request.attributeIdentifier,
            originalValue: .number(14),
            requestedValue: request.value,
            actualValue: request.value,
            appliedAtUnixTime: Date().timeIntervalSince1970
        )
        self.patch = patch
        return patch
    }

    func activeAttributePatches() async -> RuntimeAttributePatchListPayload {
        RuntimeAttributePatchListPayload(patches: patch.map { [$0] } ?? [])
    }

    func revertAttributePatch(
        _ request: RuntimeRevertAttributePatchParameters
    ) async throws -> RuntimeRevertAttributePatchPayload {
        guard patch?.patchID == request.patchID else {
            throw RuntimeError(
                code: .patchNotFound,
                message: "Test patch not found",
                recoverySuggestion: nil
            )
        }
        patch = nil
        return RuntimeRevertAttributePatchPayload(
            revertedPatchID: request.patchID,
            restoredValue: .number(14),
            remainingPatchCount: 0
        )
    }

    func clearAttributePatches() async throws -> RuntimeClearAttributePatchesPayload {
        let patchIDs = patch.map { [$0.patchID] } ?? []
        patch = nil
        return RuntimeClearAttributePatchesPayload(
            revertedPatchIDs: patchIDs,
            remainingPatchCount: 0
        )
    }

}

private actor TestTCPClient {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.astrolabe.runtime.tests.client")
    private let messageCodec = RuntimeMessageCodec()
    private let frameCodec = RuntimeFrameCodec()
    private var frameDecoder = RuntimeFrameCodec().makeStreamDecoder()
    private var pendingPayloads = [Data]()

    init(port: UInt16) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw TestClientError.invalidPort(port)
        }
        connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: endpointPort,
            using: .tcp
        )
    }

    func start() {
        connection.start(queue: queue)
    }

    func request<Parameters, Payload>(
        _ request: RuntimeRequest<Parameters>
    ) async throws -> RuntimeResponse<Payload>
    where Parameters: Codable & Equatable & Sendable,
          Payload: Codable & Equatable & Sendable {
        try await sendRequest(request)
        let responsePayload = try await receiveResponsePayload()
        return try messageCodec.decode(
            RuntimeResponse<Payload>.self,
            from: responsePayload
        )
    }

    func requestFixture<Payload>(
        named name: String
    ) async throws -> RuntimeResponse<Payload>
    where Payload: Codable & Equatable & Sendable {
        guard let fixtureURL = Bundle.module.url(
            forResource: name,
            withExtension: "json"
        ) else {
            throw TestClientError.missingFixture(name)
        }
        let payload = try Data(contentsOf: fixtureURL)
        let frame = try frameCodec.encode(payload: payload)
        try await send(frame)
        let responsePayload = try await receiveResponsePayload()
        return try messageCodec.decode(
            RuntimeResponse<Payload>.self,
            from: responsePayload
        )
    }

    func sendRequest<Parameters>(
        _ request: RuntimeRequest<Parameters>
    ) async throws where Parameters: Codable & Equatable & Sendable {
        let payload = try messageCodec.encode(request)
        let frame = try frameCodec.encode(payload: payload)
        try await send(frame)
    }

    func receiveResponsePayload() async throws -> Data {
        try await receivePayload()
    }

    func close() {
        connection.cancel()
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receivePayload() async throws -> Data {
        if !pendingPayloads.isEmpty {
            return pendingPayloads.removeFirst()
        }

        while true {
            let chunk = try await receiveChunk()
            pendingPayloads.append(contentsOf: try frameDecoder.append(chunk))
            if !pendingPayloads.isEmpty {
                return pendingPayloads.removeFirst()
            }
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: 64 * 1024
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: TestClientError.connectionClosed)
                } else {
                    continuation.resume(throwing: TestClientError.emptyRead)
                }
            }
        }
    }
}

private struct UnboundEmptyParameters: Codable, Equatable, Sendable {}

private extension RuntimeAttributeIdentifier {
    static let testFontSize = attributeIdentifier("test.fontSize")
}

private func opaqueIdentifier(_ rawValue: String) -> RuntimeOpaqueIdentifier {
    do {
        return try RuntimeOpaqueIdentifier(rawValue: rawValue)
    } catch {
        preconditionFailure("Invalid opaque identifier in test: \(rawValue)")
    }
}

private func attributeIdentifier(
    _ rawValue: String
) -> RuntimeAttributeIdentifier {
    do {
        return try RuntimeAttributeIdentifier(rawValue: rawValue)
    } catch {
        preconditionFailure("Invalid attribute identifier in test: \(rawValue)")
    }
}

private func attributeCategory(_ rawValue: String) -> RuntimeAttributeCategory {
    do {
        return try RuntimeAttributeCategory(rawValue: rawValue)
    } catch {
        preconditionFailure("Invalid attribute category in test: \(rawValue)")
    }
}

private func patchableTestAttribute(
    attributePattern: String,
    valueConstraints: RuntimePatchValueConstraints?
) -> RuntimePatchableAttribute {
    do {
        return try RuntimePatchableAttribute(
            attributePattern: attributePattern,
            valueType: RuntimePatchValueType(rawValue: "number"),
            targetRoles: ["value"],
            valueConstraints: valueConstraints,
            extensions: RuntimeExtensionMap()
        )
    } catch {
        preconditionFailure("Invalid patch catalog entry in test: \(attributePattern)")
    }
}

private enum TestClientError: Error {
    case missingBoundPort
    case invalidPort(UInt16)
    case connectionClosed
    case emptyRead
    case timeout
    case handshakeFailed
    case missingFixture(String)
}
