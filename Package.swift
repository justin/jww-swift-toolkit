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
        // Generates documentation for project
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),

        // SwiftLint build tool plugin for code quality
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.64.0")
    ],
    targets: [
        .target(
            name: "JWWCore",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ],
        ),
        .testTarget(
            name: "JWWCoreTests",
            dependencies: ["JWWCore"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .target(
            name: "JWWCoreData",
            dependencies: ["JWWCore"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "JWWCoreDataTests",
            dependencies: ["JWWCoreData", "JWWCore", "JWWCoreDataTestSupport"],
            resources: [
                .process("Resources")
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .target(
            name: "JWWTestExtensions",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "JWWTestExtensionsTests",
            dependencies: ["JWWTestExtensions"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .target(
            name: "JWWCoreDataTestSupport",
            dependencies: ["JWWCoreData"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "JWWCoreDataTestSupportTests",
            dependencies: ["JWWCoreDataTestSupport", "JWWCoreData"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .target(
            name: "JWWNetworking",
            dependencies: ["JWWCore"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "JWWNetworkingTests",
            dependencies: ["JWWNetworking", "JWWTestExtensions"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .target(
            name: "JWWAppKit",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "JWWAppKitTests",
            dependencies: ["JWWAppKit"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .target(
            name: "JWWUIKit",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "JWWUIKitTests",
            dependencies: ["JWWUIKit"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        )
    ]
)
