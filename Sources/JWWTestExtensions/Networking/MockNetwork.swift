import Foundation

/// An opaque identity for removing one expectation without comparing response payloads.
public struct MockRegistration: Hashable, Sendable {
    /// Uniquely identifies a registration across harnesses without exposing a caller-supplied identity.
    let id = UUID()
}

/// An isolated, offline URLSession and its request expectations.
/// All mutable state is protected by a lock. Close the harness when finished, or use `withMockNetwork`.
public final class MockNetwork: Sendable {
    /// The session to inject into the code under test. Do not create tasks after closing the harness.
    public let session: URLSession
    /// Session routing identifier registered before creating the session and removed on close.
    private let id: String
    /// Owns this harness's expectations and history independently of all other sessions.
    private let state: MockNetworkState

    /// Create an ephemeral session that intercepts every request and never accesses the network.
    public init() {
        id = UUID().uuidString
        state = MockNetworkState()
        MockNetworkRegistry.shared.insert(state, id: id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScopedMockURLProtocol.self]
        configuration.httpAdditionalHeaders = [MockNetworkRegistry.header: id]
        session = URLSession(configuration: configuration)
    }

    /// Closes the session and unregisters its state if the caller has not already performed cleanup.
    deinit {
        close()
    }

    /// Received requests in interception order, with captured body bytes and without the routing header.
    public var requests: [URLRequest] { state.requests }

    /// Register a response repeated exactly `count` times. Registration completes synchronously.
    @discardableResult
    public func expect(_ matcher: MockRequestMatcher, outcome: MockOutcome, count: Int = 1,
                       gate: MockResponseGate? = nil, fileID: String = #fileID, line: UInt = #line) throws -> MockRegistration {
        guard count > 0 else { throw MockNetworkError("Expectation count must be positive at \(fileID):\(line)") }
        return try expect(matcher, outcomes: Array(repeating: outcome, count: count), gate: gate, fileID: fileID, line: line)
    }

    /// Register an ordered sequence. Matching uses the first registered expectation with remaining outcomes.
    @discardableResult
    public func expect(_ matcher: MockRequestMatcher, outcomes: [MockOutcome],
                       gate: MockResponseGate? = nil, fileID: String = #fileID, line: UInt = #line) throws -> MockRegistration {
        guard !outcomes.isEmpty else { throw MockNetworkError("An expectation needs an outcome at \(fileID):\(line)") }
        return try state.add(matcher, outcomes: outcomes, gate: gate, location: "\(fileID):\(line)")
    }

    /// Remove only the registration identified by the token. Other harnesses' tokens have no effect.
    public func remove(_ registration: MockRegistration) {
        state.remove(registration)
    }

    /// Throw if any request was unexpected or any registered outcome was unused.
    /// Catching a request's transport error does not hide a matching failure from verification.
    public func verify() throws {
        try state.verify()
    }

    /// Cancel outstanding requests and release registrations. Repeated calls are harmless.
    /// Verify before closing; closing discards pending expectations.
    public func close() {
        state.close()
        MockNetworkRegistry.shared.remove(id: id)
        session.invalidateAndCancel()
    }
}

/// Run with an isolated mock network, verify on success, and clean up on every exit.
/// If the body throws, preserve that error rather than replacing it with a verification failure.
public func withMockNetwork<Value>(isolation: isolated (any Actor)? = #isolation,
                                   _ body: (MockNetwork) async throws -> Value) async throws -> Value {
    let network = MockNetwork()
    defer { network.close() }
    try Task.checkCancellation()
    let value = try await body(network)
    try Task.checkCancellation()
    try network.verify()
    return value
}
