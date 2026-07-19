//
//  ASTRuntimeTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/11.
//

#if canImport(UIKit)
@testable import AstrolabeRuntime
import XCTest

@MainActor
final class ASTRuntimeTests: XCTestCase {
    override func tearDown() async throws {
        await stopRuntime()
        try await super.tearDown()
    }

    func testObjectiveCSelectorsAreExposed() {
        XCTAssertTrue(
            ASTRuntime.responds(
                to: NSSelectorFromString("start")
            )
        )
        XCTAssertTrue(
            ASTRuntime.responds(
                to: NSSelectorFromString("startWithCompletion:")
            )
        )
        XCTAssertTrue(ASTRuntime.responds(to: NSSelectorFromString("stop")))
        XCTAssertTrue(
            ASTRuntime.responds(
                to: NSSelectorFromString("stopWithCompletion:")
            )
        )
        XCTAssertTrue(
            ASTRuntime.responds(
                to: NSSelectorFromString("isRunningWithCompletion:")
            )
        )
    }

    func testStartAndStopRuntime() async {
        let startExpectation = expectation(description: "Runtime starts")
        var startupError: NSError?

        ASTRuntime.start { error in
            startupError = error
            startExpectation.fulfill()
        }
        await fulfillment(of: [startExpectation], timeout: 2)

        XCTAssertNil(startupError)
        var isRunning = await runtimeIsRunning()
        XCTAssertTrue(isRunning)

        await stopRuntime()
        isRunning = await runtimeIsRunning()
        XCTAssertFalse(isRunning)
    }

    func testDuplicateStartCompletesSuccessfully() async {
        let firstStart = expectation(description: "First start completes")
        ASTRuntime.start { error in
            XCTAssertNil(error)
            firstStart.fulfill()
        }
        await fulfillment(of: [firstStart], timeout: 2)

        let duplicateStart = expectation(
            description: "Duplicate start completes"
        )
        ASTRuntime.start { error in
            XCTAssertNil(error)
            duplicateStart.fulfill()
        }
        await fulfillment(of: [duplicateStart], timeout: 1)

        let isRunning = await runtimeIsRunning()
        XCTAssertTrue(isRunning)
    }

    func testStartDuringStartupReportsTransitionError() async {
        let firstStart = expectation(description: "First start completes")
        ASTRuntime.start { error in
            XCTAssertNil(error)
            firstStart.fulfill()
        }

        let duplicateStart = expectation(
            description: "Duplicate start reports an error"
        )
        ASTRuntime.start { error in
            XCTAssertNotNil(error)
            duplicateStart.fulfill()
        }

        await fulfillment(
            of: [firstStart, duplicateStart],
            timeout: 2
        )
        let isRunning = await runtimeIsRunning()
        XCTAssertTrue(isRunning)
    }

    func testRepeatedStopCompletesAfterRuntimeStops() async {
        let startExpectation = expectation(description: "Runtime starts")
        ASTRuntime.start { error in
            XCTAssertNil(error)
            startExpectation.fulfill()
        }
        await fulfillment(of: [startExpectation], timeout: 2)

        let firstStop = expectation(description: "First stop completes")
        ASTRuntime.stop {
            firstStop.fulfill()
        }
        let secondStop = expectation(description: "Second stop completes")
        ASTRuntime.stop {
            secondStop.fulfill()
        }

        await fulfillment(of: [firstStop, secondStop], timeout: 2)
        let isRunning = await runtimeIsRunning()
        XCTAssertFalse(isRunning)
    }

    func testRuntimeCanStartFromBackgroundThread() async {
        let startExpectation = expectation(
            description: "Background start completes"
        )
        await Task.detached {
            ASTRuntime.start { error in
                XCTAssertNil(error)
                startExpectation.fulfill()
            }
        }.value

        await fulfillment(of: [startExpectation], timeout: 2)
        let isRunning = await runtimeIsRunning()
        XCTAssertTrue(isRunning)
    }

    private func stopRuntime() async {
        await withCheckedContinuation { continuation in
            ASTRuntime.stop {
                continuation.resume()
            }
        }
    }

    private func runtimeIsRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            ASTRuntime.isRunning { isRunning in
                continuation.resume(returning: isRunning)
            }
        }
    }
}
#endif
