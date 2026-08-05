//
//  UIKitRuntimeShapeLayerAttributeCollector.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/8/5.
//

#if canImport(UIKit)
import AstrolabeProtocol
import CoreGraphics
import QuartzCore

struct UIKitShapeLayerAttributeCollector: UIKitRuntimeAttributeCollecting {
    let category = RuntimeAttributeCategory.shapeLayer
    private let pathProjector = UIKitShapePathProjector()

    func supports(_ object: AnyObject) -> Bool {
        object is CAShapeLayer
    }

    func attributes(
        for object: AnyObject,
        context: UIKitRuntimeAttributeCollectionContext
    ) -> [RuntimeAttribute] {
        guard let layer = object as? CAShapeLayer else {
            return []
        }

        var attributes = [
            attribute(.shapeLayerFillRule, .string(layer.fillRule.rawValue))
        ]
        if let path = layer.path,
           let pathValue = pathProjector.value(for: path) {
            attributes.insert(
                attribute(.shapeLayerPath, pathValue),
                at: 0
            )
        }
        return attributes
    }
}

struct UIKitShapePathProjector {
    private let maximumElementCount: Int

    init(maximumElementCount: Int = 256) {
        precondition(maximumElementCount > 0)
        self.maximumElementCount = maximumElementCount
    }

    func value(for path: CGPath) -> RuntimeAttributeValue? {
        var elementCount = 0
        var elements = [RuntimeJSONValue]()
        var valid = true
        path.applyWithBlock { pointer in
            elementCount += 1
            guard let value = elementValueIfFinite(pointer.pointee) else {
                valid = false
                return
            }
            if elements.count < maximumElementCount {
                elements.append(value)
            }
        }
        guard valid else {
            return nil
        }
        var result: [String: RuntimeJSONValue] = [
            "coordinateSpace": .string("local"),
            "elementCount": .integer(Int64(elementCount)),
            "returnedElementCount": .integer(Int64(elements.count)),
            "truncated": .boolean(elements.count < elementCount),
            "elements": .array(elements)
        ]
        let bounds = path.boundingBoxOfPath
        if !path.isEmpty {
            guard !bounds.isNull, finite(bounds) else {
                return nil
            }
            result["boundingBox"] = rectValue(bounds)
        }
        return .object(result)
    }

    func pointValueIfFinite(_ point: CGPoint) -> RuntimeJSONValue? {
        guard point.x.isFinite, point.y.isFinite else {
            return nil
        }
        return pointValue(point)
    }

    private func elementValueIfFinite(
        _ element: CGPathElement
    ) -> RuntimeJSONValue? {
        switch element.type {
        case .moveToPoint:
            guard let point = pointValueIfFinite(element.points[0]) else {
                return nil
            }
            return .object([
                "type": .string("moveTo"),
                "point": point
            ])
        case .addLineToPoint:
            guard let point = pointValueIfFinite(element.points[0]) else {
                return nil
            }
            return .object([
                "type": .string("lineTo"),
                "point": point
            ])
        case .addQuadCurveToPoint:
            guard let controlPoint = pointValueIfFinite(element.points[0]),
                  let point = pointValueIfFinite(element.points[1]) else {
                return nil
            }
            return .object([
                "type": .string("quadCurveTo"),
                "controlPoint": controlPoint,
                "point": point
            ])
        case .addCurveToPoint:
            guard let controlPoint1 = pointValueIfFinite(element.points[0]),
                  let controlPoint2 = pointValueIfFinite(element.points[1]),
                  let point = pointValueIfFinite(element.points[2]) else {
                return nil
            }
            return .object([
                "type": .string("curveTo"),
                "controlPoint1": controlPoint1,
                "controlPoint2": controlPoint2,
                "point": point
            ])
        case .closeSubpath:
            return .object(["type": .string("closeSubpath")])
        @unknown default:
            preconditionFailure("Unsupported CGPath element type")
        }
    }

    private func finite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite &&
            rect.origin.y.isFinite &&
            rect.size.width.isFinite &&
            rect.size.height.isFinite
    }

    private func pointValue(_ point: CGPoint) -> RuntimeJSONValue {
        .object([
            "x": .number(point.x),
            "y": .number(point.y)
        ])
    }

    private func rectValue(_ rect: CGRect) -> RuntimeJSONValue {
        .object([
            "x": .number(rect.origin.x),
            "y": .number(rect.origin.y),
            "width": .number(rect.size.width),
            "height": .number(rect.size.height)
        ])
    }
}
#endif
