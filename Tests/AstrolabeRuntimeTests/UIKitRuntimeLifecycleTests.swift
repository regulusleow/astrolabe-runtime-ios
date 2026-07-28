//
//  UIKitRuntimeLifecycleTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
@testable import AstrolabeRuntime
import AstrolabeProtocol
import AstrolabeRuntimeCore
import XCTest

@MainActor
final class UIKitRuntimeLifecycleTests: XCTestCase {
    func testLifecycleStartsAndStopsDefaultRuntime() async throws {
        let lifecycle = try UIKitRuntimeLifecycle(
            configuration: RuntimeServerConfiguration(
                runtimeVersion: "2.1.0"
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
                runtimeVersion: "2.1.0"
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
                runtimeVersion: "2.1.0"
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

    func testLifecycleConformsToProcessLifecycle() throws {
        let lifecycle: any RuntimeProcessLifecycle =
            try UIKitRuntimeLifecycle(
            configuration: RuntimeServerConfiguration(
                runtimeVersion: "2.1.0"
            ),
            portSelection: .ephemeral,
            inspectionAuthorization: { true }
        )

        XCTAssertNotNil(lifecycle)
    }
}
#endif
