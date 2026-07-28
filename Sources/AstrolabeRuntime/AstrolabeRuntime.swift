//
//  AstrolabeRuntime.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol

package enum AstrolabeRuntimeSDK {
    /// Release version advertised by the embedded runtime.
    package static let runtimeVersion = "2.0.0"

    package static var protocolVersion: RuntimeProtocolVersion {
        .v2
    }
}
