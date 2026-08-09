//
//  UIKitRuntimeGradientLayerAttributeCollector.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/8/4.
//

#if canImport(UIKit)
import AstrolabeProtocol
import QuartzCore

struct UIKitGradientLayerAttributeCollector:
    UIKitRuntimeAttributeCollecting
{
    let category = RuntimeAttributeCategory.gradientLayer

    func supports(_ object: AnyObject) -> Bool {
        object is CAGradientLayer
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let layer = object as? CAGradientLayer else {
            return []
        }

        var attributes = [RuntimeAttribute]()
        if let colors = colorValues(
            from: layer.colors,
            colorMapper: context.colorMapper
        ) {
            attributes.append(
                attribute(.gradientLayerColors, .array(colors))
            )
        }
        if let locations = layer.locations {
            attributes.append(
                attribute(
                    .gradientLayerLocations,
                    .array(locations.map { .number($0.doubleValue) })
                )
            )
        }
        attributes.append(contentsOf: [
            attribute(
                .gradientLayerStartPoint,
                unitPointValue(layer.startPoint)
            ),
            attribute(
                .gradientLayerEndPoint,
                unitPointValue(layer.endPoint)
            ),
            attribute(.gradientLayerType, .string(layer.type.rawValue))
        ])
        return attributes
    }

    private func colorValues(
        from sourceColors: [Any]?,
        colorMapper: UIKitRuntimeColorMapper
    ) -> [RuntimeJSONValue]? {
        guard let sourceColors,
              let colors = sourceColors as? [CGColor] else {
            return nil
        }
        var values = [RuntimeJSONValue]()
        for color in colors {
            guard let runtimeColor = colorMapper.color(from: color) else {
                return nil
            }
            values.append(colorValue(runtimeColor))
        }
        return values
    }

    private func colorValue(_ color: RuntimeColor) -> RuntimeJSONValue {
        .object([
            "colorSpace": .string(color.colorSpace),
            "red": .number(color.red),
            "green": .number(color.green),
            "blue": .number(color.blue),
            "alpha": .number(color.alpha)
        ])
    }

    private func unitPointValue(_ point: CGPoint) -> RuntimeAttributeValue {
        .object([
            "x": .number(point.x),
            "y": .number(point.y)
        ])
    }
}
#endif
