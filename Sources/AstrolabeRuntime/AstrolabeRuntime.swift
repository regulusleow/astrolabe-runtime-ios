//
//  AstrolabeRuntime.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol

public enum AstrolabeRuntimeSDK {
    /// Release version advertised by the embedded runtime.
    public static let runtimeVersion = "1.0.0"

    public static var protocolVersion: RuntimeProtocolVersion {
        .v2
    }
}
