//
//  UIKitRuntimeColorMapper.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import CoreGraphics
import UIKit

struct UIKitRuntimeColorMapper {
    func color(
        from color: UIColor?,
        traitCollection: UITraitCollection
    ) -> RuntimeColor? {
        guard let color else {
            return nil
        }
        return self.color(
            from: color.resolvedColor(with: traitCollection).cgColor
        )
    }

    func color(from color: CGColor?) -> RuntimeColor? {
        guard let color,
              let targetColorSpace = CGColorSpace(
                  name: CGColorSpace.sRGB
              ),
              let convertedColor = color.converted(
                  to: targetColorSpace,
                  intent: .defaultIntent,
                  options: nil
              ),
              let components = convertedColor.components,
              components.count >= 4 else {
            return nil
        }

        return RuntimeColor(
            colorSpace: "srgb",
            red: normalized(components[0]),
            green: normalized(components[1]),
            blue: normalized(components[2]),
            alpha: normalized(components[3])
        )
    }

    private func normalized(_ component: CGFloat) -> Double {
        min(max(Double(component), 0), 1)
    }
}
#endif
