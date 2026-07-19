//
//  LocalTCPRuntimePortSelection.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import Foundation

public enum RuntimePortDefaults {
    /// Ports scanned by the Host for simulator runtime processes.
    public static let simulatorRange: ClosedRange<UInt16> = 47_200...47_209

    /// Device ports reached by the Host through USB forwarding.
    public static let deviceRange: ClosedRange<UInt16> = 47_210...47_219
}

public enum LocalTCPRuntimePortSelection: Equatable, Sendable {
    /// Ask the operating system to select an ephemeral port.
    case ephemeral

    /// Bind exactly one nonzero port.
    case fixed(UInt16)

    /// Try each nonzero port from lower bound to upper bound.
    case range(ClosedRange<UInt16>)

    /// Default discovery range for the current simulator or device build.
    public static var platformDefault: LocalTCPRuntimePortSelection {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        return .range(RuntimePortDefaults.simulatorRange)
        #elseif os(iOS)
        if #available(iOS 14.0, *), ProcessInfo.processInfo.isiOSAppOnMac {
            return .range(RuntimePortDefaults.simulatorRange)
        }
        return .range(RuntimePortDefaults.deviceRange)
        #else
        return .range(RuntimePortDefaults.deviceRange)
        #endif
    }
}
