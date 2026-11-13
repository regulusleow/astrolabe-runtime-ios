import AstrolabeProtocol
import Foundation
import XCTest
@testable import AstrolabeRuntimeUIKit

/// Pure contract/promotion rules; no UIKit or running UI is created.
final class SwiftUITextRunPolicyTests: XCTestCase {
    func testSourceRunsPreserveScalarBoundariesInsideCombinedCharacters() {
        for (source, splitOffset, expected) in [
            ("Ae\u{301}Z", 2, ["Ae", "\u{301}Z"]),
            ("👩\u{200D}💻", 1, ["👩", "\u{200D}💻"])
        ] {
            var attributed = AttributedString(source)
            let split = attributed.unicodeScalars.index(attributed.startIndex, offsetBy: splitOffset)
            attributed[attributed.startIndex..<split].link = URL(string: "https://example.com")
            let projected = attributed.runs.map { SwiftUITextRunPolicy.sourceText(in: attributed, range: $0.range) }
            XCTAssertEqual(projected, expected)
            XCTAssertEqual(projected.joined(), source)
            var location: Int64 = 0
            let runs = projected.map { text -> RuntimeTextRun in
                defer { location += Int64(text.utf16.count) }
                return run(text, location: location)
            }
            XCTAssertTrue(SwiftUITextRunPolicy.valid(runs))
            XCTAssertEqual(runs.map(\.range.length), expected.map { Int64($0.utf16.count) })
        }
    }

    func testRelativeForegroundCannotUseEnvironmentAfterTextOverride() {
        XCTAssertTrue(SwiftUITextRunPolicy.canUseEnvironmentForeground(path: nil))
        XCTAssertTrue(SwiftUITextRunPolicy.canUseEnvironmentForeground(path: "environment/foregroundStyle"))
        XCTAssertFalse(SwiftUITextRunPolicy.canUseEnvironmentForeground(path: "attachmentsStorage/0/texts/0/modifiers/0/color"))
        XCTAssertFalse(SwiftUITextRunPolicy.canUseEnvironmentForeground(path: "cachedCombinedAttachment/some/texts/0/modifiers/0/anyTextModifier"))
    }

    func testConcatenationStorageRequiresExactSwiftUIType() {
        XCTAssertTrue(SwiftUITextRunPolicy.isConcatenatedStorage("SwiftUI.(unknown context at $1c7b418b0).ConcatenatedTextStorage"))
        for type in ["Other.(unknown context at $1).ConcatenatedTextStorage",
                     "SwiftUI.(unknown context at $notHex).ConcatenatedTextStorage",
                     "SwiftUI.(unknown context at $1).ConcatenatedTextStorage.Type"] {
            XCTAssertFalse(SwiftUITextRunPolicy.isConcatenatedStorage(type))
        }
    }

    func testUnicodeRangesUseUTF16RatherThanCharacters() {
        let first = "中👩🏽‍💻e\u{301}"
        let second = "👨‍👩‍👧‍👦"
        XCTAssertNotEqual(first.count, first.utf16.count)
        XCTAssertTrue(SwiftUITextRunPolicy.valid([
            run(first), run(second, location: Int64(first.utf16.count))
        ]))
        XCTAssertFalse(SwiftUITextRunPolicy.valid([
            run(first), run(second, location: Int64(first.count))
        ]))
    }

    func testExactRunAndByteLimitsAreAcceptedButIncompleteRangesAreRefused() {
        let exact = (0..<64).map { run("a", location: Int64($0)) }
        XCTAssertTrue(SwiftUITextRunPolicy.valid(exact))
        XCTAssertFalse(SwiftUITextRunPolicy.valid(exact + [run("b", location: 64)]))
        XCTAssertTrue(SwiftUITextRunPolicy.valid([run(String(repeating: "a", count: 16_384))]))
        XCTAssertFalse(SwiftUITextRunPolicy.valid([run(String(repeating: "a", count: 16_385))]))
        for invalid in [[], [run("")], [run("a", location: -1)], [run("a", location: 1)],
                        [run("ab", length: 1)], [run("a"), run("b", location: 0)],
                        [run("a"), run("b", location: Int64.max)]] {
            XCTAssertFalse(SwiftUITextRunPolicy.valid(invalid))
        }
    }

    func testRunsBlockWholeNodeStyleInheritanceButKeepTheirOwnPromotionScope() {
        var proof = SwiftUITextScopeProof()
        proof.recordOriginalText(path: "attachmentsStorage/0/texts/0")
        proof.recordOriginalTextRuns()
        XCTAssertTrue(proof.hasOriginalTextRuns)
        XCTAssertTrue(proof.canPromote)
        XCTAssertFalse(proof.canInheritFont)
        XCTAssertFalse(proof.canInheritForegroundStyle)
    }

    private func run(_ text: String, location: Int64 = 0, length: Int64? = nil) -> RuntimeTextRun {
        RuntimeTextRun(range: .init(location: location, length: length ?? Int64(text.utf16.count)),
            text: text, fontName: nil, fontFamilyName: nil, fontSize: nil, color: nil, extensions: try! .init())
    }
}
