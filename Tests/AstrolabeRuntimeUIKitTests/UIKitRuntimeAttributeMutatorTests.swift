//
//  UIKitRuntimeAttributeMutatorTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/13.
//

#if canImport(UIKit)
import AstrolabeRuntimeCore
@testable import AstrolabeRuntimeUIKit
import AstrolabeProtocol
import UIKit
import XCTest

final class UIKitRuntimeAttributeMutatorTests: XCTestCase {
    @MainActor
    func testPatchCatalogDescribesAndMatchesRuntimeWhitelist() throws {
        let catalog = UIKitRuntimePatchCatalog()

        XCTAssertEqual(catalog.catalog.attributes.count, 16)
        XCTAssertEqual(
            catalog.attribute(for: .fontSize)?.valueConstraints?.minimumExclusive,
            true
        )
        XCTAssertEqual(
            catalog.attribute(for: .textColor)?.valueConstraints?.acceptedFormats,
            ["#RRGGBB", "#RRGGBBAA"]
        )
        XCTAssertEqual(
            catalog.attribute(
                for: try RuntimeAttributeIdentifier(
                    rawValue: "ios.autoLayout.constraint.cardWidth.constant"
                )
            )?.attributePattern,
            "ios.autoLayout.constraint.<identifier>.constant"
        )
        XCTAssertNil(catalog.attribute(for: .hidden))
        XCTAssertNil(
            catalog.attribute(
                for: try RuntimeAttributeIdentifier(
                    rawValue: "ios.autoLayout.constraint.constant"
                )
            )
        )
    }

