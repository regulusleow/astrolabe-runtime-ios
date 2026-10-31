import XCTest
@testable import AstrolabeRuntimeUIKit

/// Pure read-policy tests; no UIView, application, or UI runtime is created.
final class UIKitSemanticReadPolicyTests: XCTestCase {
    func testTextLayoutAcceptsOnlyVerifiedVersionsAndDeviceKinds() {
        for physical in [false, true] {
            XCTAssertTrue(SwiftUITextMetadataPolicy.supportsLayout(major: 27, minor: 0, physicalDevice: physical))
            for (major, minor) in [(26, 2), (27, 1), (27, 3), (28, 0)] {
                XCTAssertFalse(SwiftUITextMetadataPolicy.supportsLayout(major: major, minor: minor, physicalDevice: physical))
            }
        }
        XCTAssertTrue(SwiftUITextMetadataPolicy.supportsLayout(major: 27, minor: 2, physicalDevice: true))
        XCTAssertFalse(SwiftUITextMetadataPolicy.supportsLayout(major: 27, minor: 2, physicalDevice: false))
    }

    func testEnvironmentColorBoxAllowsOnlyProvenPureColorProviders() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ColorBox<SwiftUI.SystemColorType>"))
        XCTAssertTrue(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ColorBox<SwiftUI.ResolvedColorProvider>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isColorBox("Other.ColorBox<SwiftUI.ResolvedColorProvider>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ColorBox<Other.ResolvedColorProvider>"))
        XCTAssertTrue(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ColorBox<SwiftUI.Color.OpacityColor>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isColorBox("Other.ColorBox<SwiftUI.Color.OpacityColor>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ColorBox<Other.Color.OpacityColor>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ColorBox<SwiftUI.Color.OpacityColor>.Type"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ColorBox<SwiftUI.CustomColorProvider>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ShapeStyleBox<SwiftUI.LinearGradient>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isColorBox("SwiftUI.ColorBox<SwiftUI.ResolvedColorProvider>.Type"))
    }

