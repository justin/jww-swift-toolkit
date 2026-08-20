// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "JWW Swift Toolkit",
    platforms: [
        .iOS("18.4"),
        .macOS("15.4"),
        .tvOS("18.4"),
        .visionOS("2.4"),
        .watchOS("11.4")
    ],
    products: [
        .library(
            name: "JWWSwiftToolkit",
            targets: [
                "JWWCore",
                "JWWCoreData",
                "JWWNetworking",
                "JWWAppKit",
                "JWWUIKit"
            ]
        ),
        .library(
            name: "JWWCore",
            targets: ["JWWCore"]
        ),
        .library(
            name: "JWWCoreData",
            targets: ["JWWCoreData"]
        ),
        .library(
            name: "JWWTestExtensions",
            targets: ["JWWTestExtensions"]
        ),
        .library(
            name: "JWWCoreDataTestSupport",
            targets: ["JWWCoreDataTestSupport"]
        ),
        .library(
            name: "JWWNetworking",
            targets: ["JWWNetworking"]
        ),
        .library(
            name: "JWWAppKit",
            targets: ["JWWAppKit"]
        ),
        .library(
            name: "JWWUIKit",
            targets: ["JWWUIKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3")
    ],
    targets: [
        .target(
            name: "JWWCore",
        ),
        .testTarget(
            name: "JWWCoreTests",
            dependencies: ["JWWCore"],
        ),
        .target(
            name: "JWWCoreData",
            dependencies: ["JWWCore"],
        ),
        .testTarget(
            name: "JWWCoreDataTests",
            dependencies: ["JWWCoreData", "JWWCore", "JWWCoreDataTestSupport"],
            resources: [
                .process("Resources")
            ],
        ),
        .target(
            name: "JWWTestExtensions",
        ),
        .testTarget(
            name: "JWWTestExtensionsTests",
            dependencies: ["JWWTestExtensions"],
        ),
        .target(
            name: "JWWCoreDataTestSupport",
            dependencies: ["JWWCoreData"],
        ),
        .testTarget(
            name: "JWWCoreDataTestSupportTests",
            dependencies: ["JWWCoreDataTestSupport", "JWWCoreData"],
        ),
        .target(
            name: "JWWNetworking",
            dependencies: ["JWWCore"],
        ),
        .testTarget(
            name: "JWWNetworkingTests",
            dependencies: ["JWWNetworking", "JWWTestExtensions"],
        ),
        .target(
            name: "JWWAppKit",
        ),
        .testTarget(
            name: "JWWAppKitTests",
            dependencies: ["JWWAppKit"],
        ),
        .target(
            name: "JWWUIKit",
        ),
        .testTarget(
            name: "JWWUIKitTests",
            dependencies: ["JWWUIKit"],
        )
    ]
)
