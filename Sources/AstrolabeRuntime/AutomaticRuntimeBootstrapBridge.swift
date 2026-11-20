//
//  AutomaticRuntimeBootstrapBridge.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/28.
//

#if canImport(UIKit)
@_cdecl("AstrolabeRuntimeInstallAutomaticBootstrap")
package func installAutomaticAstrolabeRuntime() {
    Task { @MainActor in
        AutomaticRuntimeInstaller.shared.install()
    }
}
#elseif os(macOS)
import AstrolabeRuntimeAppKit

@_cdecl("AstrolabeRuntimeInstallAutomaticBootstrap")
package func installAutomaticAstrolabeRuntime() {
    Task { @MainActor in
        guard #available(macOS 15.0, *) else { return }
        await AppKitRuntimeInstaller.install(version: AstrolabeRuntimeSDK.runtimeVersion)
    }
}
#endif
