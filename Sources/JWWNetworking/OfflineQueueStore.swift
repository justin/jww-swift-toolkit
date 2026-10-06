import Foundation
import SwiftData

actor OfflineQueueStore: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor
    typealias Record = OfflineQueueSchemaV1.Record

    // One store owner controls all writes; rebuild accounting once after opening, then update after successful saves.
    private var accountUsage: [String: (records: Int, bytes: Int)] = [:]

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    static func open(configuration: OfflineQueueConfiguration) throws -> OfflineQueueStore {
        let schema = Schema(versionedSchema: OfflineQueueSchemaV1.self)
        let modelConfiguration = ModelConfiguration("OfflineRequests", schema: schema,
                                                    url: configuration.storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: OfflineQueueMigrationPlan.self,
                                           configurations: [modelConfiguration])
        return OfflineQueueStore(modelContainer: container)
    }

    func insert(id: UUID = UUID(), operation: String, snapshot: OfflineRequestSnapshot, policy: RetryPolicy,
                timing: (createdAt: Date, nextAttemptAt: Date), configuration: OfflineQueueConfiguration) throws {
        let snapshotData = try JSONEncoder().encode(snapshot)
        let policyData = try JSONEncoder().encode(policy)
        let usage = try usage(accountID: configuration.accountID)
        let requiredBytes = max(OfflineQueueConfiguration.minimumRecordBytes, snapshotData.count + policyData.count)
        guard snapshotData.count <= configuration.maximumPayloadBytes,
              usage.records < configuration.maximumRecords,
              usage.bytes + requiredBytes <= configuration.maximumStoredBytes else {
            throw OfflineQueueError.capacityExceeded
        }
        let record = Record(id: id, accountID: configuration.accountID, operation: operation, createdAt: timing.createdAt,
                            expiresAt: timing.createdAt.addingTimeInterval(policy.maximumAge), nextAttemptAt: timing.nextAttemptAt,
                            snapshot: snapshotData, policy: policyData)
        try save {
            modelContext.insert(record)
        }
        accountUsage[configuration.accountID] = (usage.records + 1, usage.bytes + requiredBytes)
    }

    func recover(configuration: OfflineQueueConfiguration, now: Date) throws {
        for record in try scopedRecords(configuration.accountID) where record.state != "terminal" {
            guard let pending = try validatedPending(record, configuration: configuration, now: now) else { continue }
            if record.state == "sending" {
                // A reserved attempt has an unknown server outcome after termination; never reset its budget.
                try save {
                    record.state = "waiting"
                    record.nextAttemptAt = max(record.nextAttemptAt, now)
                }
            }
            if pending.expiresAt <= now {
                _ = try finish(record.id, outcome: .failure(.expired), configuration: configuration, now: now)
            } else if pending.attemptsStarted > pending.policy.maximumRetries {
                _ = try finish(record.id, outcome: .failure(.retriesExhausted), configuration: configuration, now: now)
            }
        }
        try sweep(configuration: configuration, now: now)
    }

    func pendingRequests(configuration: OfflineQueueConfiguration, now: Date) throws -> [OfflinePendingRequest] {
        try scopedRecords(configuration.accountID).filter { $0.state != "terminal" }
            .compactMap { try validatedPending($0, configuration: configuration, now: now) }
            .sorted { $0.nextAttemptAt < $1.nextAttemptAt }
    }

    func nextPendingRequest(configuration: OfflineQueueConfiguration, now: Date) throws -> OfflinePendingRequest? {
        let accountID = configuration.accountID
        var descriptor = FetchDescriptor<Record>(predicate: #Predicate {
            $0.accountID == accountID && $0.state != "terminal" && $0.nextAttemptAt <= now
        }, sortBy: [SortDescriptor(\.nextAttemptAt)])
        descriptor.fetchLimit = 1
        while let record = try modelContext.fetch(descriptor).first {
            if let request = try validatedPending(record, configuration: configuration, now: now) { return request }
        }
        return nil
    }

    func nextDeadline(accountID: String) throws -> Date? {
        var descriptor = FetchDescriptor<Record>(predicate: #Predicate { $0.accountID == accountID })
        descriptor.propertiesToFetch = [\.state, \.nextAttemptAt, \.expiresAt, \.receiptExpiresAt]
        return try modelContext.fetch(descriptor).compactMap { record in
            record.state == "terminal" ? record.receiptExpiresAt : min(record.nextAttemptAt, record.expiresAt)
        }.min()
    }

    func reserve(_ id: UUID, recoveryDate: Date, accountID: String) throws -> Bool {
        guard let record = try record(id, accountID: accountID), record.state == "waiting" else { return false }
        try save {
            record.attemptsStarted += 1
            record.state = "sending"
            record.nextAttemptAt = recoveryDate
        }
        return true
    }

    func reschedule(_ id: UUID, nextAttemptAt: Date, accountID: String) throws {
        guard let record = try record(id, accountID: accountID), record.state == "sending" else { return }
        try save {
            record.state = "waiting"
            record.nextAttemptAt = nextAttemptAt
        }
    }

    func finish(_ id: UUID, outcome: OfflineRequestCompletion.Outcome,
                configuration: OfflineQueueConfiguration, now: Date) throws -> Bool {
        guard let record = try record(id, accountID: configuration.accountID), record.state != "terminal" else { return false }
        func encode(_ outcome: OfflineRequestCompletion.Outcome) throws -> Data {
            try JSONEncoder().encode(OfflineRequestCompletion(id: id, accountID: record.accountID, operation: record.operation,
                                                              completedAt: now, outcome: outcome))
        }
        var retainedOutcome = outcome
        if case .success(_, let body) = outcome, body.count > configuration.maximumPayloadBytes {
            retainedOutcome = .failure(.responseTooLarge)
        }
        var data = try encode(retainedOutcome)
        let previousBytes = storedBytes([record])
        if case .success = retainedOutcome {
            let remainingBytes = try usage(accountID: configuration.accountID).bytes - previousBytes
            let retainedBytes = remainingBytes + max(OfflineQueueConfiguration.minimumRecordBytes, data.count)
            if retainedBytes > configuration.maximumStoredBytes {
                data = try encode(.failure(.responseTooLarge))
            }
        }
        try save {
            record.state = "terminal"
            record.snapshot = nil
            record.policy = nil
            record.completion = data
            record.receiptExpiresAt = now.addingTimeInterval(configuration.receiptRetention)
        }
        if let usage = accountUsage[configuration.accountID] {
            accountUsage[configuration.accountID] = (usage.records, usage.bytes - previousBytes + storedBytes([record]))
        }
        return true
    }

    func completions(accountID: String) throws -> [OfflineRequestCompletion] {
        try scopedRecords(accountID).filter { $0.state == "terminal" }.map { record in
            guard let data = record.completion else { throw OfflineQueueError.invalidRecord }
            return try JSONDecoder().decode(OfflineRequestCompletion.self, from: data)
        }.sorted { $0.completedAt < $1.completedAt }
    }

    func acknowledge(_ id: UUID, accountID: String) throws {
        guard let record = try record(id, accountID: accountID), record.state == "terminal" else { return }
        let bytes = storedBytes([record])
        try save { modelContext.delete(record) }
        if let usage = accountUsage[accountID] {
            accountUsage[accountID] = (usage.records - 1, usage.bytes - bytes)
        }
    }

    func sweep(configuration: OfflineQueueConfiguration, now: Date) throws {
        let accountID = configuration.accountID
        let expired = FetchDescriptor<Record>(predicate: #Predicate {
            $0.accountID == accountID && $0.state != "terminal" && $0.expiresAt <= now
        })
        for record in try modelContext.fetch(expired) {
            _ = try finish(record.id, outcome: .failure(.expired), configuration: configuration, now: now)
        }
        let distantFuture = Date.distantFuture
        let receipts = FetchDescriptor<Record>(predicate: #Predicate {
            $0.accountID == accountID && $0.state == "terminal" && ($0.receiptExpiresAt ?? distantFuture) <= now
        })
        let records = try modelContext.fetch(receipts)
        let removedBytes = storedBytes(records)
        try save {
            for record in records { modelContext.delete(record) }
        }
        if let usage = accountUsage[accountID] {
            accountUsage[accountID] = (usage.records - records.count, usage.bytes - removedBytes)
        }
    }

    private func usage(accountID: String) throws -> (records: Int, bytes: Int) {
        if let usage = accountUsage[accountID] { return usage }
        let records = try scopedRecords(accountID)
        let usage = (records.count, storedBytes(records))
        accountUsage[accountID] = usage
        return usage
    }

    private func scopedRecords(_ accountID: String) throws -> [Record] {
        try modelContext.fetch(FetchDescriptor<Record>(predicate: #Predicate { $0.accountID == accountID }))
    }

    private func record(_ id: UUID, accountID: String) throws -> Record? {
        var descriptor = FetchDescriptor<Record>(predicate: #Predicate { $0.id == id && $0.accountID == accountID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func validatedPending(_ record: Record, configuration: OfflineQueueConfiguration, now: Date) throws -> OfflinePendingRequest? {
        let request: OfflinePendingRequest
        do {
            request = try pending(record)
        } catch {
            // Decode failures belong to this operation; storage failures must still stop scheduling.
            _ = try finish(record.id, outcome: .failure(.invalidRecord), configuration: configuration, now: now)
            return nil
        }
        return request
    }

    private func pending(_ record: Record) throws -> OfflinePendingRequest {
        guard ["waiting", "sending"].contains(record.state), record.attemptsStarted > 0,
              let snapshotData = record.snapshot, let policyData = record.policy else { throw OfflineQueueError.invalidRecord }
        let snapshot = try JSONDecoder().decode(OfflineRequestSnapshot.self, from: snapshotData)
        let policy = try JSONDecoder().decode(RetryPolicy.self, from: policyData)
        guard snapshot.version == 1, policy.isEnabled else { throw OfflineQueueError.invalidRecord }
        try policy.validate()
        return OfflinePendingRequest(id: record.id, snapshot: snapshot, policy: policy,
                                     attemptsStarted: record.attemptsStarted, expiresAt: record.expiresAt,
                                     nextAttemptAt: record.nextAttemptAt)
    }

    private func storedBytes(_ records: [Record]) -> Int {
        records.reduce(0) { total, record in
            let payloadBytes = (record.snapshot?.count ?? 0) + (record.policy?.count ?? 0) + (record.completion?.count ?? 0)
            return total + max(OfflineQueueConfiguration.minimumRecordBytes, payloadBytes)
        }
    }

    private func save(_ changes: () throws -> Void) throws {
        do {
            try changes()
            if modelContext.hasChanges { try modelContext.save() }
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
