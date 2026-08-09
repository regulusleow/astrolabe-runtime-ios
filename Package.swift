// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "astrolabe-runtime-ios",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AstrolabeRuntime",
            type: .dynamic,
            targets: [
                "AstrolabeRuntime",
                "AstrolabeRuntimeBootstrap"
            ]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/regulusleow/astrolabe-protocol.git",
            exact: "2.1.0"
        )
    ],
    targets: [
        .target(
            name: "AstrolabeRuntimeObjC",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AstrolabeRuntimeBootstrap",
            dependencies: ["AstrolabeRuntime"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "AstrolabeRuntimeCore",
            dependencies: [
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ]
        ),
        .target(
            name: "AstrolabeRuntimeUIKit",
            dependencies: [
                "AstrolabeRuntimeCore",
                "AstrolabeRuntimeObjC",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ]
        ),
        .target(
            name: "AstrolabeRuntime",
            dependencies: [
                "AstrolabeRuntimeCore",
                "AstrolabeRuntimeUIKit",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ]
        ),
        .testTarget(
            name: "AstrolabeRuntimeCoreTests",
            dependencies: [
                "AstrolabeRuntimeCore",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "AstrolabeRuntimeUIKitTests",
            dependencies: [
                "AstrolabeRuntimeCore",
                "AstrolabeRuntimeUIKit",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ]
        ),
        .testTarget(
            name: "AstrolabeRuntimeTests",
            dependencies: [
                "AstrolabeRuntime",
                "AstrolabeRuntimeCore",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ]
        ),
        .testTarget(
            name: "AstrolabeRuntimeObjCTests",
            dependencies: ["AstrolabeRuntimeObjC"]
        )
    ]
)
