//
//  RuntimeRequestExecutor.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol
import Foundation

struct RuntimeRequestExecutor: Sendable {
    static func execute(
        router: RuntimeRequestRouter,
        header: RuntimeRequestHeader,
        payload: Data,
        timeoutNanoseconds: UInt64
    ) async -> RuntimeRouteResult? {
        let race = RuntimeRequestRace()
        let operationTask = Task {
            do {
                let result = try await router.routeValidated(
                    header: header,
                    payload: payload
                )
                await race.resolve(.completed(result))
            } catch is CancellationError {
                await race.resolve(.cancelled)
            } catch {
                await race.resolve(.failed)
            }
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                await race.resolve(.timedOut)
            } catch {
                return
            }
        }
        let outcome = await withTaskCancellationHandler {
            await race.waitForOutcome()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task {
                await race.resolve(.cancelled)
            }
        }
        operationTask.cancel()
        timeoutTask.cancel()

        switch outcome {
        case let .completed(result):
            return result
        case .cancelled:
            return failureResult(
                router: router,
                header: header,
                code: .requestCancelled,
                message: "The request was cancelled."
            )
        case .timedOut:
            return failureResult(
                router: router,
                header: header,
                code: .requestTimedOut,
                message: "The request exceeded its execution timeout."
            )
        case .failed:
            return failureResult(
                router: router,
                header: header,
                code: .internalFailure,
                message: "Request execution failed."
            )
        }
    }

    private static func failureResult(
        router: RuntimeRequestRouter,
        header: RuntimeRequestHeader,
        code: RuntimeErrorCode,
        message: String
    ) -> RuntimeRouteResult? {
        try? router.failureResult(
            header: header,
            error: RuntimeError(
                code: code,
                message: message,
                recoverySuggestion: nil
            )
        )
    }
}

private actor RuntimeRequestRace {
    private var outcome: RuntimeRequestOutcome?
    private var continuation: CheckedContinuation<RuntimeRequestOutcome, Never>?

    func waitForOutcome() async -> RuntimeRequestOutcome {
        if let outcome {
            return outcome
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ outcome: RuntimeRequestOutcome) {
        guard self.outcome == nil else {
            return
        }
        self.outcome = outcome
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

private enum RuntimeRequestOutcome: Sendable {
    case completed(RuntimeRouteResult)
    case cancelled
    case timedOut
    case failed
}
