import Foundation
import Synchronization

/// Holds responses until explicitly released, allowing cancellation tests without sleeps.
/// A gate can hold multiple requests. Release is permanent and idempotent.
public final class MockResponseGate: Sendable {
    /// Delivery and observation state accessed exclusively through the gate mutex.
    private struct State {
        /// Once set, pending and future responses are allowed to deliver.
        var released = false
        /// Records whether any request has reached this gate, even if later cancelled.
        var requested = false
        /// Pending delivery callbacks keyed by protocol-instance identity.
        var responses: [UUID: @Sendable () -> Void] = [:]
        /// Suspended request observers keyed by their independently cancellable wait identifiers.
        var observers: [UUID: CheckedContinuation<Void, any Error>] = [:]
    }

    /// Synchronizes release, request arrival, and cancellation without executing response callbacks under the mutex.
    private let state = Mutex(State())

    /// Create a gate that initially holds responses.
    public init() {}

    /// Wait until a request reaches this gate. Cancellation terminates the wait.
    public func waitUntilRequested() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if state.requested {
                        continuation.resume()
                    } else {
                        state.observers[id] = continuation
                    }
                }
            }
        } onCancel: {
            self.state.withLock { $0.observers.removeValue(forKey: id) }?.resume(throwing: CancellationError())
        }
    }

    /// Deliver pending responses and allow subsequent responses through immediately.
    public func release() {
        let pending = state.withLock { state in
            state.released = true
            let pending = Array(state.responses.values)
            state.responses.removeAll()
            return pending
        }
        pending.forEach { $0() }
    }

    /// Signals request arrival and either retains the response callback or invokes it immediately after release.
    ///
    /// The callback runs outside the state mutex on the enqueuing or releasing thread. The protocol must
    /// serialize delivery with cancellation because a callback already taken by `release` cannot be withdrawn.
    ///
    /// - Parameters:
    ///   - id: Unique identity for this protocol delivery, also used to cancel a pending callback.
    ///   - response: Callback that delivers the selected outcome; capture its protocol instance weakly.
    func enqueue(id: UUID, response: @escaping @Sendable () -> Void) {
        let deliver = state.withLock { state in
            state.requested = true
            for observer in state.observers.values { observer.resume() }
            state.observers.removeAll()
            if state.released { return true }
            state.responses[id] = response
            return false
        }
        if deliver { response() }
    }

    /// Removes a callback that is still waiting at the gate. Unknown identifiers have no effect.
    /// Does not reset request observation or stop a callback already taken by `release`.
    func cancel(id: UUID) {
        _ = state.withLock { state in state.responses.removeValue(forKey: id) }
    }
}
