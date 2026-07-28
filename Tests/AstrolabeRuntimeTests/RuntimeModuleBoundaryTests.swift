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
            "AstrolabeRuntimeObjC",
            "AstrolabeRuntimeBootstrap"
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
            "RuntimeServer must not remain in the composition target"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryURL
                    .appendingPathComponent("Sources/AstrolabeRuntime/UIKitHierarchyCollector.swift")
                    .path
            ),
            "UIKitHierarchyCollector must not remain in the composition target"
        )
        XCTAssertTrue(
            packageManifest.contains("type: .dynamic"),
            "AstrolabeRuntime must be a dynamic library product"
        )
        XCTAssertTrue(
            packageManifest.contains("AstrolabeRuntimeBootstrap"),
            "The dynamic product must include the bootstrap target"
        )
        XCTAssertTrue(
            packageManifest.contains(
                "name: \"AstrolabeRuntimeBootstrap\",\n"
                    + "            dependencies: [\"AstrolabeRuntime\"]"
            ),
            "The bootstrap target must link the Swift Runtime bridge"
        )

        let runtimeModuleDirectory = repositoryURL
            .appendingPathComponent("Sources/AstrolabeRuntime")
        let runtimeModuleSource = try FileManager.default
            .contentsOfDirectory(
                at: runtimeModuleDirectory,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertFalse(runtimeModuleSource.contains("@objc(ASTRuntime)"))
        XCTAssertFalse(runtimeModuleSource.contains("@_spi"))
        XCTAssertFalse(runtimeModuleSource.contains("public static func start"))
        XCTAssertFalse(runtimeModuleSource.contains("public static func stop"))
        XCTAssertFalse(
            runtimeModuleSource.contains("public static func isRunning")
        )
        XCTAssertFalse(
            runtimeModuleSource.contains(
                "public typealias RuntimeServerConfiguration"
            )
        )
        XCTAssertFalse(
            runtimeModuleSource.contains(
                "public typealias LocalTCPRuntimePortSelection"
            )
        )
    }

    func testRuntimeModuleUsesCurrentReleaseVersion() throws {
        let packageData = try Data(
            contentsOf: repositoryURL.appendingPathComponent("package.json")
        )
        let packageObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: packageData) as? [String: Any]
        )
        let packageVersion = try XCTUnwrap(packageObject["version"] as? String)

        XCTAssertEqual(AstrolabeRuntimeSDK.runtimeVersion, packageVersion)
    }

    func testRuntimeModuleUsesCurrentProtocolVersion() {
        XCTAssertEqual(AstrolabeRuntimeSDK.protocolVersion, .v2)
    }

    private var repositoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
