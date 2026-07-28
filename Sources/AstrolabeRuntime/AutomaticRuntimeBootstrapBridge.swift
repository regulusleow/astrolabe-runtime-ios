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
#endif
