import Foundation

/// Delivery timing for a persisted request, without its payload or credentials.
public struct OfflineRequestStatus: Sendable, Identifiable {
    /// The stable queue identity.
    public let id: UUID
    /// Earliest scheduled attempt time; execution can be delayed while the app is suspended.
    public let nextAttemptAt: Date
    /// Whether the queue is currently attempting delivery.
    public let isSending: Bool
}
