//
//  LocalTCPRuntimeTransport.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import Foundation
import Network

package actor LocalTCPRuntimeTransport: RuntimeTransport {
    /// Loopback endpoint selected by the listener after a successful start.
    package private(set) var boundEndpoint: RuntimeTransportEndpoint?

    private let portSelection: LocalTCPRuntimePortSelection
    private let listenerQueue = DispatchQueue(
        label: "com.astrolabe.runtime.local-listener"
    )
    private var listener: NWListener?
    private var streamContinuation: RuntimeConnectionStream.Continuation?
    private var startContinuation: CheckedContinuation<RuntimeConnectionStream, Error>?
    private var connectionStream: RuntimeConnectionStream?
    private var remainingPorts = [UInt16]()
    private var listenerAttemptID: UUID?

    package init(
        portSelection: LocalTCPRuntimePortSelection = .platformDefault
    ) {
        self.portSelection = portSelection
    }

    package func start() async throws -> RuntimeConnectionStream {
        guard listener == nil else {
            throw RuntimeTransportError.alreadyStarted
        }

        remainingPorts = try candidatePorts()
        let stream = RuntimeConnectionStream { continuation in
            streamContinuation = continuation
        }
        connectionStream = stream

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            startNextListener()
        }
    }

    package func stop() async {
        listener?.cancel()
        listener = nil
        listenerAttemptID = nil
        remainingPorts.removeAll()
        boundEndpoint = nil
        startContinuation?.resume(
            throwing: RuntimeTransportError.listenerFailed("Listener stopped before startup completed.")
        )
        startContinuation = nil
        streamContinuation?.finish()
        streamContinuation = nil
        connectionStream = nil
    }

    private func startNextListener() {
        guard !remainingPorts.isEmpty else {
            failStartup(with: .noAvailablePort)
            return
        }
        let rawPort = remainingPorts.removeFirst()
        let listenerPort: NWEndpoint.Port
        if rawPort == 0 {
            listenerPort = .any
        } else {
            guard let port = NWEndpoint.Port(rawValue: rawPort) else {
                failStartup(
                    with: .listenerFailed("Invalid listening port: \(rawPort)")
                )
                return
            }
            listenerPort = port
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: listenerPort
        )

        do {
            let listener = try NWListener(using: parameters)
            let attemptID = UUID()
            self.listener = listener
            listenerAttemptID = attemptID
            listener.stateUpdateHandler = { [weak self] state in
                Task {
                    await self?.handleListenerState(
                        state,
                        attemptID: attemptID
                    )
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                let runtimeConnection = NetworkRuntimeConnection(
                    connection: connection
                )
                runtimeConnection.start()
                Task {
                    await self?.yield(
                        runtimeConnection,
                        attemptID: attemptID
                    )
                }
            }
            listener.start(queue: listenerQueue)
        } catch {
            listener = nil
            listenerAttemptID = nil
            handleStartupFailure(error)
        }
    }

    private func handleListenerState(
        _ state: NWListener.State,
        attemptID: UUID
    ) {
        guard listenerAttemptID == attemptID else {
            return
        }
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else {
                listener?.cancel()
                failStartup(
                    with: .listenerFailed(
                        "Listener reached the ready state without a bound port."
                    )
                )
                return
            }
            boundEndpoint = RuntimeTransportEndpoint(
                host: "127.0.0.1",
                port: port
            )
            if let continuation = startContinuation,
               let connectionStream {
                startContinuation = nil
                continuation.resume(returning: connectionStream)
            }
        case let .failed(error):
            let transportError = RuntimeTransportError.listenerFailed(
                String(describing: error)
            )
            if startContinuation != nil {
                listener?.cancel()
                listener = nil
                listenerAttemptID = nil
                handleStartupFailure(error)
            } else {
                streamContinuation?.finish(throwing: transportError)
                clearListenerState()
            }
        case .cancelled:
            if let continuation = startContinuation {
                startContinuation = nil
                continuation.resume(
                    throwing: RuntimeTransportError.listenerFailed("Listener was cancelled.")
                )
            }
            streamContinuation?.finish()
            clearListenerState()
        default:
            break
        }
    }

    private func yield(
        _ connection: NetworkRuntimeConnection,
        attemptID: UUID
    ) async {
        guard listenerAttemptID == attemptID, let streamContinuation else {
            await connection.close()
            return
        }
        if case .terminated = streamContinuation.yield(connection) {
            await connection.close()
        }
    }

    private func candidatePorts() throws -> [UInt16] {
        switch portSelection {
        case .ephemeral:
            return [0]
        case let .fixed(port):
            guard port > 0 else {
                throw RuntimeTransportError.invalidPortSelection
            }
            return [port]
        case let .range(range):
            guard range.lowerBound > 0 else {
                throw RuntimeTransportError.invalidPortSelection
            }
            return Array(range)
        }
    }

    private func handleStartupFailure(_ error: Error) {
        guard isAddressInUse(error) else {
            failStartup(
                with: .listenerFailed(String(describing: error))
            )
            return
        }
        guard !remainingPorts.isEmpty else {
            failStartup(with: .noAvailablePort)
            return
        }
        startNextListener()
    }

    private func isAddressInUse(_ error: Error) -> Bool {
        guard let networkError = error as? NWError,
              case let .posix(code) = networkError else {
            return false
        }
        return code == .EADDRINUSE
    }

    private func failStartup(with error: RuntimeTransportError) {
        let continuation = startContinuation
        startContinuation = nil
        continuation?.resume(throwing: error)
        streamContinuation?.finish(throwing: error)
        clearListenerState()
    }

    private func clearListenerState() {
        listener = nil
        listenerAttemptID = nil
        boundEndpoint = nil
        remainingPorts.removeAll()
        streamContinuation = nil
        connectionStream = nil
    }
}

private final class NetworkRuntimeConnection: RuntimeConnection, @unchecked Sendable {
    let id = UUID()

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let byteStream: AsyncThrowingStream<Data, Error>
    private let byteStreamContinuation: AsyncThrowingStream<Data, Error>.Continuation

    init(connection: NWConnection) {
        self.connection = connection
        queue = DispatchQueue(
            label: "com.astrolabe.runtime.connection.\(id.uuidString)"
        )
        let streamComponents = AsyncThrowingStream<Data, Error>.makeStream()
        byteStream = streamComponents.stream
        byteStreamContinuation = streamComponents.continuation
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }
            switch state {
            case let .failed(error):
                byteStreamContinuation.finish(
                    throwing: RuntimeTransportError.connectionFailed(
                        String(describing: error)
                    )
                )
            case .cancelled:
                byteStreamContinuation.finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNextChunk()
    }

    func incomingBytes() async -> AsyncThrowingStream<Data, Error> {
        byteStream
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(
                        throwing: RuntimeTransportError.connectionFailed(
                            String(describing: error)
                        )
                    )
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func close() async {
        connection.cancel()
        byteStreamContinuation.finish()
    }

    private func receiveNextChunk() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }
            if let data, !data.isEmpty {
                byteStreamContinuation.yield(data)
            }
            if let error {
                byteStreamContinuation.finish(
                    throwing: RuntimeTransportError.connectionFailed(
                        String(describing: error)
                    )
                )
            } else if isComplete {
                byteStreamContinuation.finish()
            } else {
                receiveNextChunk()
            }
        }
    }
}
