//
//  RuntimeConnectionSession.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol
import Foundation

actor RuntimeConnectionSession {
    private let connection: any RuntimeConnection
    private let router: RuntimeRequestRouter
    private let frameCodec: RuntimeFrameCodec
    private let requestTimeoutNanoseconds: UInt64
    private let maximumConcurrentRequests: Int
    private let messageCodec = RuntimeMessageCodec()
    private let responseWriter: RuntimeResponseWriter
    private var negotiatedProtocolVersion: RuntimeProtocolVersion?
    private var requestTasks = [UUID: Task<Void, Never>]()
    private var isStopped = false

    init(
        connection: any RuntimeConnection,
        router: RuntimeRequestRouter,
        frameCodec: RuntimeFrameCodec,
        requestTimeoutNanoseconds: UInt64,
        maximumConcurrentRequests: Int
    ) {
        self.connection = connection
        self.router = router
        self.frameCodec = frameCodec
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        self.maximumConcurrentRequests = maximumConcurrentRequests
        responseWriter = RuntimeResponseWriter(connection: connection)
    }

    func run() async {
        var decoder = frameCodec.makeStreamDecoder()
        let incomingBytes = await connection.incomingBytes()

        do {
            for try await chunk in incomingBytes {
                try Task.checkCancellation()
                for payload in try decoder.append(chunk) {
                    try await receive(payload)
                }
            }
        } catch {
            // Closing the connection is the protocol response for malformed framing.
        }

        await stop()
    }

    func stop() async {
        guard !isStopped else {
            return
        }
        isStopped = true
        let tasks = Array(requestTasks.values)
        requestTasks.removeAll()
        for task in tasks {
            task.cancel()
        }
        await connection.close()
    }

    private func receive(_ payload: Data) async throws {
        let header = try router.decodeHeader(from: payload)
        if let rejection = try router.preflight(
            header: header,
            negotiatedProtocolVersion: negotiatedProtocolVersion
        ) {
            _ = try await send(rejection, for: header)
            return
        }

        guard requestTasks[header.requestID] == nil else {
            _ = try await send(
                router.failureResult(
                    header: header,
                    error: RuntimeError(
                        code: .invalidParameters,
                        message: "A request with the same ID is already running.",
                        recoverySuggestion: nil
                    )
                ),
                for: header
            )
            return
        }

        if header.method == .cancelRequest {
            try await handleCancellation(header: header, payload: payload)
            return
        }

        guard requestTasks.count < maximumConcurrentRequests else {
            _ = try await send(
                router.failureResult(
                    header: header,
                    error: RuntimeError(
                        code: .tooManyRequests,
                        message: "The connection has reached its request limit.",
                        recoverySuggestion: "Wait for an active request to " +
                            "complete and retry."
                    )
                ),
                for: header
            )
            return
        }

        let router = router
        let timeout = requestTimeoutNanoseconds
        let task = Task { [weak self] in
            let result = await RuntimeRequestExecutor.execute(
                router: router,
                header: header,
                payload: payload,
                timeoutNanoseconds: timeout
            )
            await self?.complete(
                header: header,
                result: result
            )
        }
        requestTasks[header.requestID] = task
    }

    private func handleCancellation(
        header: RuntimeRequestHeader,
        payload: Data
    ) async throws {
        let request: RuntimeRequest<RuntimeCancelRequestParameters>
        do {
            request = try messageCodec.decode(
                RuntimeRequest<RuntimeCancelRequestParameters>.self,
                from: payload
            )
        } catch {
            _ = try await send(
                router.failureResult(
                    header: header,
                    error: RuntimeError(
                        code: .invalidParameters,
                        message: "Cancellation parameters could not be decoded.",
                        recoverySuggestion: nil
                    )
                ),
                for: header
            )
            return
        }
        guard request.requestID == header.requestID,
              request.protocolVersion == header.protocolVersion,
              request.method == header.method else {
            _ = try await send(
                router.failureResult(
                    header: header,
                    error: RuntimeError(
                        code: .malformedMessage,
                        message: "Cancellation envelope changed while decoding parameters.",
                        recoverySuggestion: nil
                    )
                ),
                for: header
            )
            return
        }

        let targetRequestID = request.parameters.targetRequestID
        let targetTask = requestTasks[targetRequestID]
        targetTask?.cancel()
        let response = try RuntimeResponse.success(
            requestID: request.requestID,
            method: request.method,
            payload: RuntimeCancelRequestPayload(
                targetRequestID: targetRequestID,
                cancellationAccepted: targetTask != nil
            )
        )
        _ = try await send(
            RuntimeRouteResult(
                responsePayload: try messageCodec.encode(response)
            ),
            for: header
        )
    }

    private func complete(
        header: RuntimeRequestHeader,
        result: RuntimeRouteResult?
    ) async {
        let requestTask = requestTasks.removeValue(forKey: header.requestID)
        guard !isStopped else {
            return
        }
        let finalResult: RuntimeRouteResult?
        if requestTask?.isCancelled == true {
            finalResult = try? router.failureResult(
                header: header,
                error: RuntimeError(
                    code: .requestCancelled,
                    message: "The request was cancelled.",
                    recoverySuggestion: nil
                )
            )
        } else {
            finalResult = result
        }
        guard let finalResult else {
            return
        }
        do {
            let didSendOriginalResponse = try await send(
                finalResult,
                for: header
            )
            if didSendOriginalResponse,
               let version = finalResult.negotiatedProtocolVersion {
                negotiatedProtocolVersion = version
            }
        } catch {
            await stop()
        }
    }

    private func send(
        _ result: RuntimeRouteResult,
        for header: RuntimeRequestHeader
    ) async throws -> Bool {
        let frame: Data
        let didSendOriginalResponse: Bool
        do {
            frame = try frameCodec.encode(payload: result.responsePayload)
            didSendOriginalResponse = true
        } catch RuntimeFrameError.payloadTooLarge(let actual, let maximum) {
            let failure = try router.failureResult(
                header: header,
                error: RuntimeError(
                    code: .frameTooLarge,
                    message: "The response payload exceeds the configured frame limit.",
                    recoverySuggestion: "Reduce the requested data or increase " +
                        "the runtime frame limit. Actual bytes: \(actual), " +
                        "maximum bytes: \(maximum)."
                )
            )
            frame = try frameCodec.encode(payload: failure.responsePayload)
            didSendOriginalResponse = false
        }
        try await responseWriter.send(frame)
        return didSendOriginalResponse
    }
}