    func testTintEnvironmentKeyRequiresExactOwnerAndPrivateLayout() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isTintKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1c7b6a3d4).TintKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintKey("Other.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).TintKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintKey("SwiftUI.EnvironmentPropertyKey<Other.(unknown context at $1).TintKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $notHex).TintKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).ForegroundStyleKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).TintKey>.Type"))
    }

    func testTintStyleBoxRequiresExactOwnerAndPureTintType() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isTintStyleBox("SwiftUI.(unknown context at $1c7b36b5c).ShapeStyleBox<SwiftUI.TintShapeStyle>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintStyleBox("Other.(unknown context at $1).ShapeStyleBox<SwiftUI.TintShapeStyle>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintStyleBox("SwiftUI.(unknown context at $1).ShapeStyleBox<Other.TintShapeStyle>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintStyleBox("SwiftUI.(unknown context at $notHex).ShapeStyleBox<SwiftUI.TintShapeStyle>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintStyleBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.HierarchicalShapeStyle>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isTintStyleBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.TintShapeStyle>.Type"))
    }

    func testHierarchyOffsetBoxRequiresExactOwnerAndErasedStyleBase() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isHierarchyOffsetBox("SwiftUI.(unknown context at $1c7b36b5c).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyOffsetBox("Other.(unknown context at $1).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyOffsetBox("SwiftUI.(unknown context at $1).ShapeStyleBox<Other.OffsetShapeStyle<SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyOffsetBox("SwiftUI.(unknown context at $notHex).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyOffsetBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.SystemColorsStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyOffsetBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.AnyShapeStyle>>.Type"))
    }

    func testHierarchyModifierBoxRequiresExactColorBase() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isHierarchyModifierBox("SwiftUI.(unknown context at $1c7b36b5c).ShapeStyleBox<SwiftUI.HierarchicalShapeStyleModifier<SwiftUI.Color>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyModifierBox("Other.(unknown context at $1).ShapeStyleBox<SwiftUI.HierarchicalShapeStyleModifier<SwiftUI.Color>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyModifierBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.HierarchicalShapeStyleModifier<Other.Color>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyModifierBox("SwiftUI.(unknown context at $notHex).ShapeStyleBox<SwiftUI.HierarchicalShapeStyleModifier<SwiftUI.Color>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyModifierBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.HierarchicalShapeStyleModifier<SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyModifierBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.HierarchicalShapeStyleModifier<SwiftUI.Color>>.Type"))
    }

    func testHierarchyPackBoxRequiresTwoOrThreeErasedStyles() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isHierarchyPackBox("SwiftUI.(unknown context at $1c7b36b5c).ShapeStyleBox<SwiftUI.ShapeStylePair<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>>"))
        XCTAssertTrue(SwiftUITextMetadataPolicy.isHierarchyPackBox("SwiftUI.(unknown context at $1c7b36b5c).ShapeStyleBox<SwiftUI.ShapeStyleTriple<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyPackBox("Other.(unknown context at $1).ShapeStyleBox<SwiftUI.ShapeStylePair<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyPackBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.ShapeStylePair<SwiftUI.AnyShapeStyle, Other.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyPackBox("SwiftUI.(unknown context at $notHex).ShapeStyleBox<SwiftUI.ShapeStylePair<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isHierarchyPackBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.ShapeStylePair<SwiftUI.AnyShapeStyle, SwiftUI.AnyShapeStyle>>.Type"))
    }

    func testDefaultHierarchyBoxRequiresExactSystemColorsBase() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isDefaultHierarchyOffsetBox("SwiftUI.(unknown context at $1c7b36b5c).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.SystemColorsStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isDefaultHierarchyOffsetBox("Other.(unknown context at $1).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.SystemColorsStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isDefaultHierarchyOffsetBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.OffsetShapeStyle<Other.SystemColorsStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isDefaultHierarchyOffsetBox("SwiftUI.(unknown context at $notHex).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.SystemColorsStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isDefaultHierarchyOffsetBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.AnyShapeStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isDefaultHierarchyOffsetBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.ForegroundMaterialStyle>>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isDefaultHierarchyOffsetBox("SwiftUI.(unknown context at $1).ShapeStyleBox<SwiftUI.OffsetShapeStyle<SwiftUI.SystemColorsStyle>>.Type"))
    }

    func testHierarchyLevelsRejectUnprovenRanges() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(1))
        XCTAssertTrue(SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(2))
        for level in [Int.min, -1, 0, 3, Int.max] {
            XCTAssertFalse(SwiftUITextMetadataPolicy.isSupportedHierarchyLevel(level))
        }
    }

    func testExplicitFontPresenceBlocksInheritanceEvenWithoutProjectedFont() {
        var proof = SwiftUITextScopeProof()
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        XCTAssertTrue(proof.canInheritFont)
        proof.recordOriginalFont()
        XCTAssertTrue(proof.canPromote)
        XCTAssertFalse(proof.canInheritFont)
        XCTAssertTrue(proof.canInheritColor)
    }

    func testInheritedFontRequiresExactlyOneCompleteOriginalText() {
        var proof = SwiftUITextScopeProof()
        XCTAssertFalse(proof.canInheritFont)
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        XCTAssertTrue(proof.canInheritFont)
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/1")
        XCTAssertFalse(proof.canInheritFont)

        var unknown = SwiftUITextScopeProof()
        unknown.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        unknown.markUnknownOriginalBranch()
        XCTAssertFalse(unknown.canInheritFont)
    }

    func testFontEnvironmentKeyRequiresExactOwnerAndPrivateLayout() {
        XCTAssertTrue(SwiftUITextMetadataPolicy.isFontKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1c7b625e0).FontKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isFontKey("Other.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).FontKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isFontKey("SwiftUI.EnvironmentPropertyKey<Other.(unknown context at $1).FontKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isFontKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $notHex).FontKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isFontKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).DefaultFontKey>"))
        XCTAssertFalse(SwiftUITextMetadataPolicy.isFontKey("SwiftUI.EnvironmentPropertyKey<SwiftUI.(unknown context at $1).ForegroundStyleKey>"))
    }

    func testExplicitColorPresenceBlocksInheritanceEvenWithoutProjectedColor() {
        var proof = SwiftUITextScopeProof()
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        XCTAssertTrue(proof.canInheritColor)
        proof.recordOriginalColor()
        XCTAssertTrue(proof.canPromote)
        XCTAssertFalse(proof.canInheritColor)
        XCTAssertTrue(proof.canInheritFont)
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
