# Repository Guidelines

## Project Structure & Module Organization

This is a Swift Package Manager library for Apple platforms. Production code is
grouped by product in `Sources/`: `JWWCore` (Foundation/Codable helpers),
`JWWCoreData`, `JWWNetworking`, `JWWTestExtensions`, `JWWUIKit`, and
`JWWAppKit`. Keep APIs in the narrowest applicable module and declare
inter-module dependencies in `Package.swift`. Tests mirror modules under
`Tests/<Module>Tests/`; keep helpers and Core Data fixtures in their test target.

## Sources of Truth & Platform Support

`Package.swift`, `.swiftlint.yml`, `.github/workflows/`, and this file define
current behavior and contribution requirements. Keep shared APIs compatible
with the deployment targets in `Package.swift`; use narrow availability checks.

## Build, Test, and Development Commands

Run commands from the repository root:

```sh
swift build                              # Build the package for the host
swift test                               # Run the Swift package test suite
swiftlint lint --config .swiftlint.yml   # Lint Sources and Tests
```

Open `Package.swift` in Xcode for platform work. Use the VS Code **xcode: test
all platforms** task when a change involves platform-specific code.

## Coding Style & Naming Conventions

Use four-space indentation and the surrounding Swift style. Public APIs need
`///` documentation. Use `UpperCamelCase` for types and `lowerCamelCase` for
members. Name extensions `Type+Purpose.swift`, e.g. `URL+StaticString.swift`.
The VS Code Swift formatter uses 150 columns and no trailing commas. Do not add
SwiftLint suppressions without explaining why they are necessary.

## Testing Guidelines

Prefer Swift Testing (`import Testing`, `@Test`, and `#expect`) for new tests;
retain XCTest where existing platform or test infrastructure needs it. Name
tests after the observable behavior, e.g. `testRemovingDuplicates()`. Add
regression coverage in the matching target; fixtures must be deterministic and
offline. Run `swift test` for ordinary changes and the platform matrix for
UIKit, AppKit, Core Data, or availability-sensitive work.

## Workflow Skills

Invoke `$jww-swift-style` before any Swift source or test change or review.
After changing code, configuration, templates, documentation, or automation,
invoke `$jww-repository-validation` unless this guide already specifies the
required validation. Invoke `$jww-git-workflow` for branches, commits, rebases,
pushes, pull requests, or GitHub work. Use `$jww-handoff` when work spans
sessions or is intentionally paused.

## Commit & Pull Request Guidelines

Use short, imperative, capitalized commit subjects, e.g. `Add JWW Swift
Toolkit`. Keep commits focused. PRs should explain behavior, link relevant
issues, list validation, and include screenshots only for visible UI changes.
Ensure linting and the CI platform matrix pass before review.
