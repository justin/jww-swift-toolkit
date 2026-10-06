import Foundation

/// Account scope, storage location, and capacity limits for a durable queue.
public struct OfflineQueueConfiguration: Sendable {
    static let minimumRecordBytes = 4_096

    /// Dedicated local store URL. Only one queue may own this URL at a time.
    public let storeURL: URL
    /// Stable account identifier, or an explicit anonymous scope.
    public let accountID: String
    /// Maximum number of pending operations and terminal receipts combined, per account.
    public let maximumRecords: Int
    /// Maximum persisted encoded request or response body size in bytes.
    public let maximumPayloadBytes: Int
    /// Maximum retained request and completion payload bytes for each account.
    public let maximumStoredBytes: Int
    /// Seconds to retain an unacknowledged completion.
    public let receiptRetention: TimeInterval
    /// Header names permitted in persisted snapshots, compared case-insensitively.
    public let allowedHeaderNames: Set<String>

    /// Creates validated storage settings. Credential headers may never be persisted.
    /// The parent directory must already exist and be writable.
    public init(storeURL: URL, accountID: String, maximumRecords: Int = 1_000,
                maximumPayloadBytes: Int = 1_048_576, maximumStoredBytes: Int = 20_971_520,
                receiptRetention: TimeInterval = 604_800,
                allowedHeaderNames: Set<String> = ["content-type", "accept", "accept-language", "user-agent", "idempotency-key"]) throws {
        guard storeURL.isFileURL, !accountID.isEmpty, accountID.utf8.count <= 256, maximumRecords > 0,
              maximumPayloadBytes > 0, maximumStoredBytes >= max(Self.minimumRecordBytes, maximumPayloadBytes),
              receiptRetention.isFinite, receiptRetention > 0 else {
            throw OfflineQueueError.invalidConfiguration
        }
        self.storeURL = storeURL
        self.accountID = accountID
        self.maximumRecords = maximumRecords
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumStoredBytes = maximumStoredBytes
        self.receiptRetention = receiptRetention
        self.allowedHeaderNames = Set(allowedHeaderNames.map { $0.lowercased() })
    }
}
