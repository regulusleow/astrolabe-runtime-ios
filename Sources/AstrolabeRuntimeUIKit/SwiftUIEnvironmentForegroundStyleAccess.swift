#if canImport(UIKit)
import AstrolabeRuntimeObjC
import Darwin
import SwiftUI

/// Reads the current native foreground, separating a default nil style from an unavailable getter.
@available(iOS 17.0, *)
@MainActor
enum SwiftUIEnvironmentForegroundStyleAccess {
    struct Reading {
        /// Native nil means the default palette; absence of Reading means the call was refused.
        let style: AnyShapeStyle?
    }

    static func read(_ environment: EnvironmentValues, local: inout UIKitSemanticTraversalBudget,
                     budget: inout UIKitSemanticTraversalBudget) -> Reading? {
        #if arch(arm64) && !targetEnvironment(macCatalyst)
        guard !ProcessInfo.processInfo.isiOSAppOnMac else { return nil }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        let symbol = "$s7SwiftUI17EnvironmentValuesVAAE15foregroundStyleAA08AnyShapeF0VSgvg"
        guard SwiftUITextMetadataPolicy.supportsCurrentLayout,
              SwiftUITextMetadataPolicy.supportsHierarchyLayout(major: version.majorVersion, minor: version.minorVersion, simulator: simulator),
              MemoryLayout<EnvironmentValues>.size == 16, MemoryLayout<EnvironmentValues>.alignment == 8,
              MemoryLayout<AnyShapeStyle?>.size == 8, MemoryLayout<AnyShapeStyle?>.alignment == 8,
              let getter = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol),
              local.consume(depth: 1), budget.consume(depth: 1) else { return nil }
        var image = Dl_info()
        var environmentImage = Dl_info()
        guard dladdr(getter, &image) != 0,
              dladdr(unsafeBitCast(EnvironmentValues.self, to: UnsafeRawPointer.self), &environmentImage) != 0,
              image.dli_fbase == environmentImage.dli_fbase, image.dli_saddr == getter,
              let name = image.dli_sname, String(cString: name) == symbol,
              local.consume(depth: 2), budget.consume(depth: 2) else { return nil }
        var style: AnyShapeStyle? = nil
        withUnsafePointer(to: environment) { environmentPointer in
            withUnsafeMutablePointer(to: &style) { result in
                ASTCopySwiftUIForegroundStyle(environmentPointer, getter, result)
            }
        }
        return Reading(style: style)
        #else
        return nil
        #endif
    }
}
#endif
