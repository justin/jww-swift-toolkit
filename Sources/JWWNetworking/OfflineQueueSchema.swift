import Foundation
import SwiftData

// Shipped schema definitions and encoded snapshot versions must remain readable by future migrations.
enum OfflineQueueSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Record.self] }

    @Model
    final class Record {
        @Attribute(.unique)
        var id: UUID
        var accountID: String
        var operation: String
        var createdAt: Date
        var expiresAt: Date
        var nextAttemptAt: Date
        var attemptsStarted: Int
        var state: String
        var snapshot: Data?
        var policy: Data?
        var completion: Data?
        var receiptExpiresAt: Date?

        init(id: UUID, accountID: String, operation: String, createdAt: Date, expiresAt: Date,
             nextAttemptAt: Date, snapshot: Data, policy: Data) {
            self.id = id
            self.accountID = accountID
            self.operation = operation
            self.createdAt = createdAt
            self.expiresAt = expiresAt
            self.nextAttemptAt = nextAttemptAt
            self.attemptsStarted = 1
            self.state = "waiting"
            self.snapshot = snapshot
            self.policy = policy
        }
    }
}

enum OfflineQueueMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OfflineQueueSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

struct OfflinePendingRequest: Sendable {
    let id: UUID
    let snapshot: OfflineRequestSnapshot
    let policy: RetryPolicy
    let attemptsStarted: Int
    let expiresAt: Date
    let nextAttemptAt: Date
}
