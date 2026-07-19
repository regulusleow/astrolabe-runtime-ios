//
//  UIKitRuntimeScreenMapper.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeProtocol
import UIKit

@MainActor
struct UIKitRuntimeScreenMapper {
    func displayInfo(for screen: UIScreen) -> RuntimeDisplayInfo {
        RuntimeDisplayInfo(
            logicalSize: RuntimeMeasuredSize(
                width: screen.bounds.width,
                height: screen.bounds.height,
                unit: .logical
            ),
            pixelSize: RuntimeMeasuredSize(
                width: screen.nativeBounds.width,
                height: screen.nativeBounds.height,
                unit: .pixel
            ),
            logicalToPixelScale: RuntimeScale(
                x: screen.nativeBounds.width / screen.bounds.width,
                y: screen.nativeBounds.height / screen.bounds.height
            ),
            maximumRefreshRate: Double(screen.maximumFramesPerSecond)
        )
    }
}
#endif
