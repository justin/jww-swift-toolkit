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
- `JWWCoreDataTestSupport`: scoped true-memory and temporary-SQLite resources
  for Core Data tests, including typed app-container composition.
- `JWWNetworking`: request construction, HTTP client support, authentication,
  headers, content types, and network errors.
- `JWWTestExtensions`: XCTest assertions, publisher-awaiting helpers, UI-test
  conveniences, and network test doubles.
- `JWWUIKit`: UIKit conveniences for view controllers, controls, collection
  views, table views, and reusable views.
- `JWWAppKit`: AppKit conveniences for child-controller containment, typed
  collection and table view reuse, text-field publishing, views, storyboards,
  and XIB-backed types.

`JWWSwiftToolkit` is an umbrella product for the production modules. Individual
products are available when an application needs a narrower dependency; test
support remains an explicit test-target dependency.

## AppKit Helpers

`NSViewController.add(_:)` and `add(_:superview:)` attach both the child
controller and its view. Call `remove()` on the child to detach both. These
helpers leave frames, autoresizing masks, and constraints to the caller.

Conform collection view items or table views' reusable views to
`JWWAppKit.ReuseIdentifiable`, providing a static `reuseIdentifier` of type
`NSUserInterfaceItemIdentifier`. Collection views provide
`registerReusableClass(_:)` and `makeReusableItem(_:for:)`. Table views provide
`makeReusableView(_:owner:)`, which preserves AppKit's optional result and
passes the owner through to nib loading. An identifier that produces the wrong
type is a programming error. For nib-backed types, conform to
`JWWAppKit.ReuseIdentifiableNib`, provide a static `NSNib`, and use
`registerReusableNib(_:)` on either collection or table views.

`NSTextField.textPublisher` emits strings for editing-change notifications
from that field. It does not emit an initial value or observe programmatic
`stringValue` assignments. Subscribe and edit on the main actor; keeping the
publisher or subscription alive does not retain the field.

## Core Data Test Support

`JWWCoreDataTestSupport` provides two physical stores with explicit lifecycles:
true in-memory stores for lightweight tests, and UUID-owned temporary SQLite
stores for tests that need SQLite behavior. Use typed `CoreDataTestStore`
composition when a test needs an application's concrete persistent-container
subclass; a `CoreDataTestContainerFactory` receives the generated
`PersistentStoreProfile` and owns application-specific loading. The optional
`CoreDataTestStoreTrait` is available on compiler versions 6.1 and later for
context-level Swift Testing cases. It deliberately does not replace typed
container composition.

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

## Documentation

The generated API reference is published at
[justin.github.io/jww-swift-toolkit/documentation](https://justin.github.io/jww-swift-toolkit/documentation/).

Generate and publish documentation from a clean checkout of current `main`
on your Mac using the Xcode Swift toolchain:

```sh
./scripts/publish-documentation --dry-run # Generate and validate without publishing
./scripts/publish-documentation           # Generate and push the site to gh-pages
```

The script fetches `origin/main` and requires your checkout to match it. It
generates the reference in a temporary directory and publishes it to the
dedicated `gh-pages` branch without switching or modifying your working
branch. Publication uses your Git credentials and commit identity, preserves
the site's branch history, and rejects concurrent updates rather than
force-pushing. Temporary files are removed when the script exits.

The Ubuntu documentation workflow deploys the generated files to GitHub
Pages when `gh-pages` changes. Configure the repository's Pages source as
**GitHub Actions** and allow the `gh-pages` branch to deploy to the
`github-pages` environment. The workflow can also be run manually to redeploy
the existing site. The script copies this workflow into `gh-pages` so pushes
to that branch can trigger it.

Documentation generation and Apple-platform tests run locally. GitHub
Actions uses only Ubuntu runners for Pages deployment, linting, and releases.

## License

JWW Swift Toolkit is available under the [MIT License](LICENSE.md).
