//
//  UIKitRuntimeNodeDetailPayloadProviderTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeRuntimeCore
@testable import AstrolabeRuntimeUIKit
import AstrolabeProtocol
import QuartzCore
import UIKit
import XCTest

@MainActor
final class UIKitRuntimeNodeDetailPayloadProviderTests: XCTestCase {
    func testProviderCollectsButtonAndAutoLayoutAttributes() async throws {
        let registry = RuntimeNodeRegistry()
        let provider = UIKitRuntimeNodeDetailProvider(nodeRegistry: registry)
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 4,
            leading: 8,
            bottom: 6,
            trailing: 10
        )
        button.configuration = configuration
        button.setTitle("Save", for: .normal)
        button.isSelected = true
        button.tintAdjustmentMode = .dimmed
        button.layer.cornerRadius = 12
        button.layer.shadowOffset = CGSize(width: 3, height: -4)
        button.accessibilityIdentifier = "saveButton"
        button.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: 120)
        widthConstraint.identifier = "saveButton.width"
        widthConstraint.isActive = true

        let nodeID = registry.nodeID(for: button)
        let detail = try await provider.nodeDetail(for: nodeID)

        XCTAssertEqual(
            detail.sections.map(\.category),
            [.layout, .view, .layer, .accessibility, .control, .button, .autoLayout]
        )
        XCTAssertEqual(value(.buttonTitle, in: detail), .string("Save"))
        XCTAssertEqual(value(.selected, in: detail), .boolean(true))
        XCTAssertEqual(
            value(.tintAdjustmentMode, in: detail),
            .string("dimmed")
        )
        XCTAssertEqual(value(.cornerRadius, in: detail), .number(12))
        XCTAssertEqual(
            value(.shadowOffset, in: detail),
            .vector(RuntimeVector(dx: 3, dy: -4, unit: .logical))
        )
        XCTAssertEqual(value(.shadowOffsetWidth, in: detail), .number(3))
        XCTAssertEqual(value(.shadowOffsetHeight, in: detail), .number(-4))
        XCTAssertEqual(
            value(.accessibilityIdentifier, in: detail),
            .string("saveButton")
        )
        XCTAssertEqual(
            value(.contentInsets, in: detail),
            .insets(
                RuntimeInsets(
                    top: 4,
                    left: 8,
                    bottom: 6,
                    right: 10,
                    unit: .logical
                )
            )
        )
        guard case let .array(constraints)? = value(.constraints, in: detail) else {
            return XCTFail("Expected Auto Layout extension values.")
        }
        let constraint = try XCTUnwrap(
            constraints.compactMap(\.objectValue).first {
                $0["identifier"] == .string("saveButton.width")
            }
        )
        XCTAssertEqual(constraint["firstAttribute"], .string("width"))
        XCTAssertEqual(constraint["constant"], .number(120))
        XCTAssertEqual(
            constraint["firstItem"]?.objectValue?["nodeID"],
            .string(nodeID.rawValue)
        )
    }

    func testProviderRedactsSecureTextAndCollectsSpecializedViews() async throws {
        let registry = RuntimeNodeRegistry()
        let provider = UIKitRuntimeNodeDetailProvider(nodeRegistry: registry)

        let textField = UITextField()
        textField.text = "secret"
        textField.placeholder = "Password"
        textField.isSecureTextEntry = true
        textField.keyboardType = .asciiCapable
        textField.accessibilityValue = "secret"
        let textDetail = try await provider.nodeDetail(
            for: registry.nodeID(for: textField)
        )
        XCTAssertNil(value(.inputText, in: textDetail))
        XCTAssertEqual(value(.placeholder, in: textDetail), .string("Password"))
        XCTAssertEqual(value(.isSecureTextEntry, in: textDetail), .boolean(true))
        XCTAssertEqual(value(.keyboardType, in: textDetail), .string("asciiCapable"))
        XCTAssertNil(value(.accessibilityValue, in: textDetail))

        let searchBar = UISearchBar()
        searchBar.text = "private query"
        searchBar.placeholder = "Search"
        searchBar.searchTextField.isSecureTextEntry = true
        let searchDetail = try await provider.nodeDetail(
            for: registry.nodeID(for: searchBar)
        )
        XCTAssertNil(value(.inputText, in: searchDetail))
        XCTAssertEqual(value(.placeholder, in: searchDetail), .string("Search"))

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        let imageView = UIImageView(image: image)
        let imageDetail = try await provider.nodeDetail(
            for: registry.nodeID(for: imageView)
        )
        XCTAssertEqual(value(.imagePresent, in: imageDetail), .boolean(true))
        XCTAssertEqual(
            value(.imageSize, in: imageDetail),
            .size(RuntimeMeasuredSize(width: 20, height: 30, unit: .logical))
        )

        let scrollView = UIScrollView()
        scrollView.contentSize = CGSize(width: 400, height: 800)
        scrollView.contentOffset = CGPoint(x: 12, y: 34)
        scrollView.isPagingEnabled = true
        let scrollDetail = try await provider.nodeDetail(
            for: registry.nodeID(for: scrollView)
        )
        XCTAssertEqual(
            value(.contentSize, in: scrollDetail),
            .size(RuntimeMeasuredSize(width: 400, height: 800, unit: .logical))
        )
        XCTAssertEqual(
            value(.contentOffset, in: scrollDetail),
            .point(
                RuntimeCoordinatePoint(
                    x: 12,
                    y: 34,
                    coordinateSpace: .local,
                    unit: .logical
                )
            )
        )
        XCTAssertEqual(value(.isPagingEnabled, in: scrollDetail), .boolean(true))

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = 9
        let stackDetail = try await provider.nodeDetail(
            for: registry.nodeID(for: stackView)
        )
        XCTAssertEqual(value(.stackAxis, in: stackDetail), .string("vertical"))
        XCTAssertEqual(value(.stackAlignment, in: stackDetail), .string("center"))
        XCTAssertEqual(
            value(.stackDistribution, in: stackDetail),
            .string("equalSpacing")
        )
        XCTAssertEqual(value(.stackSpacing, in: stackDetail), .number(9))
    }

    func testProviderCollectsStandaloneLayerAndRejectsUnknownNode() async throws {
        let registry = RuntimeNodeRegistry()
        let provider = UIKitRuntimeNodeDetailProvider(nodeRegistry: registry)
        let layer = CALayer()
        layer.frame = CGRect(x: 1, y: 2, width: 30, height: 40)
        layer.opacity = 0.5
        layer.backgroundColor = UIColor.blue.cgColor
        let nodeID = registry.nodeID(for: layer)

        let detail = try await provider.nodeDetail(for: nodeID)
        XCTAssertEqual(detail.sections.map(\.category), [.layout, .layer])
        XCTAssertEqual(value(.layerOpacity, in: detail), .number(0.5))
        XCTAssertNotNil(value(.layerBackgroundColor, in: detail))

        let unknownNodeID = try RuntimeOpaqueIdentifier(rawValue: "unknown-node")
        do {
            _ = try await provider.nodeDetail(for: unknownNodeID)
            XCTFail("Expected unknown node failure.")
        } catch {
            XCTAssertEqual((error as? RuntimeError)?.code, .nodeNotFound)
        }
    }

    func testProviderCollectsGradientLayerAttributes() async throws {
        let registry = RuntimeNodeRegistry()
        let provider = UIKitRuntimeNodeDetailProvider(nodeRegistry: registry)
        let layer = CAGradientLayer()
        let colorSpace = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.sRGB)
        )
        layer.colors = [
            try XCTUnwrap(
                CGColor(
                    colorSpace: colorSpace,
                    components: [1, 0, 0, 1]
                )
            ),
            try XCTUnwrap(
                CGColor(
                    colorSpace: colorSpace,
                    components: [0, 0, 1, 0.5]
                )
            )
        ]
        layer.locations = [0.25, 0.75]
        layer.startPoint = CGPoint(x: 0.1, y: 0.2)
        layer.endPoint = CGPoint(x: 0.8, y: 0.9)
        layer.type = .radial

        let detail = try await provider.nodeDetail(
            for: registry.nodeID(for: layer)
        )

        XCTAssertEqual(
            detail.sections.map(\.category),
            [.layout, .layer, .gradientLayer]
        )
        XCTAssertEqual(
            value(.gradientLayerColors, in: detail),
            .array([
                .object([
                    "colorSpace": .string("srgb"),
                    "red": .number(1),
                    "green": .number(0),
                    "blue": .number(0),
                    "alpha": .number(1)
                ]),
                .object([
                    "colorSpace": .string("srgb"),
                    "red": .number(0),
                    "green": .number(0),
                    "blue": .number(1),
                    "alpha": .number(0.5)
                ])
            ])
        )
        XCTAssertEqual(
            value(.gradientLayerLocations, in: detail),
            .array([.number(0.25), .number(0.75)])
        )
        XCTAssertEqual(
            value(.gradientLayerStartPoint, in: detail),
            .object(["x": .number(0.1), "y": .number(0.2)])
        )
        XCTAssertEqual(
            value(.gradientLayerEndPoint, in: detail),
            .object(["x": .number(0.8), "y": .number(0.9)])
        )
        XCTAssertEqual(
            value(.gradientLayerType, in: detail),
            .string("radial")
        )
    }

    func testProviderDoesNotInferGradientLocations() async throws {
        let registry = RuntimeNodeRegistry()
        let provider = UIKitRuntimeNodeDetailProvider(nodeRegistry: registry)
        let layer = CAGradientLayer()
        layer.locations = nil

        let detail = try await provider.nodeDetail(
            for: registry.nodeID(for: layer)
        )

        XCTAssertNil(value(.gradientLayerLocations, in: detail))
    }

    func testProviderOmitsUndefinedIntrinsicContentSize() async throws {
        let registry = RuntimeNodeRegistry()
        let provider = UIKitRuntimeNodeDetailProvider(nodeRegistry: registry)
        let view = UIView()

        let detail = try await provider.nodeDetail(
            for: registry.nodeID(for: view)
        )

        XCTAssertNil(value(.intrinsicContentSize, in: detail))
    }

    func testProviderDoesNotFlattenMixedAttributedTextStyle() async throws {
        let registry = RuntimeNodeRegistry()
        let provider = UIKitRuntimeNodeDetailProvider(nodeRegistry: registry)
        let label = UILabel()
        let text = NSMutableAttributedString(string: "AB")
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 3
        text.addAttributes(
            [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.red,
                .paragraphStyle: paragraphStyle,
                .kern: 1.5
            ],
            range: NSRange(location: 0, length: 1)
        )
        text.addAttributes(
            [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .foregroundColor: UIColor.blue
            ],
            range: NSRange(location: 1, length: 1)
        )
        label.attributedText = text

        let detail = try await provider.nodeDetail(
            for: registry.nodeID(for: label)
        )

        XCTAssertEqual(value(.text, in: detail), .string("AB"))
        XCTAssertNil(value(.fontName, in: detail))
        XCTAssertNil(value(.fontSize, in: detail))
        XCTAssertNil(value(.textColor, in: detail))
        guard case let .textRuns(runs)? = value(
            .attributedTextRuns,
            in: detail
        ) else {
            return XCTFail("Expected attributed text runs.")
        }
        XCTAssertEqual(runs.map(\.range.location), [0, 1])
        XCTAssertEqual(runs.map(\.range.length), [1, 1])
        XCTAssertEqual(runs.map(\.fontSize?.value), [12, 20])
        XCTAssertEqual(
            try XCTUnwrap(runs.first?.color?.red),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(runs.last?.color?.blue),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            runs.first?.extensions.values["ios.paragraphStyle.alignment"],
            .string("center")
        )
        XCTAssertEqual(
            runs.first?.extensions.values["ios.paragraphStyle.lineSpacing"],
            .number(3)
        )
        XCTAssertEqual(
            runs.first?.extensions.values["ios.textRun.kern"],
            .number(1.5)
        )
    }

    func testProviderOmitsConfiguredSizeWhenLabelAutoShrinks() async throws {
        let registry = RuntimeNodeRegistry()
        let provider = UIKitRuntimeNodeDetailProvider(nodeRegistry: registry)
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "Long text",
            attributes: [.font: UIFont.systemFont(ofSize: 20)]
        )
        label.adjustsFontSizeToFitWidth = true

        let detail = try await provider.nodeDetail(
            for: registry.nodeID(for: label)
        )

        XCTAssertNotNil(value(.fontName, in: detail))
        XCTAssertNil(value(.fontSize, in: detail))
        guard case let .textRuns(runs)? = value(
            .attributedTextRuns,
            in: detail
        ) else {
            return XCTFail("Expected attributed text runs.")
        }
        XCTAssertEqual(runs.count, 1)
        XCTAssertNil(runs.first?.fontSize)
    }

    func testColorMapperProducesNormalizedSRGB() throws {
        let color = try XCTUnwrap(
            UIKitRuntimeColorMapper().color(
                from: UIColor.white,
                traitCollection: UITraitCollection(userInterfaceStyle: .light)
            )
        )

        XCTAssertEqual(color.colorSpace, "srgb")
        XCTAssertTrue((0 ... 1).contains(color.red))
        XCTAssertTrue((0 ... 1).contains(color.green))
        XCTAssertTrue((0 ... 1).contains(color.blue))
        XCTAssertTrue((0 ... 1).contains(color.alpha))
    }

    private func value(
        _ identifier: RuntimeAttributeIdentifier,
        in detail: RuntimeNodeDetailPayload
    ) -> RuntimeAttributeValue? {
        detail.sections
            .flatMap(\.attributes)
            .first { $0.identifier == identifier }?
            .value
    }
}

private extension RuntimeJSONValue {
    var objectValue: [String: RuntimeJSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }
        return value
    }
}
#endif
