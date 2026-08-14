// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "JWW Swift Toolkit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .visionOS(.v1),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "JWWSwiftToolkit",
            targets: [
                "JWWCore",
                "JWWCoreData",
                "JWWTestExtensions",
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
        ),
        .library(
            name: "JWWSwiftUI",
            targets: ["JWWSwiftUI"]
        )
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
            dependencies: ["JWWCoreData", "JWWCore"],
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
        ),
        .target(
            name: "JWWSwiftUI",
        )
    ]
)
