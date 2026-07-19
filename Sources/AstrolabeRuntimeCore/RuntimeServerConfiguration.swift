//
//  RuntimeServerConfiguration.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol
import Foundation

public struct RuntimeServerConfiguration: Sendable {
    /// Runtime implementation identifier used by the official iOS SDK.
    public static let defaultRuntimeIdentifier: RuntimeNamespacedIdentifier = {
        do {
            return try RuntimeNamespacedIdentifier(rawValue: "astrolabe.runtime-ios")
        } catch {
            preconditionFailure("Invalid built-in Runtime identifier")
        }
    }()

    /// Process-scoped Runtime instance identifier shared by default configurations.
    public static let defaultRuntimeInstanceIdentifier: RuntimeOpaqueIdentifier = {
        do {
            return try RuntimeOpaqueIdentifier(rawValue: UUID().uuidString)
        } catch {
            preconditionFailure("Failed to generate the Runtime instance identifier")
        }
    }()

    /// Release version advertised by the embedded runtime.
    public let runtimeVersion: String

    /// Protocol versions accepted by the server.
    public let supportedProtocolRange: RuntimeProtocolRange

    /// Open runtime platform identifier advertised during handshake.
    public let platform: String

    /// Namespaced runtime implementation identifier advertised during handshake.
    public let runtimeIdentifier: RuntimeNamespacedIdentifier

    /// Stable identifier for the current embedded runtime process.
    public let runtimeInstanceIdentifier: RuntimeOpaqueIdentifier

    /// Maximum payload bytes accepted in one transport frame.
    public let maximumPayloadSize: Int

    /// Maximum execution time allowed for one non-control request.
    public let requestTimeoutNanoseconds: UInt64

    /// Maximum number of non-control requests running on one connection.
    public let maximumConcurrentRequests: Int

    public init(
        runtimeVersion: String,
        supportedProtocolRange: RuntimeProtocolRange = .v2,
        platform: String = "ios",
        runtimeIdentifier: RuntimeNamespacedIdentifier = Self.defaultRuntimeIdentifier,
        runtimeInstanceIdentifier: RuntimeOpaqueIdentifier = Self.defaultRuntimeInstanceIdentifier,
        maximumPayloadSize: Int = RuntimeFrameCodec.defaultMaximumPayloadSize,
        requestTimeoutNanoseconds: UInt64 = 10_000_000_000,
        maximumConcurrentRequests: Int = 8
    ) {
        self.runtimeVersion = runtimeVersion
        self.supportedProtocolRange = supportedProtocolRange
        self.platform = platform
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeInstanceIdentifier = runtimeInstanceIdentifier
        self.maximumPayloadSize = maximumPayloadSize
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

}
