import AstrolabeProtocol
import XCTest
@testable import AstrolabeRuntimeUIKit

/// Pure value projection; no UI object, application, or simulator is created.
final class UIKitSemanticAccessibilityFactsTests: XCTestCase {
    func testLongTypeNamesRemainInsideTheSemanticWireContract() throws {
        for name in ["SwiftUI.AccessibilityNode", String(repeating: "T", count: 512),
                     String(repeating: "类型", count: 300)] {
            let bounded = UIKitSemanticAccessibilityFacts.runtimeTypeName(name)
            XCTAssertEqual(bounded, String(name.prefix(512)))
            let node = try RuntimeSemanticNode(nodeID: .init(rawValue: "semantic-1"), parentID: nil,
                siblingIndex: 0, role: "container", runtimeType: .init(name: bounded, ancestors: []),
                availableDetailCategories: [], children: [])
            XCTAssertEqual(try JSONDecoder().decode(RuntimeSemanticNode.self, from: JSONEncoder().encode(node)), node)
        }
    }

    func testRolesUsePublicTraitsAndNativeEvidence() {
        let examples: [(traits: [String], native: String?, expected: String)] = [
            (["button"], nil, "button"),
            (["staticText"], nil, "text"),
            (["image"], nil, "image"),
            (["image", "button"], nil, "button"),
            (["adjustable"], nil, "control"),
            (["toggleButton", "button"], nil, "control"),
            (["searchField"], nil, "input"),
            (["keyboardKey"], nil, "button"),
            ([], "input", "input"),
            ([], "scroll", "scroll"),
            ([], "list", "list"),
            ([], "window", "window"),
            ([], "control", "control"),
            ([], nil, "container"),
            (["futureTrait"], nil, "container")
        ]
        for example in examples {
            XCTAssertEqual(UIKitSemanticAccessibilityFacts.role(traits: example.traits, nativeRole: example.native), example.expected)
        }
    }

    func testNativeInputEvidenceAndSpecificAXRolesHavePriority() {
        XCTAssertEqual(UIKitSemanticAccessibilityFacts.role(traits: ["staticText"], nativeRole: "input"), "input")
        XCTAssertEqual(UIKitSemanticAccessibilityFacts.role(traits: ["button"], nativeRole: "control"), "button")
    }

    func testFrozenDetailRetainsPublicAXValueAndTraits() throws {
        let info = RuntimeAccessibility(element: true, identifier: "sample.input", label: "输入", value: "值 A", hint: "提示", traits: ["selected", "notEnabled"])
        let section = try XCTUnwrap(UIKitSemanticAccessibilityFacts.section(for: info))
        XCTAssertEqual(section.category.rawValue, "ios.accessibility")
        XCTAssertEqual(section.attributes.map(\.identifier.rawValue), [
            "ios.accessibility.element", "ios.accessibility.identifier", "ios.accessibility.label",
            "ios.accessibility.value", "ios.accessibility.hint", "ios.accessibility.traits"
        ])
        XCTAssertEqual(section.attributes.map(\.value), [
            .boolean(true), .string("sample.input"), .string("输入"), .string("值 A"),
            .string("提示"), .stringList(["selected", "notEnabled"])
        ])
    }

    func testRedactedValueIsNotRecoveredFromOtherFields() throws {
        let info = RuntimeAccessibility(element: true, identifier: nil, label: "安全输入", value: nil, hint: nil, traits: [])
        let section = try XCTUnwrap(UIKitSemanticAccessibilityFacts.section(for: info))
        XCTAssertEqual(section.attributes.map(\.identifier.rawValue), ["ios.accessibility.element", "ios.accessibility.label"])
        XCTAssertNil(try UIKitSemanticAccessibilityFacts.section(for: nil))
    }
}
