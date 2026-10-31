#if canImport(UIKit)
import Darwin
import Foundation
import SwiftUI
import UIKit

/// Keeps the verified private Swift call outside environment traversal and canonical projection.
@available(iOS 17.0, *)
@MainActor
enum SwiftUIHierarchicalColorResolver {
    /// ABI and palette checks also require the exact validated architecture and native iOS environment.
    private static var isSupportedPlatform: Bool {
        #if arch(arm64)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return SwiftUITextMetadataPolicy.supportsCurrentLayout &&
            SwiftUITextMetadataPolicy.supportsHierarchyLayout(major: version.majorVersion,
                minor: version.minorVersion, simulator: simulator)
        #else
        return false
        #endif
    }

    static func defaultColor(level: Int, environment: EnvironmentValues) -> Color.Resolved? {
        guard isSupportedPlatform,
              SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(level),
              environment.backgroundMaterial == nil else { return nil }
        let color = level == 1 ? Color.secondary : Color(uiColor: .tertiaryLabel)
        return color.resolve(in: environment)
    }

    static func apply(to color: Color, level: Int) -> Color? {
        typealias Apply = @convention(thin) (Int, Color) -> Color
        let symbol = "$s7SwiftUI5ColorV30multiplyingHierarchicalOpacity2atACSi_tF"
        guard isSupportedPlatform,
              SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(level),
              MemoryLayout<Int>.size == 8, MemoryLayout<Color>.size == 8,
              MemoryLayout<Apply>.size == 8,
              let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) else { return nil }
        var functionImage = Dl_info()
        var colorImage = Dl_info()
        let metadata = unsafeBitCast(Color.self, to: UnsafeRawPointer.self)
        guard dladdr(pointer, &functionImage) != 0, dladdr(metadata, &colorImage) != 0,
              functionImage.dli_fbase == colorImage.dli_fbase,
              functionImage.dli_saddr == pointer,
              let name = functionImage.dli_sname, String(cString: name) == symbol else { return nil }
        // The observed frozen Color ABI passes the level and Color provider in x0/x1.
        let apply = unsafeBitCast(pointer, to: Apply.self)
        return apply(level, color)
    }
}
#endif
