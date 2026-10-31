#if canImport(UIKit)
import ObjectiveC
import OSLog
import UIKit

/// Prepares app-local AX metadata without activating a control or changing accessibility settings.
@MainActor
enum UIKitAccessibilityMetadataBootstrap {
    static func prepare() {
        #if os(iOS) && arch(arm64) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        // shortcut: initialization is verified only on iOS 27.2 hardware; verify each new OS before extending.
        guard version.majorVersion == 27, version.minorVersion == 2,
              !ProcessInfo.processInfo.isiOSAppOnMac else { return }
        _ = initialization
        #endif
    }

    /// System initialization is process-wide; never repeat it for subsequent captures or connections.
    private static let initialization: Void = {
        let logger = Logger(subsystem: "com.astrolabe.runtime", category: "AccessibilityMetadata")
        for name in ["UIKit", "SwiftUI"] {
            let path = "/System/Library/AccessibilityBundles/" + name + ".axbundle"
            guard let bundle = Bundle(path: path), bundle.load() else {
                logger.error("辅助功能元数据初始化失败：无法加载系统组件 \(name, privacy: .public)")
                return
            }
        }
        let selector = NSSelectorFromString("_accessibilityInitializeRuntimeOverrides")
        guard let loader = NSClassFromString("UIAccessibilityLoader") as? NSObject.Type,
              let image = class_getImageName(loader),
              String(cString: image) == "/System/Library/PrivateFrameworks/UIAccessibility.framework/UIAccessibility",
              let method = class_getClassMethod(loader, selector),
              method_getNumberOfArguments(method) == 2,
              let encoding = method_getTypeEncoding(method),
              String(cString: encoding) == "v16@0:8" else {
            logger.error("辅助功能元数据初始化失败：系统入口或调用签名不匹配")
            return
        }
        // The checked selector returns void; no object is taken from perform's unretained result.
        _ = loader.perform(selector)
    }()
}
#endif
