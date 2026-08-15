# JWW Swift Toolkit

[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift)](https://www.swift.org)
[![CI](https://github.com/justin/jww-swift-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/justin/jww-swift-toolkit/actions/workflows/ci.yml)
[![Release](https://github.com/justin/jww-swift-toolkit/actions/workflows/release.yml/badge.svg)](https://github.com/justin/jww-swift-toolkit/actions/workflows/release.yml)

Reusable Swift utilities for Apple-platform applications.

The package provides focused modules for common Foundation, Core Data,
networking, UIKit, AppKit, and test-support tasks. It supports iOS 18.4+, macOS
15.4+, tvOS 18.4+, visionOS 2.4+, and watchOS 11.4+.

## Modules

- `JWWCore`: Foundation and Swift extensions, Codable helpers, logging, and
  formatting utilities.
- `JWWCoreData`: Core Data container, managed-object, and context helpers.
- `JWWNetworking`: request construction, HTTP client support, authentication,
  headers, content types, and network errors.
- `JWWTestExtensions`: XCTest assertions, publisher-awaiting helpers, UI-test
  conveniences, and network test doubles.
- `JWWUIKit`: UIKit conveniences for view controllers, controls, collection
  views, table views, and reusable views.
- `JWWAppKit`: AppKit conveniences for views, collection views, storyboards,
  and XIB-backed types.

`JWWSwiftToolkit` is an umbrella product that exposes every module. Individual
products are available when an application needs a narrower dependency.

## Adding the Package

Add this repository as a Swift package dependency in Xcode or declare it in a
package manifest. Depend on the individual product that matches the APIs you
use:

```swift
.product(name: "JWWNetworking", package: "jww-swift-toolkit")
```

For local development, open `Package.swift` in Xcode or use Swift Package
Manager from the repository root.

## Development

```sh
swift build
swift test
swiftlint lint --config .swiftlint.yml
```

The repository also includes VS Code tasks for building, testing, linting, and
running the test suite across the supported Apple platforms.

## License

JWW Swift Toolkit is available under the [MIT License](LICENSE.md).
