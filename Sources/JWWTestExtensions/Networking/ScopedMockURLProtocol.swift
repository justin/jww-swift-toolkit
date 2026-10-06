import Foundation
import Synchronization

/// Intercepts requests for one scoped harness and delivers their registered outcomes.
///
/// Foundation makes URLProtocol's Sendable conformance unavailable. The gate callback must
/// retain access to this internal protocol instance across threads. Lifecycle state lives in a
/// Mutex, and the recursive lock serializes every callback and inherited-property access in
/// this subclass with startLoading/stopLoading. Keep this exception at the Foundation boundary.
final class ScopedMockURLProtocol: URLProtocol, @unchecked Sendable {
    /// Lifecycle data protected by the mutex independently of callback serialization.
    private struct State {
        /// Cancellation flag checked between callbacks, including reentrant cancellation by the client.
        var stopped = false
        /// Claims delivery once so repeated or competing completions cannot send duplicate terminal callbacks.
        var completed = false
        /// Gate retaining the pending response callback until release or cancellation.
        var gate: MockResponseGate?
    }

    /// Protects lifecycle flags and the gate reference; never held across external callbacks.
    private let state = Mutex(State())
    /// Serialize callbacks with stopLoading. A client may cancel synchronously from a callback,
    /// so this lock must be recursive. Never hold the state mutex while invoking client or gate code.
    private let lock = NSRecursiveLock()
    /// Identifies this protocol instance's callback in a shared response gate.
    private let deliveryID = UUID()

    /// Accepts intercepted requests even when routing information is missing, so they fail locally.
    override static func canInit(with request: URLRequest) -> Bool { true }

    /// Preserves the request URL and constraints for exact matching.
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Captures and consumes a request, then delivers its outcome immediately or through its gate.
    /// Routing and preparation failures are reported to the client without accessing the network.
    override func startLoading() {
        lock.withLock {
            guard state.withLock({ !$0.stopped && !$0.completed }) else { return }
            guard let networkState = MockNetworkRegistry.shared.state(for: request) else {
                finish(.failure(MockNetworkError("Missing mock session routing information; request was blocked")))
                return
            }
            let outcome: MockOutcome
            do {
                outcome = try loadOutcome(state: networkState)
            } catch {
                finish(.failure(error))
                return
            }
            if let gate = state.withLock({ $0.gate }) {
                gate.enqueue(id: deliveryID) { [weak self] in self?.finish(outcome) }
            } else {
                finish(outcome)
            }
        }
    }

    /// Serializes cancellation with delivery and removes a callback still held by the gate.
    /// May be reentered synchronously from a client callback; later callbacks then stop.
    override func stopLoading() {
        lock.withLock {
            let gate = state.withLock { state in
                state.stopped = true
                let gate = state.gate
                state.gate = nil
                return gate
            }
            gate?.cancel(id: deliveryID)
        }
    }

    /// Materializes request bytes, removes the routing header, and consumes the owning session's expectation.
    /// Retains its optional delivery gate and records body-capture errors for later verification.
    ///
    /// - Precondition: The callback serialization lock is held.
    /// - Throws: A body-stream error or a session-state matching/lifecycle error.
    private func loadOutcome(state: MockNetworkState) throws -> MockOutcome {
        var captured = request
        captured.setValue(nil, forHTTPHeaderField: MockNetworkRegistry.header)
        do {
            captured.httpBody = try bodyData()
        } catch {
            state.recordFailure(error)
            throw error
        }
        let (outcome, gate) = try state.consume(captured)
        self.state.withLock { $0.gate = gate }
        return outcome
    }

    /// Returns the request body or reads its finite stream to completion. Nil means no body was supplied.
    /// The stream is closed after reading; this terminal mock transport does not forward it elsewhere.
    ///
    /// - Precondition: The callback serialization lock is held.
    /// - Throws: The stream error, or a mock diagnostic if the stream fails without supplying an error.
    private func bodyData() throws -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        // This protocol is the terminal transport. The captured bytes replace the stream for matching and recording.
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? MockNetworkError("Failed to capture request body stream") }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    /// Claims delivery once and serializes response, data, and completion callbacks with cancellation.
    /// Transport failures send only a failure callback. Reentrant cancellation after a response or data
    /// callback prevents further delivery. May be called from the gate's releasing thread.
    private func finish(_ outcome: MockOutcome) {
        lock.withLock {
            let shouldDeliver = state.withLock { state in
                guard !state.stopped, !state.completed else { return false }
                state.completed = true
                state.gate = nil
                return true
            }
            guard shouldDeliver else { return }
            switch outcome {
            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            case .response(let response):
                guard let url = request.url,
                      let httpResponse = HTTPURLResponse(url: url, statusCode: response.statusCode,
                                                         httpVersion: "HTTP/1.1", headerFields: response.headers) else {
                    client?.urlProtocol(self, didFailWithError: MockNetworkError("Could not construct mock HTTP response"))
                    return
                }
                client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                guard state.withLock({ !$0.stopped }) else { return }
                if !response.data.isEmpty { client?.urlProtocol(self, didLoad: response.data) }
                guard state.withLock({ !$0.stopped }) else { return }
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
}
