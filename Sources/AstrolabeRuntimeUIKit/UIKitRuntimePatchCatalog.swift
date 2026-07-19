//
//  UIKitRuntimePatchCatalog.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/13.
//

#if canImport(UIKit)
import AstrolabeProtocol

struct UIKitRuntimePatchCatalog: Sendable {
    private static let constraintPattern =
        "ios.autoLayout.constraint.<identifier>.constant"
    private static let constraintPrefix = "ios.autoLayout.constraint."
    private static let constraintSuffix = ".constant"

    /// Public protocol catalog advertised to connected Hosts.
    let catalog: RuntimePatchableAttributesPayload

    private let exactAttributes: [String: RuntimePatchableAttribute]
    private let constraintAttribute: RuntimePatchableAttribute

    init() {
        let colorConstraints = RuntimePatchValueConstraints(
            minimum: nil,
            maximum: nil,
            minimumExclusive: false,
            maximumExclusive: false,
            acceptedFormats: ["#RRGGBB", "#RRGGBBAA"],
            allowedValues: []
        )
        let nonnegative = RuntimePatchValueConstraints(
            minimum: 0,
            maximum: nil,
            minimumExclusive: false,
            maximumExclusive: false,
            acceptedFormats: [],
            allowedValues: []
        )
        let unitInterval = RuntimePatchValueConstraints(
            minimum: 0,
            maximum: 1,
            minimumExclusive: false,
            maximumExclusive: false,
            acceptedFormats: [],
            allowedValues: []
        )
        let attributes = [
            patchableAttribute(
                identifier: .text,
                valueType: .string,
                targetTypes: ["UILabel"]
            ),
            patchableAttribute(
                identifier: .fontName,
                valueType: .string,
                targetTypes: ["UILabel"],
                constraints: RuntimePatchValueConstraints(
                    minimum: nil,
                    maximum: nil,
                    minimumExclusive: false,
                    maximumExclusive: false,
                    acceptedFormats: ["PostScript font name"],
                    allowedValues: []
                )
            ),
            patchableAttribute(
                identifier: .fontSize,
                valueType: .number,
                targetTypes: ["UILabel"],
                constraints: RuntimePatchValueConstraints(
                    minimum: 0,
                    maximum: nil,
                    minimumExclusive: true,
                    maximumExclusive: false,
                    acceptedFormats: [],
                    allowedValues: []
                )
            ),
            patchableAttribute(
                identifier: .textColor,
                valueType: .color,
                targetTypes: ["UILabel"],
                constraints: colorConstraints
            ),
            patchableAttribute(
                identifier: .alpha,
                valueType: .number,
                targetTypes: ["UIView"],
                constraints: unitInterval
            ),
            patchableAttribute(
                identifier: .backgroundColor,
                valueType: .color,
                targetTypes: ["UIView"],
                constraints: colorConstraints
            ),
            patchableAttribute(
                identifier: .cornerRadius,
                valueType: .number,
                targetTypes: ["UIView", "CALayer"],
                constraints: nonnegative
            ),
            patchableAttribute(
                identifier: .borderWidth,
                valueType: .number,
                targetTypes: ["UIView", "CALayer"],
                constraints: nonnegative
            ),
            patchableAttribute(
                identifier: .shadowOpacity,
                valueType: .number,
                targetTypes: ["UIView", "CALayer"],
                constraints: unitInterval
            ),
            patchableAttribute(
                identifier: .shadowRadius,
                valueType: .number,
                targetTypes: ["UIView", "CALayer"],
                constraints: nonnegative
            ),
            patchableAttribute(
                identifier: .borderColor,
                valueType: .color,
                targetTypes: ["UIView", "CALayer"],
                constraints: colorConstraints
            ),
            patchableAttribute(
                identifier: .shadowColor,
                valueType: .color,
                targetTypes: ["UIView", "CALayer"],
                constraints: colorConstraints
            ),
            patchableAttribute(
                identifier: .shadowOffset,
                valueType: .vector,
                targetTypes: ["UIView", "CALayer"]
            ),
            patchableAttribute(
                identifier: .shadowOffsetWidth,
                valueType: .number,
                targetTypes: ["UIView", "CALayer"]
            ),
            patchableAttribute(
                identifier: .shadowOffsetHeight,
                valueType: .number,
                targetTypes: ["UIView", "CALayer"]
            )
        ]
        let constraintAttribute = patchableAttribute(
            pattern: Self.constraintPattern,
            valueType: .number,
            targetTypes: ["UIView"]
        )
        self.constraintAttribute = constraintAttribute
        exactAttributes = Dictionary(
            uniqueKeysWithValues: attributes.map {
                ($0.attributePattern, $0)
            }
        )
        catalog = RuntimePatchableAttributesPayload(
            attributes: attributes + [constraintAttribute]
        )
    }

    func attribute(
        for identifier: RuntimeAttributeIdentifier
    ) -> RuntimePatchableAttribute? {
        if let attribute = exactAttributes[identifier.rawValue] {
            return attribute
        }
        guard isConstraintConstant(identifier.rawValue) else {
            return nil
        }
        return constraintAttribute
    }

    private func isConstraintConstant(_ identifier: String) -> Bool {
        guard identifier.hasPrefix(Self.constraintPrefix),
              identifier.hasSuffix(Self.constraintSuffix) else {
            return false
        }
        let valueStart = identifier.index(
            identifier.startIndex,
            offsetBy: Self.constraintPrefix.count
        )
        let valueEnd = identifier.index(
            identifier.endIndex,
            offsetBy: -Self.constraintSuffix.count
        )
        return valueStart < valueEnd
    }
}

private func patchableAttribute(
    identifier: RuntimeAttributeIdentifier,
    valueType: RuntimePatchValueType,
    targetTypes: [String],
    constraints: RuntimePatchValueConstraints? = nil
) -> RuntimePatchableAttribute {
    patchableAttribute(
        pattern: identifier.rawValue,
        valueType: valueType,
        targetTypes: targetTypes,
        constraints: constraints
    )
}

private func patchableAttribute(
    pattern: String,
    valueType: RuntimePatchValueType,
    targetTypes: [String],
    constraints: RuntimePatchValueConstraints? = nil
) -> RuntimePatchableAttribute {
    do {
        return try RuntimePatchableAttribute(
            attributePattern: pattern,
            valueType: valueType,
            targetRoles: [],
            valueConstraints: constraints,
            extensions: RuntimeExtensionMap(
                values: [
                    "ios.targetTypes": .array(
                        targetTypes.map(RuntimeJSONValue.string)
                    )
                ]
            )
        )
    } catch {
        preconditionFailure("Invalid built-in iOS patch catalog entry: \(pattern)")
    }
}
#endif
