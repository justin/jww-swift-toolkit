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

## Mock Networking

`JWWTestExtensions` provides an isolated `MockNetwork` for each test. Inject its
`session` into the client under test. The same API works with XCTest and Swift
Testing; no test superclass or process-wide URL protocol registration is needed.

```swift
import Foundation
import JWWTestExtensions
import Testing

@Test
func testResponse() async throws {
    try await withMockNetwork { network in
        let url = URL(string: "https://example.invalid/items")!
        try network.expect(
            .init(.get, url: url),
            outcome: .response(try .json(["name": "example"]))
        )

        let (data, response) = try await network.session.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(!data.isEmpty)
        #expect(network.requests.count == 1)
    }
}
```

Expectations match the exact HTTP method and full URL, including query order.
Optional `headers` constrain a subset of request headers, with case-insensitive
header names and exact values. An optional `body` compares exact bytes; nil
leaves the body unconstrained, while `Data()` requires an empty body. Finite
request body streams are captured by the mock transport for matching and
recording. The harness consumes the first matching registration with remaining
outcomes. Each registration expects one request unless `count` or an ordered
`outcomes` array is supplied. An opaque returned token removes only that
registration through `network.remove(token)`.

Unexpected requests fail locally and remain verification failures even if the
test catches their errors. There is no HTTP network fallback. Diagnostics include
the actual method and URL, mismatch details, and each expectation's declaration
location. The internal `X-JWW-Mock-Network` header routes requests to their owning
harness and is removed from recorded requests. Reserve this header for the
harness; do not set it on requests or expect it in matchers.

`withMockNetwork` verifies that every outcome was consumed on successful exit
and closes the session on success, error, or cancellation. A thrown body error
is preserved rather than replaced by an unused-expectation error. Await work
inside the scope; neither the session nor tasks using it should escape. For
manual lifetimes, use `defer { network.close() }` and call `try network.verify()`
before cleanup. Never create tasks on a session after closing it; Foundation
considers that API misuse. Verification checks request consumption, not whether
an intentionally held response has finished delivering.

### Responses and errors

- `.response(.init(statusCode: 204))` delivers an empty HTTP response.
- `.response(try .json(value, statusCode: 201))` encodes any `Encodable` value
  during setup. Supply an encoder for custom encoding strategies.
- `.response(.text("malformed JSON", contentType: "application/json"))` delivers
  intentionally invalid bytes for decoding tests.
- `.response(.init(data: bytes))` preserves arbitrary binary data.
- `.response(try .fixture("users", extension: "json", bundle: .module))` loads
  bytes from the consuming test target's resources. Missing files throw during
  setup. Supply response headers explicitly for resource fixtures.
- `.failure(URLError(.timedOut))` represents a transport failure. Arbitrary
  errors retain their domain, code, and user information through Foundation.

HTTP 401/500 responses are `.response` outcomes, not transport failures. Every
HTTP response accepts custom numeric status codes and headers. JSON and text
factories supply a content type unless the caller already provided one. Keep
representative server fixtures alongside model-based factories so decoder tests
do not rely exclusively on encoding and decoding the same model.

For successive calls, register `outcomes: [.failure(URLError(.timedOut)),
.response(.text("recovered"))]`. The mock does not implement retries itself.
For deterministic cancellation tests, pass a `MockResponseGate` to `expect`,
start the request in a task, and `try await gate.waitUntilRequested()`. Then
cancel the task or call `gate.release()` to deliver the response. Release is
permanent and idempotent; cancellation prevents later delivery. Always cancel
or await request tasks before leaving their scope. Redirect simulation,
streaming response delivery, and custom fixture macros are outside this API.

### Migration from static mocks

`MockURLProtocol`, `NetworkResponseStub`, and `MockedNetworkTestCase` remain
public and are deprecated with migration messages. Their sources live under
`Sources/JWWTestExtensions/Deprecated`. Existing callers retain their
original signatures and behavior, including global registration, path/query
matching, and reusable fixtures. These compatibility helpers retain their global
state and are not suitable for concurrent tests that share fixtures.

For migration, replace static registrations with `network.expect`, inject
`network.session`, and replace global fixture removal with scope cleanup.
Existing XCTest classes can own a `MockNetwork` in setup and verify/close it in
teardown. Include the full URL and method, and explicitly declare repeated
requests. The scoped harness uses a separate internal protocol and fixture store;
it never falls back to deprecated global stubs. The networking module's private
test doubles have been removed, so its tests exercise the scoped public helper.

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
