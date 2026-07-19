//
//  RuntimeRequestRouter.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol
import Foundation

protocol RuntimeRequestHandling: Sendable {
    var method: RuntimeMethod { get }

    func handle(
        header: RuntimeRequestHeader,
        payload: Data,
        codec: RuntimeMessageCodec
    ) async throws -> Data
}

struct TypedRuntimeRequestHandler<Parameters, ResponsePayload>: RuntimeRequestHandling
where Parameters: Codable & Equatable & Sendable,
      ResponsePayload: Codable & Equatable & Sendable {
    let method: RuntimeMethod
    let operation: @Sendable (RuntimeRequest<Parameters>) async throws -> ResponsePayload

    func handle(
        header: RuntimeRequestHeader,
        payload: Data,
        codec: RuntimeMessageCodec
    ) async throws -> Data {
        let request: RuntimeRequest<Parameters>
        do {
            request = try codec.decode(RuntimeRequest<Parameters>.self, from: payload)
        } catch {
            throw RuntimeError(
                code: .invalidParameters,
                message: "Request parameters could not be decoded.",
                recoverySuggestion: nil
            )
        }

        guard request.requestID == header.requestID,
              request.protocolVersion == header.protocolVersion,
              request.method == header.method else {
            throw RuntimeError(
                code: .malformedMessage,
                message: "Request envelope changed while decoding parameters.",
                recoverySuggestion: nil
            )
        }

        try Task.checkCancellation()
        let responsePayload = try await operation(request)
        try Task.checkCancellation()
        return try codec.encode(
            RuntimeResponse.success(
                requestID: request.requestID,
                method: request.method,
                payload: responsePayload
            )
        )
    }
}

struct ControlRuntimeRequestHandler: RuntimeRequestHandling {
    let method: RuntimeMethod

    func handle(
        header: RuntimeRequestHeader,
        payload: Data,
        codec: RuntimeMessageCodec
    ) async throws -> Data {
        throw RuntimeError(
            code: .internalFailure,
            message: "Control request reached the business router.",
            recoverySuggestion: nil
        )
    }
}

struct RuntimeRequestRouter: Sendable {
    private let supportedProtocolRange: RuntimeProtocolRange
    private let handlers: [RuntimeMethod: any RuntimeRequestHandling]
    private let codec = RuntimeMessageCodec()

    init(
        supportedProtocolRange: RuntimeProtocolRange,
        handlers: [any RuntimeRequestHandling]
    ) {
        self.supportedProtocolRange = supportedProtocolRange
        self.handlers = Dictionary(uniqueKeysWithValues: handlers.map { ($0.method, $0) })
    }

    func route(
        payload: Data,
        negotiatedProtocolVersion: RuntimeProtocolVersion?
    ) async throws -> RuntimeRouteResult {
        let header = try decodeHeader(from: payload)
        if let rejection = try preflight(
            header: header,
            negotiatedProtocolVersion: negotiatedProtocolVersion
        ) {
            return rejection
        }
        return try await routeValidated(header: header, payload: payload)
    }

    func decodeHeader(from payload: Data) throws -> RuntimeRequestHeader {
        do {
            return try codec.decode(RuntimeRequestHeader.self, from: payload)
        } catch {
            throw RuntimeRequestRoutingError.malformedEnvelope
        }
    }

    func preflight(
        header: RuntimeRequestHeader,
        negotiatedProtocolVersion: RuntimeProtocolVersion?
    ) throws -> RuntimeRouteResult? {
        if let negotiatedProtocolVersion,
           header.protocolVersion != negotiatedProtocolVersion {
            return RuntimeRouteResult(
                responsePayload: try failureResponse(
                    header: header,
                    error: RuntimeError(
                        code: .unsupportedProtocolVersion,
                        message: "The request does not use the negotiated " +
                            "protocol version.",
                        recoverySuggestion: nil
                    )
                )
            )
        }

        guard supportedProtocolRange.contains(header.protocolVersion) else {
            return RuntimeRouteResult(
                responsePayload: try failureResponse(
                    header: header,
                    error: RuntimeError(
                        code: .unsupportedProtocolVersion,
                        message: "The requested protocol version is not supported.",
                        recoverySuggestion: nil
                    )
                )
            )
        }

        guard negotiatedProtocolVersion != nil ||
                header.method == .handshake else {
            return RuntimeRouteResult(
                responsePayload: try failureResponse(
                    header: header,
                    error: RuntimeError(
                        code: .handshakeRequired,
                        message: "Handshake must complete before other requests.",
                        recoverySuggestion: nil
                    )
                )
            )
        }

        guard handlers[header.method] != nil else {
            return RuntimeRouteResult(
                responsePayload: try failureResponse(
                    header: header,
                    error: RuntimeError(
                        code: .unsupportedMethod,
                        message: "Unsupported method: \(header.method.rawValue)",
                        recoverySuggestion: nil
                    )
                )
            )
        }

        return nil
    }

    func routeValidated(
        header: RuntimeRequestHeader,
        payload: Data
    ) async throws -> RuntimeRouteResult {
        guard let handler = handlers[header.method] else {
            return try failureResult(
                header: header,
                error: RuntimeError(
                    code: .unsupportedMethod,
                    message: "Control methods must be handled by the connection session.",
                    recoverySuggestion: nil
                )
            )
        }

        do {
            let responsePayload = try await handler.handle(
                header: header,
                payload: payload,
                codec: codec
            )
            return RuntimeRouteResult(
                responsePayload: responsePayload,
                negotiatedProtocolVersion: try negotiatedProtocolVersion(
                    for: header.method,
                    responsePayload: responsePayload
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RuntimeError {
            return RuntimeRouteResult(
                responsePayload: try failureResponse(
                    header: header,
                    error: error
                )
            )
        } catch {
            return RuntimeRouteResult(
                responsePayload: try failureResponse(
                    header: header,
                    error: RuntimeError(
                        code: .internalFailure,
                        message: "Request handling failed.",
                        recoverySuggestion: nil
                    )
                )
            )
        }
    }

    private func negotiatedProtocolVersion(
        for method: RuntimeMethod,
        responsePayload: Data
    ) throws -> RuntimeProtocolVersion? {
        guard method == .handshake else {
            return nil
        }
        let response = try codec.decode(
            RuntimeResponse<RuntimeHandshakePayload>.self,
            from: responsePayload
        )
        guard case let .success(handshake) = response.outcome else {
            return nil
        }
        return handshake.negotiatedProtocolVersion
    }

    func failureResult(
        header: RuntimeRequestHeader,
        error: RuntimeError
    ) throws -> RuntimeRouteResult {
        return RuntimeRouteResult(
            responsePayload: try failureResponse(
                header: header,
                error: error
            )
        )
    }

    private func failureResponse(
        header: RuntimeRequestHeader,
        error: RuntimeError
    ) throws -> Data {
        try codec.encode(
            RuntimeResponse<RuntimeJSONValue>.failure(
                requestID: header.requestID,
                method: header.method,
                error: error
            )
        )
    }
}

struct RuntimeRouteResult: Sendable {
    /// Encoded response payload ready for transport framing.
    let responsePayload: Data

    /// Protocol version established by a successful handshake response.
    let negotiatedProtocolVersion: RuntimeProtocolVersion?

    init(
        responsePayload: Data,
        negotiatedProtocolVersion: RuntimeProtocolVersion? = nil
    ) {
        self.responsePayload = responsePayload
        self.negotiatedProtocolVersion = negotiatedProtocolVersion
    }
}

enum RuntimeRequestRoutingError: Error, Equatable, Sendable {
    case malformedEnvelope
}
