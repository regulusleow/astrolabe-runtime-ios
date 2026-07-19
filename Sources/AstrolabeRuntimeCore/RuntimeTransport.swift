//
//  RuntimeTransport.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import Foundation

public struct RuntimeTransportEndpoint: Equatable, Sendable {
    /// Listener host exposed to local inspection clients.
    public let host: String

    /// Listener TCP port.
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

package typealias RuntimeConnectionStream =
    AsyncThrowingStream<any RuntimeConnection, Error>

package protocol RuntimeConnection: AnyObject, Sendable {
    /// Stable identifier for the lifetime of one transport connection.
    var id: UUID { get }

    func incomingBytes() async -> AsyncThrowingStream<Data, Error>
    func send(_ data: Data) async throws
    func close() async
}

package protocol RuntimeTransport: AnyObject, Sendable {
    func start() async throws -> RuntimeConnectionStream
    func stop() async
}

package enum RuntimeTransportError: Error, Equatable, Sendable {
    case alreadyStarted
    case invalidPortSelection
    case noAvailablePort
    case listenerFailed(String)
    case connectionFailed(String)
}
