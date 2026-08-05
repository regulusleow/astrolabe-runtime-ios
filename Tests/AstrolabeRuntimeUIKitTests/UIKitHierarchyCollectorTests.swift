//
//  UIKitHierarchyCollectorTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

#if canImport(UIKit)
import AstrolabeRuntimeCore
@testable import AstrolabeRuntimeUIKit
import AstrolabeProtocol
import QuartzCore
import SwiftUI
import UIKit
import XCTest

@MainActor
final class UIKitHierarchyCollectorTests: XCTestCase {
    func testCollectorCapturesDetachedMaskAndEmitsLayerMaskRelation() throws {
        let registry = RuntimeNodeRegistry()
        let collector = makeCollector(nodeRegistry: registry)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 640)
        )
        let maskedView = UIView(
            frame: CGRect(x: 20, y: 40, width: 120, height: 80)
        )
        let mask = CAShapeLayer()
        mask.frame = maskedView.bounds
        maskedView.layer.mask = mask
        window.addSubview(maskedView)

        let snapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )
        let maskNodeID = registry.nodeID(for: mask)
        let maskNode = try XCTUnwrap(
            snapshot.roots.first { $0.nodeID == maskNodeID }
        )
        let ownerNode = try XCTUnwrap(
            flattenedNodes(snapshot.roots[1]).first {
                $0.nodeID == registry.nodeID(for: maskedView.layer)
            }
        )
        let relations = try XCTUnwrap(snapshot.relations)

        XCTAssertEqual(maskNode.runtimeType.name, "CAShapeLayer")
        XCTAssertNil(maskNode.parentID)
        XCTAssertFalse(ownerNode.children.contains { $0.nodeID == maskNodeID })
        XCTAssertTrue(relations.contains {
            $0.type.rawValue == "ios.layer.mask" &&
                $0.sourceNodeID == ownerNode.nodeID &&
                $0.targetNodeID == maskNodeID
        })
    }

    func testCollectorCapturesDetachedMaskLayerSubtreeWithOwnerGeometry() throws {
        let registry = RuntimeNodeRegistry()
        let collector = makeCollector(nodeRegistry: registry)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 640)
        )
        let maskedView = UIView(
            frame: CGRect(x: 20, y: 40, width: 120, height: 80)
        )
        let mask = CALayer()
        mask.frame = CGRect(x: 10, y: 12, width: 60, height: 40)
        let maskSublayer = CALayer()
        maskSublayer.frame = CGRect(x: 5, y: 7, width: 20, height: 10)
        mask.addSublayer(maskSublayer)
        maskedView.layer.mask = mask
        window.addSubview(maskedView)

        let snapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )
        let maskNode = try XCTUnwrap(
            snapshot.roots.first {
                $0.nodeID == registry.nodeID(for: mask)
            }
        )
        let maskSublayerNode = try XCTUnwrap(maskNode.children.first)

        XCTAssertEqual(maskNode.runtimeType.name, "CALayer")
        XCTAssertEqual(maskNode.geometry.frameInScreen.x, 30, accuracy: 0.001)
        XCTAssertEqual(maskNode.geometry.frameInScreen.y, 52, accuracy: 0.001)
        XCTAssertEqual(maskSublayerNode.parentID, maskNode.nodeID)
        XCTAssertEqual(
            maskSublayerNode.nodeID,
            registry.nodeID(for: maskSublayer)
        )
        XCTAssertEqual(
            maskSublayerNode.geometry.frameInScreen.x,
            35,
            accuracy: 0.001
        )
        XCTAssertEqual(
            maskSublayerNode.geometry.frameInScreen.y,
            59,
            accuracy: 0.001
        )
    }

    func testCollectorCapturesDetachedMaskWithoutRelationProviders() throws {
        let registry = RuntimeNodeRegistry()
        let collector = makeCollector(
            nodeRegistry: registry,
            relationProviderRegistry: UIKitRuntimeNodeRelationProviderRegistry(
                providers: []
            )
        )
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 640)
        )
        let maskedView = UIView(
            frame: CGRect(x: 20, y: 40, width: 120, height: 80)
        )
        let mask = CALayer()
        mask.frame = maskedView.bounds
        maskedView.layer.mask = mask
        window.addSubview(maskedView)

        let snapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )

        XCTAssertTrue(snapshot.roots.contains {
            $0.nodeID == registry.nodeID(for: mask)
        })
        XCTAssertEqual(snapshot.relations, [])
    }

    func testCollectorEmitsViewBackingLayerRelationsForCapturedNodes() throws {
        let registry = RuntimeNodeRegistry()
        let collector = makeCollector(nodeRegistry: registry)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 640)
        )
        let label = UILabel(frame: CGRect(x: 16, y: 20, width: 120, height: 24))
        window.addSubview(label)

        let snapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )
        let relations = try XCTUnwrap(snapshot.relations)

        XCTAssertEqual(relations.count, 2)
        XCTAssertEqual(
            relations.map(\.type.rawValue),
            ["ios.view.backingLayer", "ios.view.backingLayer"]
        )
        XCTAssertEqual(relations[0].sourceNodeID, registry.nodeID(for: window))
        XCTAssertEqual(relations[0].targetNodeID, registry.nodeID(for: window.layer))
        XCTAssertEqual(relations[1].sourceNodeID, registry.nodeID(for: label))
        XCTAssertEqual(relations[1].targetNodeID, registry.nodeID(for: label.layer))
        XCTAssertFalse(relations.contains {
            $0.sourceNodeID == registry.nodeID(for: label.layer) &&
                $0.targetNodeID == registry.nodeID(for: label)
        })
    }

    func testCollectorPreservesRootsWhenRelationProvidersAreEmpty() throws {
        let registry = RuntimeNodeRegistry()
        let collector = makeCollector(
            nodeRegistry: registry,
            relationProviderRegistry: UIKitRuntimeNodeRelationProviderRegistry(
                providers: []
            )
        )
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 640)
        )

        let snapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )

        XCTAssertEqual(snapshot.roots.count, 2)
        XCTAssertEqual(snapshot.relations, [])
    }

    func testCollectorCapturesViewAndLayerTreesWithStableIDs() throws {
        let registry = RuntimeNodeRegistry()
        let colorMapper = UIKitRuntimeColorMapper()
        let accessibilityMapper = UIKitRuntimeAccessibilityMapper()
        let attributeCollectorRegistry = UIKitRuntimeAttributeCollectorRegistry(
            nodeRegistry: registry,
            colorMapper: colorMapper,
            accessibilityMapper: accessibilityMapper
        )
        let collector = UIKitHierarchyCollector(
            nodeRegistry: registry,
            targetIdentifier: testOpaqueIdentifier("target"),
            screenMapper: UIKitRuntimeScreenMapper(),
            colorMapper: colorMapper,
            accessibilityMapper: accessibilityMapper,
            attributeCollectorRegistry: attributeCollectorRegistry
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false

        let label = UILabel(frame: CGRect(x: 16, y: 20, width: 120, height: 24))
        label.text = "Hello"
        label.backgroundColor = .red
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "title"
        label.accessibilityLabel = "Hello"
        label.accessibilityTraits = .staticText
        window.addSubview(label)

        let hiddenContainer = UIView(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        hiddenContainer.isHidden = true
        let hiddenLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        hiddenLabel.text = "Hidden"
        hiddenContainer.addSubview(hiddenLabel)
        window.addSubview(hiddenContainer)

        let clippedContainer = UIView(frame: CGRect(x: 0, y: 240, width: 100, height: 100))
        clippedContainer.clipsToBounds = true
        let clippedLabel = UILabel(frame: CGRect(x: 120, y: 0, width: 80, height: 20))
        clippedLabel.text = "Clipped"
        clippedContainer.addSubview(clippedLabel)
        window.addSubview(clippedContainer)

        let secureTextField = UITextField(
            frame: CGRect(x: 16, y: 360, width: 160, height: 40)
        )
        secureTextField.text = "secret"
        secureTextField.placeholder = "Password"
        secureTextField.isSecureTextEntry = true
        secureTextField.accessibilityValue = "secret"
        window.addSubview(secureTextField)

        let customLayer = CALayer()
        customLayer.frame = CGRect(x: 10, y: 200, width: 30, height: 40)
        customLayer.backgroundColor = UIColor.blue.cgColor
        window.layer.addSublayer(customLayer)

        let firstSnapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )
        let secondSnapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 101
        )

        XCTAssertEqual(firstSnapshot.roots.count, 2)
        XCTAssertEqual(firstSnapshot.roots.map(\.role), ["window", "layer"])
        XCTAssertEqual(
            firstSnapshot.roots.map(\.nodeID),
            secondSnapshot.roots.map(\.nodeID)
        )

        let viewRoot = try XCTUnwrap(firstSnapshot.roots.first)
        XCTAssertEqual(viewRoot.runtimeType.name, "UIWindow")
        XCTAssertEqual(viewRoot.children.count, 4)

        let labelNode = viewRoot.children[0]
        XCTAssertEqual(labelNode.runtimeType.name, "UILabel")
        XCTAssertEqual(labelNode.text, "Hello")
        XCTAssertEqual(labelNode.parentID, viewRoot.nodeID)
        XCTAssertTrue(labelNode.visibility.onscreen)
        XCTAssertNotNil(labelNode.backgroundColor)
        XCTAssertEqual(labelNode.accessibility?.identifier, "title")
        XCTAssertTrue(
            labelNode.availableDetailCategories.contains {
                $0.rawValue == RuntimeAttributeCategory.label.rawValue
            }
        )
        XCTAssertEqual(
            labelNode.availableDetailCategories.map(\.rawValue),
            attributeCollectorRegistry.sections(for: label)
                .map(\.category.rawValue)
        )

        let hiddenLabelNode = viewRoot.children[1].children[0]
        XCTAssertTrue(hiddenLabelNode.visibility.hiddenByAncestor)
        XCTAssertFalse(hiddenLabelNode.visibility.onscreen)

        let clippedLabelNode = viewRoot.children[2].children[0]
        XCTAssertFalse(clippedLabelNode.visibility.hiddenByAncestor)
        XCTAssertFalse(clippedLabelNode.visibility.onscreen)

        let secureTextFieldNode = viewRoot.children[3]
        XCTAssertEqual(secureTextFieldNode.text, "Password")
        XCTAssertNotEqual(secureTextFieldNode.text, secureTextField.text)
        XCTAssertNil(secureTextFieldNode.accessibility?.value)

        let layerRoot = firstSnapshot.roots[1]
        let customLayerID = registry.nodeID(for: customLayer)
        let customLayerNode = try XCTUnwrap(
            flattenedNodes(layerRoot).first { $0.nodeID == customLayerID }
        )
        XCTAssertEqual(customLayerNode.role, "layer")
        XCTAssertNotNil(customLayerNode.backgroundColor)
        XCTAssertTrue(registry.object(for: labelNode.nodeID) === label)
    }

    func testCollectorVisibilityUsesScreenAndScrollViewportIntersection() throws {
        let registry = RuntimeNodeRegistry()
        let collector = makeCollector(nodeRegistry: registry)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.isHidden = false

        let scrollView = UIScrollView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 100, height: 300)
        let clippedLabel = UILabel(
            frame: CGRect(x: 0, y: 120, width: 80, height: 20)
        )
        let partiallyVisibleLabel = UILabel(
            frame: CGRect(x: 0, y: 90, width: 80, height: 20)
        )
        scrollView.addSubview(clippedLabel)
        scrollView.addSubview(partiallyVisibleLabel)
        window.addSubview(scrollView)

        let offscreenLabel = UILabel(
            frame: CGRect(
                x: window.screen.bounds.maxX + 20,
                y: 0,
                width: 80,
                height: 20
            )
        )
        window.addSubview(offscreenLabel)

        let snapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )
        let viewRoot = try XCTUnwrap(snapshot.roots.first)
        let nodes = flattenedNodes(viewRoot)
        let clippedNode = try XCTUnwrap(
            nodes.first { $0.nodeID == registry.nodeID(for: clippedLabel) }
        )
        let partiallyVisibleNode = try XCTUnwrap(
            nodes.first { $0.nodeID == registry.nodeID(for: partiallyVisibleLabel) }
        )
        let offscreenNode = try XCTUnwrap(
            nodes.first { $0.nodeID == registry.nodeID(for: offscreenLabel) }
        )

        XCTAssertFalse(clippedNode.visibility.hidden)
        XCTAssertFalse(clippedNode.visibility.hiddenByAncestor)
        XCTAssertFalse(clippedNode.visibility.onscreen)
        XCTAssertTrue(partiallyVisibleNode.visibility.onscreen)
        XCTAssertFalse(offscreenNode.visibility.onscreen)
    }

    func testCollectorCapturesMultipleWindowsAndUIKitContainerMatrix() throws {
        let registry = RuntimeNodeRegistry()
        let collector = makeCollector(nodeRegistry: registry)
        let compactWindow = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 640)
        )
        compactWindow.isHidden = false
        let tableView = UITableView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 250, width: 320, height: 120),
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        let textField = UITextField(
            frame: CGRect(x: 16, y: 390, width: 200, height: 40)
        )
        textField.text = "Editable text"
        let imageView = UIImageView(
            frame: CGRect(x: 16, y: 450, width: 40, height: 40)
        )
        imageView.image = UIGraphicsImageRenderer(
            size: CGSize(width: 20, height: 20)
        ).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        compactWindow.addSubview(tableView)
        compactWindow.addSubview(collectionView)
        compactWindow.addSubview(textField)
        compactWindow.addSubview(imageView)

        let largeWindow = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 430, height: 932)
        )
        largeWindow.isHidden = false
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 20, y: 20, width: 100, height: 44)
        button.setTitle("Selected", for: .normal)
        button.isSelected = true
        largeWindow.addSubview(button)

        let snapshot = try collector.capture(
            windows: [compactWindow, largeWindow],
            screen: compactWindow.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )

        XCTAssertEqual(snapshot.roots.count, 4)
        XCTAssertEqual(snapshot.roots[0].geometry.bounds.width, 320)
        XCTAssertEqual(snapshot.roots[1].geometry.bounds.width, 430)
        XCTAssertEqual(
            snapshot.roots[0].children.map(\.runtimeType.name),
            ["UITableView", "UICollectionView", "UITextField", "UIImageView"]
        )
        XCTAssertEqual(
            snapshot.roots[1].children.first?.runtimeType.name,
            "UIButton"
        )
    }

    func testCollectorCapturesSwiftUIHostingHierarchy() throws {
        let registry = RuntimeNodeRegistry()
        let collector = makeCollector(nodeRegistry: registry)
        let hostingController = UIHostingController(
            rootView: Text("SwiftUI Matrix")
                .padding(12)
                .background(Color.red)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.isHidden = false
        hostingController.view.frame = window.bounds
        hostingController.view.layoutIfNeeded()
        let hostingViewID = registry.nodeID(for: hostingController.view)

        let snapshot = try collector.capture(
            windows: [window],
            screen: window.screen,
            interfaceOrientation: "portrait",
            capturedAtUnixTime: 100
        )

        let viewNodes = flattenedNodes(snapshot.roots[0])
        XCTAssertTrue(viewNodes.contains { $0.nodeID == hostingViewID })
        XCTAssertGreaterThan(viewNodes.count, 1)
    }

    private func makeCollector(
        nodeRegistry: RuntimeNodeRegistry,
        relationProviderRegistry: UIKitRuntimeNodeRelationProviderRegistry = .init()
    ) -> UIKitHierarchyCollector {
        let colorMapper = UIKitRuntimeColorMapper()
        let accessibilityMapper = UIKitRuntimeAccessibilityMapper()
        return UIKitHierarchyCollector(
            nodeRegistry: nodeRegistry,
            targetIdentifier: testOpaqueIdentifier("target"),
            screenMapper: UIKitRuntimeScreenMapper(),
            colorMapper: colorMapper,
            accessibilityMapper: accessibilityMapper,
            attributeCollectorRegistry: UIKitRuntimeAttributeCollectorRegistry(
                nodeRegistry: nodeRegistry,
                colorMapper: colorMapper,
                accessibilityMapper: accessibilityMapper
            ),
            relationProviderRegistry: relationProviderRegistry
        )
    }

    private func flattenedNodes(_ root: RuntimeNode) -> [RuntimeNode] {
        [root] + root.children.flatMap(flattenedNodes)
    }
}

private func testOpaqueIdentifier(
    _ rawValue: String
) -> RuntimeOpaqueIdentifier {
    do {
        return try RuntimeOpaqueIdentifier(rawValue: rawValue)
    } catch {
        preconditionFailure("Invalid node identifier in test: \(rawValue)")
    }
}
#endif
