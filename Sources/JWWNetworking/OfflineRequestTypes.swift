import Foundation

/// The outcome of submitting an operation with offline support.
public enum RequestSubmission<Output: Sendable>: Sendable {
    /// The operation completed immediately.
    case completed(Output)
    /// The operation was durably saved for later delivery.
    case queued(UUID)
}

/// The caller's assurance that repeating an operation is safe.
public enum RequestReplaySafety: Sendable {
    /// Repeating this operation has the same intended effect.
    case idempotent
    /// The server recognizes this key and deduplicates repeated operations.
    case idempotencyKey(String)
}

/// Errors managing the durable queue, separate from HTTP failures.
public enum OfflineQueueError: Error, Sendable {
    /// A retry policy contains invalid limits or intervals.
    case invalidPolicy
    /// The queue configuration contains invalid limits or account scope.
    case invalidConfiguration
    /// The request cannot be safely persisted, or contains an unapproved header.
    case unsupportedRequest
    /// A configured record or payload limit would be exceeded.
    case capacityExceeded
    /// The store contains an unsupported or invalid persisted representation.
    case invalidRecord
    /// The queue has been stopped and must be started before submitting more work.
    case stopped
}

/// A bounded, persisted terminal result, retained until acknowledgment or expiration.
public struct OfflineRequestCompletion: Codable, Sendable, Identifiable {
    /// The stable operation identifier.
    public let id: UUID
    /// The account or anonymous scope that submitted the operation.
    public let accountID: String
    /// An app-defined identifier used to select response handling after relaunch.
    public let operation: String
    /// The completion timestamp.
    public let completedAt: Date
    /// The HTTP response or terminal failure.
    public let outcome: Outcome

    /// A transport result. Decoding is performed by the consuming app.
    public enum Outcome: Codable, Sendable {
        /// Successful HTTP status and response body.
        case success(statusCode: Int, data: Data)
        /// A terminal failure, without credentials or arbitrary underlying error descriptions.
        case failure(Failure)
    }

    /// Stable failure categories suitable for persistence.
    public enum Failure: Codable, Sendable, Equatable {
        /// The operation reached its retry limit.
        case retriesExhausted
        /// The operation exceeded its maximum age.
        case expired
        /// The operation was explicitly cancelled.
        case cancelled
        /// The server returned a non-success status.
        case httpStatus(Int)
        /// Authentication could not be prepared.
        case authentication
        /// A terminal URL loading failure.
        case transport(Int)
        /// Request preparation or response validation failed.
        case invalidRequestOrResponse
        /// The stored request or retry policy could not be decoded or validated.
        case invalidRecord
        /// The response could not fit within the retained-payload limits.
        case responseTooLarge
    }
}

/// Live notifications supplementing the durable completion query.
public enum OfflineRequestEvent: Sendable {
    /// A terminal receipt was saved. Query unacknowledged completions to retrieve it.
    case completed(UUID)
    /// Scheduling stopped after a storage error. Call `start()` to try recovery again.
    case storageFailure(any Error)
}

struct OfflineRequestSnapshot: Codable, Sendable {
    let version: Int
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data?
    let requiresAuthentication: Bool

    var request: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = headers
        request.httpBody = body
        request.httpShouldHandleCookies = false
        return request
    }
}

struct OfflineReplayExpired: Error {}