    @MainActor
    func testLabelPatchesApplyAndRestoreTypedPresentationValues() async throws {
        let label = UILabel()
        label.text = "Before"
        label.font = UIFont.systemFont(ofSize: 10)
        label.textColor = .black
        let (service, nodeID) = makeService(object: label)

        let textPatch = try await apply(service, nodeID, .text, .string("After"))
        XCTAssertEqual(label.text, "After")
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: textPatch.patchID)
        )
        XCTAssertEqual(label.text, "Before")

        let fontSizePatch = try await apply(service, nodeID, .fontSize, .number(18))
        XCTAssertEqual(label.font?.pointSize, 18)
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: fontSizePatch.patchID)
        )
        XCTAssertEqual(label.font?.pointSize, 10)
        XCTAssertEqual(label.text, "Before")

        let textColorPatch = try await apply(
            service,
            nodeID,
            .textColor,
            .color(RuntimeColor(colorSpace: "srgb", red: 1, green: 0, blue: 0, alpha: 1))
        )
        XCTAssertTrue(label.textColor.isEqual(UIColor.red))
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: textColorPatch.patchID)
        )
        XCTAssertTrue(label.textColor.isEqual(UIColor.black))
        XCTAssertEqual(label.text, "Before")

        let fontNamePatch = try await apply(
            service,
            nodeID,
            .fontName,
            .string("Helvetica-Bold")
        )
        XCTAssertEqual(label.font?.fontName, "Helvetica-Bold")
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: fontNamePatch.patchID)
        )
        XCTAssertNotEqual(label.font?.fontName, "Helvetica-Bold")
        XCTAssertEqual(label.text, "Before")
    }

    @MainActor
    func testAttributedLabelPatchRestoresOriginalAttributedText() async throws {
        let label = UILabel()
        let originalText = NSAttributedString(
            string: "Before",
            attributes: [
                .font: UIFont.boldSystemFont(ofSize: 11),
                .foregroundColor: UIColor.blue,
                .kern: 2
            ]
        )
        label.attributedText = originalText
        let (service, nodeID) = makeService(object: label)

        let patch = try await apply(service, nodeID, .fontSize, .number(18))

        let patchedFont = label.attributedText?.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? UIFont
        XCTAssertEqual(patchedFont?.pointSize, 18)

        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: patch.patchID)
        )
        XCTAssertEqual(label.attributedText, originalText)
    }

    @MainActor
    func testAttributedLabelCombinesAndIndependentlyRevertsPresentationPatches() async throws {
        let label = UILabel()
        let originalText = NSAttributedString(
            string: "Before",
            attributes: [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.blue,
                .kern: 2
            ]
        )
        label.attributedText = originalText
        let (service, nodeID) = makeService(object: label)

        let fontPatch = try await apply(service, nodeID, .fontSize, .number(18))
        let colorPatch = try await apply(
            service,
            nodeID,
            .textColor,
            .color(RuntimeColor(colorSpace: "srgb", red: 1, green: 0, blue: 0, alpha: 1))
        )

        XCTAssertEqual(attributedFont(in: label)?.pointSize, 18)
        XCTAssertTrue(attributedColor(in: label)?.isEqual(UIColor.red) == true)
        XCTAssertEqual(attributedKern(in: label), 2)

        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: fontPatch.patchID)
        )
        XCTAssertEqual(attributedFont(in: label)?.pointSize, 11)
        XCTAssertTrue(attributedColor(in: label)?.isEqual(UIColor.red) == true)
        XCTAssertEqual(attributedKern(in: label), 2)

        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: colorPatch.patchID)
        )
        XCTAssertEqual(label.attributedText, originalText)
    }

    @MainActor
    func testPlainLabelUpdatesMultiplePresentationPatchesInPlace() async throws {
        let label = UILabel()
        label.text = "Before"
        label.font = UIFont.systemFont(ofSize: 15)
        let (service, nodeID) = makeService(object: label)

        let firstTextPatch = try await apply(service, nodeID, .text, .string("A"))
        let firstFontPatch = try await apply(service, nodeID, .fontSize, .number(20))
        let secondTextPatch = try await apply(service, nodeID, .text, .string("B"))
        let secondFontPatch = try await apply(service, nodeID, .fontSize, .number(15))

        XCTAssertEqual(secondTextPatch.patchID, firstTextPatch.patchID)
        XCTAssertEqual(secondFontPatch.patchID, firstFontPatch.patchID)
        XCTAssertEqual(secondTextPatch.originalValue, .string("Before"))
        XCTAssertEqual(secondFontPatch.originalValue, .number(15))
        XCTAssertEqual(label.text, "B")
        XCTAssertEqual(label.font?.pointSize, 15)

        let patches = await service.activeAttributePatches().patches
        XCTAssertEqual(patches, [secondTextPatch, secondFontPatch])

        _ = try await service.clearAttributePatches()
        XCTAssertEqual(label.text, "Before")
        XCTAssertEqual(label.font?.pointSize, 15)
    }

    @MainActor
    func testExtendedSRGBPatchAcceptsNormalizedSRGBReadback() async throws {
        let label = UILabel()
        label.text = "Color"
        label.textColor = .black
        let (service, nodeID) = makeService(object: label)
        let color = RuntimeColor(
            colorSpace: "extended-srgb",
            red: 1,
            green: 0,
            blue: 0,
            alpha: 1
        )

        let patch = try await apply(service, nodeID, .textColor, .color(color))

        XCTAssertTrue(label.textColor.isEqual(UIColor.red))
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: patch.patchID)
        )
        XCTAssertTrue(label.textColor.isEqual(UIColor.black))
    }

    @MainActor
    func testDisplayP3PatchAcceptsConvertedSRGBReadback() async throws {
        let view = UIView()
        view.backgroundColor = .black
        let (service, nodeID) = makeService(object: view)
        let color = RuntimeColor(
            colorSpace: "display-p3",
            red: 0.8,
            green: 0.2,
            blue: 0.1,
            alpha: 1
        )

        let patch = try await apply(service, nodeID, .backgroundColor, .color(color))

        XCTAssertNotNil(view.backgroundColor)
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: patch.patchID)
        )
        XCTAssertTrue(view.backgroundColor?.isEqual(UIColor.black) == true)
    }

    @MainActor
    func testViewAndLayerPatchesApplyAndClearTogether() async throws {
        let view = UIView()
        view.alpha = 1
        view.backgroundColor = nil
        view.layer.cornerRadius = 0
        view.layer.borderWidth = 0
        view.layer.shadowOpacity = 0
        view.layer.shadowRadius = 0
        view.layer.shadowOffset = .zero
        let originalBorderColor = view.layer.borderColor
        let originalShadowColor = view.layer.shadowColor
        let (service, nodeID) = makeService(object: view)
        let red = RuntimeColor(colorSpace: "srgb", red: 1, green: 0, blue: 0, alpha: 1)

        _ = try await apply(service, nodeID, .alpha, .number(0.5))
        _ = try await apply(service, nodeID, .backgroundColor, .color(red))
        _ = try await apply(service, nodeID, .cornerRadius, .number(8))
        _ = try await apply(service, nodeID, .borderWidth, .number(2))
        _ = try await apply(service, nodeID, .borderColor, .color(red))
        _ = try await apply(service, nodeID, .shadowColor, .color(red))
        _ = try await apply(service, nodeID, .shadowOpacity, .number(0.8))
        _ = try await apply(service, nodeID, .shadowRadius, .number(4))
        _ = try await apply(
            service,
            nodeID,
            .shadowOffset,
            .vector(RuntimeVector(dx: 3, dy: -2, unit: .logical))
        )

        XCTAssertEqual(view.alpha, 0.5, accuracy: 0.001)
        XCTAssertTrue(view.backgroundColor?.isEqual(UIColor.red) == true)
        XCTAssertEqual(view.layer.cornerRadius, 8)
        XCTAssertEqual(view.layer.borderWidth, 2)
        XCTAssertEqual(view.layer.shadowOpacity, 0.8, accuracy: 0.001)
        XCTAssertEqual(view.layer.shadowRadius, 4)
        XCTAssertEqual(view.layer.shadowOffset, CGSize(width: 3, height: -2))

        let clear = try await service.clearAttributePatches()
        XCTAssertEqual(clear.revertedPatchIDs.count, 9)
        XCTAssertEqual(view.alpha, 1, accuracy: 0.001)
        XCTAssertNil(view.backgroundColor)
        XCTAssertEqual(view.layer.cornerRadius, 0)
        XCTAssertEqual(view.layer.borderWidth, 0)
        XCTAssertEqual(view.layer.borderColor, originalBorderColor)
        XCTAssertEqual(view.layer.shadowColor, originalShadowColor)
        XCTAssertEqual(view.layer.shadowOpacity, 0)
        XCTAssertEqual(view.layer.shadowRadius, 0)
        XCTAssertEqual(view.layer.shadowOffset, .zero)
    }

    @MainActor
    func testShadowOffsetComponentsComposeWhileFullOffsetConflicts() async throws {
        let view = UIView()
        view.layer.shadowOffset = CGSize(width: 1, height: 2)
        let (service, nodeID) = makeService(object: view)

        let widthPatch = try await apply(
            service,
            nodeID,
            .shadowOffsetWidth,
            .number(3)
        )
        let heightPatch = try await apply(
            service,
            nodeID,
            .shadowOffsetHeight,
            .number(4)
        )

        XCTAssertEqual(view.layer.shadowOffset, CGSize(width: 3, height: 4))
        do {
            _ = try await apply(
                service,
                nodeID,
                .shadowOffset,
                .vector(RuntimeVector(dx: 5, dy: 6, unit: .logical))
            )
            XCTFail("Overlapping full-offset and component patches must be rejected")
        } catch let error as RuntimeError {
            XCTAssertEqual(error.code, .patchConflict)
        }

        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: widthPatch.patchID)
        )
        XCTAssertEqual(view.layer.shadowOffset, CGSize(width: 1, height: 4))
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: heightPatch.patchID)
        )
        XCTAssertEqual(view.layer.shadowOffset, CGSize(width: 1, height: 2))
    }

    @MainActor
    func testViewAndLayerNodesSharePatchForSameUnderlyingProperty() async throws {
        let registry = RuntimeNodeRegistry()
        let view = UIView()
        let viewNodeID = registry.nodeID(for: view)
        let layerNodeID = registry.nodeID(for: view.layer)
        let service = RuntimeAttributePatchService(
            nodeRegistry: registry,
            mutator: UIKitRuntimeAttributeMutator()
        )

        let first = try await apply(service, viewNodeID, .cornerRadius, .number(8))
        let second = try await apply(service, layerNodeID, .cornerRadius, .number(12))

        XCTAssertEqual(second.patchID, first.patchID)
        XCTAssertEqual(second.originalValue, .number(0))
        let list = await service.activeAttributePatches()
        XCTAssertEqual(list.patches, [second])
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: second.patchID)
        )
        XCTAssertEqual(view.layer.cornerRadius, 0)
    }

    @MainActor
    func testConstraintPatchRequiresUniqueIdentifierAndRestoresConstant() async throws {
        let view = UIView()
        let constraint = view.widthAnchor.constraint(equalToConstant: 100)
        constraint.identifier = "cardWidth"
        constraint.isActive = true
        let (service, nodeID) = makeService(object: view)
        let attribute = try RuntimeAttributeIdentifier(
            rawValue: "ios.autoLayout.constraint.cardWidth.constant"
        )

        let patch = try await apply(
            service,
            nodeID,
            attribute,
            .number(160)
        )

        XCTAssertEqual(constraint.constant, 160)
        XCTAssertEqual(patch.originalValue, .number(100))
        _ = try await service.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(patchID: patch.patchID)
        )
        XCTAssertEqual(constraint.constant, 100)
    }

    @MainActor
    private func makeService(
        object: AnyObject
    ) -> (RuntimeAttributePatchService, RuntimeOpaqueIdentifier) {
        let registry = RuntimeNodeRegistry()
        let nodeID = registry.nodeID(for: object)
        return (
            RuntimeAttributePatchService(
                nodeRegistry: registry,
                mutator: UIKitRuntimeAttributeMutator()
            ),
            nodeID
        )
    }

    @MainActor
    private func apply(
        _ service: RuntimeAttributePatchService,
        _ nodeID: RuntimeOpaqueIdentifier,
        _ attribute: RuntimeAttributeIdentifier,
        _ value: RuntimeAttributeValue
    ) async throws -> RuntimeAttributePatch {
        try await service.applyAttributePatch(
            RuntimeApplyAttributePatchParameters(
                nodeID: nodeID,
                attributeIdentifier: attribute,
                value: value
            )
        )
    }

    private func attributedFont(in label: UILabel) -> UIFont? {
        label.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
    }

    private func attributedColor(in label: UILabel) -> UIColor? {
        label.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
    }

    private func attributedKern(in label: UILabel) -> Double? {
        let value = label.attributedText?.attribute(.kern, at: 0, effectiveRange: nil)
        return (value as? NSNumber)?.doubleValue
    }
}
#endif
