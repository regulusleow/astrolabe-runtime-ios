//
//  LocalTCPRuntimeTransportTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeRuntimeCore
import XCTest

final class LocalTCPRuntimeTransportTests: XCTestCase {
    func testTransportFallsBackWithinRangeWhenFirstPortIsOccupied() async throws {
        let occupyingTransport = LocalTCPRuntimeTransport(
            portSelection: .ephemeral
        )
        _ = try await occupyingTransport.start()
        guard let occupiedPort = await occupyingTransport.boundEndpoint?.port else {
            await occupyingTransport.stop()
            return XCTFail("Expected a usable ephemeral port.")
        }

        let fallbackUpperBound = UInt16(
            min(UInt32(occupiedPort) + 32, UInt32(UInt16.max))
        )
        guard fallbackUpperBound > occupiedPort else {
            await occupyingTransport.stop()
            throw XCTSkip("Ephemeral port leaves no fallback candidates.")
        }
        let fallbackRange = occupiedPort...fallbackUpperBound
        let fallbackTransport = LocalTCPRuntimeTransport(
            portSelection: .range(fallbackRange)
        )
        do {
            _ = try await fallbackTransport.start()
            guard let boundPort = await fallbackTransport.boundEndpoint?.port else {
                await fallbackTransport.stop()
                await occupyingTransport.stop()
                return XCTFail("Expected a fallback port.")
            }
            XCTAssertNotEqual(boundPort, occupiedPort)
            XCTAssertTrue(fallbackRange.contains(boundPort))
            await fallbackTransport.stop()
            await occupyingTransport.stop()
        } catch {
            await fallbackTransport.stop()
            await occupyingTransport.stop()
            throw error
        }
    }

    func testTransportReportsNoAvailablePort() async throws {
        let occupyingTransport = LocalTCPRuntimeTransport(
            portSelection: .ephemeral
        )
        _ = try await occupyingTransport.start()
        guard let occupiedPort = await occupyingTransport.boundEndpoint?.port else {
            await occupyingTransport.stop()
            return XCTFail("Expected an occupied port.")
        }
        let blockedTransport = LocalTCPRuntimeTransport(
            portSelection: .fixed(occupiedPort)
        )

        do {
            _ = try await blockedTransport.start()
            XCTFail("Expected the occupied port to be rejected.")
        } catch {
            XCTAssertEqual(error as? RuntimeTransportError, .noAvailablePort)
        }
        await blockedTransport.stop()
        await occupyingTransport.stop()
    }

    func testTransportRejectsZeroFixedPort() async {
        let transport = LocalTCPRuntimeTransport(
            portSelection: .fixed(0)
        )
        do {
            _ = try await transport.start()
            XCTFail("Expected invalid port selection.")
        } catch {
            XCTAssertEqual(
                error as? RuntimeTransportError,
                .invalidPortSelection
            )
        }
    }
}
