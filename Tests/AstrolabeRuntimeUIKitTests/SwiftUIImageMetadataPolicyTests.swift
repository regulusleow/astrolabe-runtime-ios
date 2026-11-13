import XCTest
@testable import AstrolabeRuntimeUIKit

/// Pure source-selection and validation rules; no image or UI is constructed.
final class SwiftUIImageMetadataPolicyTests: XCTestCase {
    func testOnlyExactVerifiedProviderTypesAreAccepted() {
        let cases: [(String, SwiftUIImageMetadataPolicy.ProviderKind)] = [
            ("SwiftUI.ImageProviderBox<SwiftUI.Image.NamedImageProvider>", .named),
            ("SwiftUI.ImageProviderBox<__C.UIImage>", .uiImage),
            ("SwiftUI.ImageProviderBox<SwiftUI.Image.ResizableProvider>", .resizable),
            ("SwiftUI.ImageProviderBox<SwiftUI.Image.(unknown context at $1c7b42734).CGImageProvider>", .cgImage),
            ("SwiftUI.ImageProviderBox<SwiftUI.Image.(unknown context at $1c7b42d80).RenderingModeProvider>", .renderingMode),
            ("SwiftUI.ImageProviderBox<(extension in SwiftUI):SwiftUI.Image.(unknown context at $1c7b3d054).SymbolRenderingOptionsProvider>", .symbolOptions)
        ]
        for (type, kind) in cases { XCTAssertEqual(SwiftUIImageMetadataPolicy.providerKind(type), kind) }
        for type in ["Other.ImageProviderBox<SwiftUI.Image.NamedImageProvider>",
                     "SwiftUI.ImageProviderBox<Other.Image.NamedImageProvider>",
                     "SwiftUI.ImageProviderBox<SwiftUI.Image.(unknown context at $notHex).CGImageProvider>",
                     "SwiftUI.ImageProviderBox<SwiftUI.Image.ResizableProvider>.Type",
                     "SwiftUI.ImageProviderBox<SwiftUI.Image.UnknownProvider>"] {
            XCTAssertNil(SwiftUIImageMetadataPolicy.providerKind(type))
        }
    }

    func testImageKeyDuplicatesAndExplicitEmptySourcesAreNotMerged() {
        XCTAssertTrue(SwiftUIImageMetadataPolicy.isSingleOriginalImage([1]))
        for counts in [[], [0], [2], [1, 1], [1, 0], [0, 1]] {
            XCTAssertFalse(SwiftUIImageMetadataPolicy.isSingleOriginalImage(counts))
        }
    }

    func testSourceSizesAreFiniteWithoutInventingPixelScaleEquality() {
        XCTAssertTrue(SwiftUIImageMetadataPolicy.validSize(width: 19, height: 20.3333333333, scale: 3))
        XCTAssertTrue(SwiftUIImageMetadataPolicy.validSize(width: 47, height: 53, scale: 1))
        XCTAssertTrue(SwiftUIImageMetadataPolicy.validSize(width: 0, height: 0, scale: 1))
        for values in [(-1.0, 12.0, 2.0), (24, -1, 2), (24, 12, 0), (24, 12, -1),
                       (.nan, 12, 2), (24, .infinity, 2), (24, 12, .nan), (Double.greatestFiniteMagnitude, 12, 2)] {
            XCTAssertFalse(SwiftUIImageMetadataPolicy.validSize(width: values.0, height: values.1, scale: values.2))
        }
    }

    func testInsetsRequireExactlyFourFiniteNonnegativeSourceValues() {
        XCTAssertTrue(SwiftUIImageMetadataPolicy.validInsets([1, 2, 1, 2]))
        XCTAssertTrue(SwiftUIImageMetadataPolicy.validInsets([0, 0, 0, 0]))
        for values in [[], [1], [1, 2, 1, 2, 3], [-1, 0, 0, 0], [.nan, 0, 0, 0], [0, .infinity, 0, 0]] {
            XCTAssertFalse(SwiftUIImageMetadataPolicy.validInsets(values))
        }
    }

    func testFourWrappersAreAllowedButTheNextIsRefused() {
        XCTAssertTrue(SwiftUIImageMetadataPolicy.validWrapperCount(0))
        XCTAssertTrue(SwiftUIImageMetadataPolicy.validWrapperCount(4))
        XCTAssertFalse(SwiftUIImageMetadataPolicy.validWrapperCount(5))
        XCTAssertFalse(SwiftUIImageMetadataPolicy.validWrapperCount(-1))
    }

    func testUnverifiedPlatformsDoNotUseTheImageLayout() {
        XCTAssertTrue(SwiftUIImageMetadataPolicy.supportsLayout(major: 27, minor: 0, simulator: true))
        XCTAssertTrue(SwiftUIImageMetadataPolicy.supportsLayout(major: 27, minor: 0, simulator: false))
        for values in [(27, 1, false), (27, 2, true), (27, 2, false), (26, 0, true), (28, 0, true)] {
            XCTAssertFalse(SwiftUIImageMetadataPolicy.supportsLayout(major: values.0, minor: values.1, simulator: values.2))
        }
    }
}
