//
//  UIKitRuntimeInspectionServicesFactoryTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/15.
//

#if canImport(UIKit)
import AstrolabeRuntimeCore
@testable import AstrolabeRuntimeUIKit
import XCTest

@MainActor
final class UIKitRuntimeInspectionServicesFactoryTests: XCTestCase {
    func testFactorySharesRegistryWithinRuntimeSession() throws {
        let factory = UIKitRuntimeInspectionServicesFactory(
            targetIdentifier: RuntimeServerConfiguration
                .defaultRuntimeInstanceIdentifier
        )
        let firstServices = factory.makeServices()
        let secondServices = factory.makeServices()
        let firstProvider = try XCTUnwrap(
            firstServices.hierarchyProvider as? UIKitRuntimeHierarchyProvider
        )
        let secondProvider = try XCTUnwrap(
            secondServices.hierarchyProvider as? UIKitRuntimeHierarchyProvider
        )

        XCTAssertEqual(
            firstServices.additionalCapabilities,
            [.uiGraphRelations]
        )
        XCTAssertTrue(firstProvider.nodeRegistry === secondProvider.nodeRegistry)

        let nextSessionProvider = try XCTUnwrap(
            UIKitRuntimeInspectionServicesFactory(
                targetIdentifier: RuntimeServerConfiguration
                    .defaultRuntimeInstanceIdentifier
            )
                .makeServices()
                .hierarchyProvider as? UIKitRuntimeHierarchyProvider
        )
        XCTAssertFalse(firstProvider.nodeRegistry === nextSessionProvider.nodeRegistry)
    }
}
#endif
