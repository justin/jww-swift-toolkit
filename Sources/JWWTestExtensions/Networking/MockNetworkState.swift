import Foundation
import Synchronization

/// Owns the expectations, request history, and verification failures for one mock session.
///
/// All operations synchronize through one mutex so matching and outcome consumption are atomic.
/// A consumed outcome represents an intercepted request, even when its response is still held by a gate.
final class MockNetworkState: Sendable {
    /// One registration and its progress through a finite sequence of outcomes.
    private struct Expectation {
        /// Stable removal identity, independent of matcher or response equality.
        let registration = MockRegistration()
        /// Constraints applied to the captured request before consuming an outcome.
        let matcher: MockRequestMatcher
        /// Nonempty sequence supplied by the harness in delivery order.
        let outcomes: [MockOutcome]
        /// Optional delivery control shared by every outcome in this registration.
        let gate: MockResponseGate?
        /// Declaration location included in mismatch and unused-outcome diagnostics.
        let location: String
        /// Index of the next unused outcome; updated atomically with request recording.
        var consumed = 0
    }

    /// Mutable session data that must only be accessed while holding the owning mutex.
    private struct State {
        /// Registrations in matching priority order, including exhausted registrations for diagnostics.
        var expectations: [Expectation] = []
        /// Captured requests in interception order, including those that failed to match.
        var received: [URLRequest] = []
        /// Persistent diagnostics that keep caught request errors visible to verification.
        var failures: [String] = []
        /// Prevents registration, consumption, and verification after harness cleanup.
        var closed = false
    }

    /// Protects all session data as one unit so parallel requests cannot consume the same outcome.
    private let state = Mutex(State())

    /// Returns a snapshot of captured requests without exposing the mutable history.
    var requests: [URLRequest] { state.withLock { $0.received } }

    /// Registers an expectation synchronously and returns its removal identity.
    ///
    /// - Parameters:
    ///   - matcher: Constraints applied to captured request data.
    ///   - outcomes: Nonempty response sequence, validated by `MockNetwork.expect`.
    ///   - gate: Optional control that delays delivery after consumption.
    ///   - location: Caller location used in verification diagnostics.
    /// - Throws: `MockNetworkError` if the harness has closed.
    func add(_ matcher: MockRequestMatcher, outcomes: [MockOutcome], gate: MockResponseGate?, location: String) throws -> MockRegistration {
        try state.withLock { state in
            guard !state.closed else { throw MockNetworkError("Cannot register expectations on a closed mock network") }
            let expectation = Expectation(matcher: matcher, outcomes: outcomes, gate: gate, location: location)
            state.expectations.append(expectation)
            return expectation.registration
        }
    }

    /// Removes one registration and its unused outcomes. Unknown tokens have no effect.
    /// Request history and previously recorded failures remain available.
    func remove(_ registration: MockRegistration) {
        state.withLock { state in state.expectations.removeAll { $0.registration == registration } }
    }

    /// Records a request and consumes the next outcome from the first matching unexhausted registration.
    ///
    /// - Parameter request: A captured request with body bytes materialized and the routing header removed.
    /// - Returns: The selected outcome and optional delivery gate. No callbacks run under the state mutex.
    /// - Throws: `MockNetworkError` if closed or unmatched. Unmatched requests also leave a persistent verification failure.
    func consume(_ request: URLRequest) throws -> (MockOutcome, MockResponseGate?) {
        try state.withLock { state in
            guard !state.closed else { throw MockNetworkError("Request reached a closed mock network") }
            state.received.append(request)
            if let index = state.expectations.firstIndex(where: {
                $0.consumed < $0.outcomes.count && $0.matcher.mismatches(request).isEmpty
            }) {
                let expectation = state.expectations[index]
                state.expectations[index].consumed += 1
                return (expectation.outcomes[expectation.consumed], expectation.gate)
            }
            let candidates = state.expectations.map { expectation in
                let mismatches = expectation.matcher.mismatches(request)
                let reason = mismatches.isEmpty ? "outcomes exhausted" : mismatches.joined(separator: ", ")
                return "\(expectation.location): \(expectation.matcher.method) \(expectation.matcher.url) — \(reason)"
            }
            let message = "Unexpected request \(request.httpMethod ?? "<no method>") \(request.url?.absoluteString ?? "<no URL>")\n"
                + (candidates.isEmpty ? "No expectations registered" : candidates.joined(separator: "\n"))
            state.failures.append(message)
            throw MockNetworkError(message)
        }
    }

    /// Retains a transport preparation failure for verification, even if the caller catches the request error.
    func recordFailure(_ error: any Error) {
        state.withLock { state in state.failures.append(String(describing: error)) }
    }

    /// Checks that all outcomes were consumed and no preparation or matching failures were recorded.
    /// Does not wait for held responses to finish and does not clear diagnostics.
    ///
    /// - Throws: `MockNetworkError` for a closed harness or any outstanding verification failures.
    func verify() throws {
        try state.withLock { state in
            guard !state.closed else { throw MockNetworkError("Cannot verify a closed mock network") }
            let missing = state.expectations.filter { $0.consumed < $0.outcomes.count }.map {
                "\($0.location): \($0.matcher.method) \($0.matcher.url) has \($0.outcomes.count - $0.consumed) unused outcome(s)"
            }
            let issues = state.failures + missing
            if !issues.isEmpty { throw MockNetworkError(issues.joined(separator: "\n")) }
        }
    }

    /// Permanently closes the state and releases registrations. Repeated calls are harmless.
    /// Request history is retained; the owning harness separately invalidates its session.
    func close() {
        state.withLock { state in
            state.closed = true
            state.expectations.removeAll()
        }
    }
}

/// Routing only: expectation state belongs to each harness, never to a global fixture store.
final class MockNetworkRegistry: Sendable {
    /// Process-wide routing table; fixture data remains isolated in each registered session state.
    static let shared = MockNetworkRegistry()
    /// Reserved session header carrying the routing identifier through Foundation request copying.
    static let header = "X-JWW-Mock-Network"
    /// Strong references to active session states, released when their harnesses close.
    private let states = Mutex<[String: MockNetworkState]>([:])

    /// Associates a session state with its harness-generated identifier before the session is used.
    /// The identifier must be unique among active harnesses; inserting an existing identifier replaces its state.
    func insert(_ state: MockNetworkState, id: String) {
        states.withLock { $0[id] = state }
    }

    /// Resolves the request routing header to an active session state.
    /// Returns nil for a missing or unknown identifier; the protocol must fail locally instead of using the network.
    func state(for request: URLRequest) -> MockNetworkState? {
        guard let id = request.value(forHTTPHeaderField: Self.header) else { return nil }
        return states.withLock { $0[id] }
    }

    /// Releases the routing entry during cleanup. Removing an unknown identifier has no effect.
    func remove(id: String) {
        _ = states.withLock { $0.removeValue(forKey: id) }
    }
}
