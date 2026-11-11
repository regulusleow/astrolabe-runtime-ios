#if canImport(UIKit)
import AstrolabeProtocol
import CoreText
import SwiftUI

/// Shared source-font resolution for whole Text and its individual runs.
@available(iOS 26.0, *)
@MainActor
enum SwiftUIFontProjector {
    static func attributes(_ font: Font, environment: EnvironmentValues) -> [RuntimeAttribute]? {
        let resolved = font.resolve(in: environment.fontResolutionContext)
        let size = Double(resolved.pointSize)
        guard size.isFinite && size > 0 else { return nil }
        return [RuntimeAttribute(identifier: try! .init(rawValue: "common.text.fontName"), value: .string(CTFontCopyPostScriptName(resolved.ctFont) as String)),
                RuntimeAttribute(identifier: try! .init(rawValue: "common.text.fontSize"), value: .measurement(.init(value: size, unit: .scaledLogical))),
                RuntimeAttribute(identifier: try! .init(rawValue: "ios.swiftui.text.isBold"), value: .boolean(resolved.isBold)),
                RuntimeAttribute(identifier: try! .init(rawValue: "ios.swiftui.text.isMonospaced"), value: .boolean(resolved.isMonospaced))]
    }
}
#endif
