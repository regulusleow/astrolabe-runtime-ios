//
//  RuntimeModuleBoundaryTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeRuntime
import AstrolabeProtocol
import Foundation
import XCTest

final class RuntimeModuleBoundaryTests: XCTestCase {
    func testPackageDefinesExplicitRuntimeModuleBoundaries() throws {
        let packageManifest = try String(
            contentsOf: repositoryURL.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        for targetName in [
            "AstrolabeRuntimeCore",
            "AstrolabeRuntimeUIKit",
            "AstrolabeRuntime",
            "AstrolabeRuntimeObjC"
        ] {
            XCTAssertTrue(
                packageManifest.contains("name: \"\(targetName)\""),
                "Package.swift is missing target: \(targetName)"
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryURL
                    .appendingPathComponent("Sources/AstrolabeRuntime/RuntimeServer.swift")
                    .path
            ),
            "RuntimeServer must not remain in the facade target"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryURL
                    .appendingPathComponent("Sources/AstrolabeRuntime/UIKitHierarchyCollector.swift")
                    .path
            ),
            "UIKitHierarchyCollector must not remain in the facade target"
        )
    }

    func testRuntimeFacadeExposesCurrentReleaseVersion() throws {
        let packageData = try Data(
            contentsOf: repositoryURL.appendingPathComponent("package.json")
        )
        let packageObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: packageData) as? [String: Any]
        )
        let packageVersion = try XCTUnwrap(packageObject["version"] as? String)

        XCTAssertEqual(AstrolabeRuntimeSDK.runtimeVersion, packageVersion)
    }

    func testRuntimeFacadeExposesCurrentProtocolVersion() {
        XCTAssertEqual(AstrolabeRuntimeSDK.protocolVersion, .v2)
    }

    private var repositoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
