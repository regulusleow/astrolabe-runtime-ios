import XCTest
@testable import AstrolabeRuntimeUIKit

/// Pure read-policy tests; no UIView, application, or UI runtime is created.
final class UIKitSemanticReadPolicyTests: XCTestCase {
    func testExplicitColorPresenceBlocksInheritanceEvenWithoutProjectedColor() {
        var proof = SwiftUITextScopeProof()
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        XCTAssertTrue(proof.canInheritColor)
        proof.recordOriginalColor()
        XCTAssertTrue(proof.canPromote)
        XCTAssertFalse(proof.canInheritColor)
    }

    func testInheritedColorKeyRejectsLookalikeOwnersAndUnknownPrivateLayouts() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isForegroundStyleKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1c7b46310).ForegroundStyleKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isForegroundStyleKey("Other.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).ForegroundStyleKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isForegroundStyleKey("SwiftUI.EnvironmentPropertyKey<Other.(unknown context at $1).ForegroundStyleKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isForegroundStyleKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $notHex).ForegroundStyleKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isForegroundStyleKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).DefaultForegroundStyleKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isForegroundStyleKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).TintKey>"))
    }

    func testUnknownOriginalFieldInvalidatesSingleTextScope() {
        var proof = SwiftUITextScopeProof()
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        XCTAssertTrue(proof.canPromote)
        XCTAssertFalse(proof.allowsField("futureStorage", permitted: ["verbatim", "anyTextStorage"], isArray: false, isOriginal: true))
        XCTAssertFalse(proof.canPromote)
    }

    func testKnownFieldsAndCachedUnknownDoNotInventOriginalTextScopes() {
        var proof = SwiftUITextScopeProof()
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        XCTAssertTrue(proof.allowsField("storage", permitted: ["storage", "modifiers"], isArray: false, isOriginal: true))
        XCTAssertFalse(proof.allowsField("futureStorage", permitted: ["verbatim"], isArray: false, isOriginal: false))
        XCTAssertTrue(proof.canPromote)
        proof.recordOriginalText(path: "attachmentsStorage/4/texts/0")
        XCTAssertFalse(proof.canPromote)
    }

    func testUnlabeledOriginalFieldIsUnknownUnlessVerifiedArrayElement() {
        var proof = SwiftUITextScopeProof()
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        XCTAssertTrue(proof.allowsField(nil, permitted: [], isArray: true, isOriginal: true))
        XCTAssertTrue(proof.canPromote)
        XCTAssertFalse(proof.allowsField(nil, permitted: ["value"], isArray: false, isOriginal: true))
        XCTAssertFalse(proof.canPromote)
    }

    func testRepeatedReferenceSlotsStillReportOmittedTail() {
        var budget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 2_000)
        XCTAssertTrue(budget.consume(depth: 0))
        XCTAssertTrue(budget.consume(depth: 1))
        XCTAssertEqual(budget.boundedChildCount(2_002), 2_000)
        XCTAssertTrue(budget.truncated)
        XCTAssertEqual(budget.visits, 2)
    }

    func testExactChildSlotAndObjectBoundariesDoNotClaimTruncation() {
        var budget = UIKitSemanticTraversalBudget(maxDepth: 20, maxVisits: 2_000)
        XCTAssertEqual(budget.boundedChildCount(2_000), 2_000)
        for _ in 0..<2_000 { XCTAssertTrue(budget.consume(depth: 0)) }
        XCTAssertFalse(budget.truncated)
        XCTAssertFalse(budget.consume(depth: 0))
        XCTAssertTrue(budget.truncated)
    }

    func testOnlyTwoProvenOptionSetTypesAreLeaves() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isLeaf("SwiftUI.AccessibilityNullableOptionSet<SwiftUI.AccessibilityTraitSet>"))
        XCTAssertTrue(SwiftUITextMetadataPolicy.isLeaf("SwiftUI.AccessibilityNullableOptionSet<SwiftUI.AccessibilityVisibility>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isLeaf("SwiftUI.AccessibilityNullableOptionSet<SwiftUI.Text>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isLeaf("Other.AccessibilityNullableOptionSet<SwiftUI.AccessibilityVisibility>"))
    }

    func testMetadataOmissionRequiresProvenContainerFieldAndExactType() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.AccessibilityNodeAttachmentStorage", field: "modified", type: "Swift.Bool"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.AccessibilityNodeAttachmentStorage", field: "futureText", type: "Swift.Bool"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.Text.Storage", field: "modified", type: "Swift.Bool"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.AccessibilityNodeAttachmentStorage", field: "modified", type: "SwiftUI.Text"))
        XCTAssertTrue(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.AccessibilityProperties.(unknown context at $1).Entry", field: "key", type: "SwiftUI.AccessibilityProperties.LabelKey.Type"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.AccessibilityProperties.(unknown context at $1).Entry", field: "key", type: "SwiftUI.AccessibilityProperties.FutureTextKey.Type"))
        XCTAssertTrue(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.TextLayoutProperties", field: "flags", type: "(extension in SwiftUI):SwiftUI.TextLayoutProperties.(unknown context at $1c7b38184).Flags"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.TextLayoutProperties", field: "flags", type: "(extension in SwiftUI):SwiftUI.TextLayoutProperties.(unknown context at $notHex).Flags"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.TextLayoutProperties", field: "flags", type: "(extension in SwiftUI):SwiftUI.OtherProperties.(unknown context at $1).Flags"))
    }

    func testLocalizedFormattingCanOnlyBeOmittedWhenFalseAndArgumentsEmpty() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.LocalizedStringKey", field: "hasFormatting", type: "Swift.Bool", booleanValue: false))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.LocalizedStringKey", field: "hasFormatting", type: "Swift.Bool", booleanValue: true))
        XCTAssertTrue(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.LocalizedStringKey", field: "arguments", type: "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>", isEmptyCollection: true))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.LocalizedStringKey", field: "arguments", type: "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>", isEmptyCollection: false))
        XCTAssertFalse(SwiftUITextMetadataPolicy.canIgnoreField(container: "SwiftUI.LocalizedStringKey", field: "arguments", type: "Swift.Array<SwiftUI.Text>", isEmptyCollection: true))
        XCTAssertTrue(SwiftUITextMetadataPolicy.localizedKeyHasNoHiddenText(hasFormatting: false, argumentsType: "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>", argumentsAreEmpty: true))
        XCTAssertFalse(SwiftUITextMetadataPolicy.localizedKeyHasNoHiddenText(hasFormatting: nil, argumentsType: "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>", argumentsAreEmpty: true))
        XCTAssertFalse(SwiftUITextMetadataPolicy.localizedKeyHasNoHiddenText(hasFormatting: false, argumentsType: nil, argumentsAreEmpty: true))
        XCTAssertFalse(SwiftUITextMetadataPolicy.localizedKeyHasNoHiddenText(hasFormatting: true, argumentsType: "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>", argumentsAreEmpty: true))
        XCTAssertFalse(SwiftUITextMetadataPolicy.localizedKeyHasNoHiddenText(hasFormatting: false, argumentsType: "Swift.Array<SwiftUI.LocalizedStringKey.FormatArgument>", argumentsAreEmpty: false))
    }
}
