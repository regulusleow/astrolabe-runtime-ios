//
//  RuntimeMetadataAdapterTests.swift
//  astrolabe-runtime-ios
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeRuntimeObjC
import Foundation
import XCTest

final class RuntimeMetadataAdapterTests: XCTestCase {
    func testAdapterReturnsRuntimeClassName() {
        XCTAssertEqual(RuntimeMetadataAdapter.className(for: NSObject()), "NSObject")
    }

    func testAdapterReturnsMostDerivedClassFirst() {
        let object = NSMutableString()
        let classChain = RuntimeMetadataAdapter.classChain(for: object)

        XCTAssertEqual(classChain.first, RuntimeMetadataAdapter.className(for: object))
        XCTAssertEqual(classChain.last, "NSObject")
        XCTAssertTrue(classChain.contains("NSString"))
    }
}
