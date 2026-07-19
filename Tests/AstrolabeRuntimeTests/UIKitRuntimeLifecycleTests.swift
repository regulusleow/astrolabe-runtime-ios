//
//  UIKitRuntimeLifecycleTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
@testable import AstrolabeRuntime
import AstrolabeProtocol
import XCTest

@MainActor
final class UIKitRuntimeLifecycleTests: XCTestCase {
    #if DEBUG
    func testLifecycleStartsAndStopsDefaultRuntime() async throws {
        let lifecycle = try UIKitRuntimeLifecycle(
            configuration: RuntimeServerConfiguration(
                runtimeVersion: "0.1.0"
            ),
            inspectionAuthorization: { true }
        )

        let endpoint = try await lifecycle.start()
        XCTAssertEqual(endpoint.host, "127.0.0.1")
        XCTAssertTrue(
            RuntimePortDefaults.simulatorRange.contains(endpoint.port)
        )
        XCTAssertEqual(lifecycle.state, .running(endpoint))

        await lifecycle.stop()
        XCTAssertEqual(lifecycle.state, .stopped)
    }

    func testLifecycleRejectsUnauthorizedInspection() async throws {
        let lifecycle = try UIKitRuntimeLifecycle(
            configuration: RuntimeServerConfiguration(
                runtimeVersion: "0.1.0"
            ),
            portSelection: .ephemeral,
            inspectionAuthorization: { false }
        )

        do {
            _ = try await lifecycle.start()
            XCTFail("Expected inspection authorization failure.")
        } catch {
            XCTAssertEqual(
                error as? UIKitRuntimeLifecycleError,
                .inspectionNotAllowed
            )
        }
        XCTAssertEqual(lifecycle.state, .stopped)
    }

    func testLifecycleRejectsDuplicateStart() async throws {
        let lifecycle = try UIKitRuntimeLifecycle(
            configuration: RuntimeServerConfiguration(
                runtimeVersion: "0.1.0"
            ),
            portSelection: .ephemeral,
            inspectionAuthorization: { true }
        )
        _ = try await lifecycle.start()

        do {
            _ = try await lifecycle.start()
            XCTFail("Expected duplicate-start failure.")
        } catch {
            XCTAssertEqual(
                error as? UIKitRuntimeLifecycleError,
                .invalidState
            )
        }
        await lifecycle.stop()
    }
    #else
    func testLifecycleDoesNotStartInRelease() async throws {
        let lifecycle = try UIKitRuntimeLifecycle(
            configuration: RuntimeServerConfiguration(
                runtimeVersion: "0.1.0"
            ),
            portSelection: .ephemeral,
            inspectionAuthorization: { true }
        )

        do {
            _ = try await lifecycle.start()
            XCTFail("A release build must not start the Runtime")
        } catch {
            XCTAssertEqual(
                error as? UIKitRuntimeLifecycleError,
                .unavailableInCurrentBuild
            )
        }
        XCTAssertEqual(lifecycle.state, .stopped)
    }
    #endif
}
#endif
