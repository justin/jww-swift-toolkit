import Foundation
import SwiftData
import Testing
@testable import JWWNetworking

struct OfflineQueueStoreTests {
    @Test
    func testDiskReopenPreservesScheduleAndReceipt() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let id = try await fixture.insert()
        let reopened = try OfflineQueueStore.open(configuration: fixture.configuration)
        let pending = try #require(await reopened.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).first)
        #expect(pending.id == id)
        #expect(pending.attemptsStarted == 1)
        #expect(pending.nextAttemptAt == fixture.clock.now().addingTimeInterval(10))
        #expect(pending.snapshot.headers["Idempotency-Key"] == "stable-key")
        #expect(pending.snapshot.body == fixture.snapshot.body)
        #expect(pending.policy.maximumRetries == 2)
        #expect(try await reopened.finish(id, outcome: .success(statusCode: 200, data: Data("ok".utf8)),
                                         configuration: fixture.configuration, now: fixture.clock.now()))
        let third = try OfflineQueueStore.open(configuration: fixture.configuration)
        #expect(try await third.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
        let receipt = try #require(await third.completions(accountID: "account-a").first)
        #expect(receipt.id == id)
        try await third.acknowledge(id, accountID: "account-a")
        #expect(try await third.completions(accountID: "account-a").isEmpty)
    }

    @Test
    func testInterruptedAttemptConsumesBudgetAndRetainsBackoff() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let id = try await fixture.insert()
        let recoveryDate = fixture.clock.now().addingTimeInterval(45)
        #expect(try await fixture.store.reserve(id, recoveryDate: recoveryDate, accountID: "account-a"))
        let reopened = try OfflineQueueStore.open(configuration: fixture.configuration)
        try await reopened.recover(configuration: fixture.configuration, now: fixture.clock.now())
        let recovered = try #require(await reopened.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).first)
        #expect(recovered.attemptsStarted == 2)
        #expect(recovered.nextAttemptAt == recoveryDate)
        #expect(try await reopened.reserve(id, recoveryDate: recoveryDate, accountID: "account-a"))
        try await reopened.recover(configuration: fixture.configuration, now: fixture.clock.now())
        let receipt = try #require(await reopened.completions(accountID: "account-a").first)
        guard case .failure(.retriesExhausted) = receipt.outcome else { Issue.record("Expected exhaustion"); return }
    }

    @Test
    func testCancellationCannotBeRevivedAndPayloadIsCleared() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let id = try await fixture.insert()
        #expect(try await fixture.store.finish(id, outcome: .failure(.cancelled), configuration: fixture.configuration, now: fixture.clock.now()))
        #expect(try await !fixture.store.finish(id, outcome: .success(statusCode: 200, data: Data()),
                                              configuration: fixture.configuration, now: fixture.clock.now()))
        try await fixture.store.reschedule(id, nextAttemptAt: fixture.clock.now(), accountID: "account-a")
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
        let context = ModelContext(fixture.store.modelContainer)
        let record = try #require(context.fetch(FetchDescriptor<OfflineQueueSchemaV1.Record>()).first)
        #expect(record.snapshot == nil)
        #expect(record.policy == nil)
        #expect(record.completion != nil)
    }

    @Test
    func testAccountIsolationExpirationAndReceiptCleanup() async throws {
        let fixture = try OfflineQueueFixture(receiptRetention: 20)
        defer { try? fixture.remove() }
        let id = try await fixture.insert(policy: RetryPolicy(schedule: .fixed(10), maximumAge: 15))
        let other = try OfflineQueueConfiguration(storeURL: fixture.configuration.storeURL, accountID: "account-b")
        #expect(try await fixture.store.pendingRequests(configuration: other, now: fixture.clock.now()).isEmpty)
        try await fixture.store.acknowledge(id, accountID: "account-b")
        fixture.clock.advance(16)
        try await fixture.store.sweep(configuration: fixture.configuration, now: fixture.clock.now())
        let completion = try #require(await fixture.store.completions(accountID: "account-a").first)
        guard case .failure(.expired) = completion.outcome else { Issue.record("Expected expiration"); return }
        try await fixture.store.acknowledge(id, accountID: "account-b")
        #expect(try await fixture.store.completions(accountID: "account-a").count == 1)
        fixture.clock.advance(21)
        try await fixture.store.sweep(configuration: fixture.configuration, now: fixture.clock.now())
        #expect(try await fixture.store.completions(accountID: "account-a").isEmpty)
    }

    @Test
    func testCapacityAndOversizedResponse() async throws {
        let fixture = try OfflineQueueFixture(maximumRecords: 1, maximumPayloadBytes: 512, maximumStoredBytes: 4_096)
        defer { try? fixture.remove() }
        let id = try await fixture.insert()
        await #expect(throws: OfflineQueueError.self) { try await fixture.insert() }
        _ = try await fixture.store.finish(id, outcome: .success(statusCode: 200, data: Data(repeating: 1, count: 513)),
                                           configuration: fixture.configuration, now: fixture.clock.now())
        let receipt = try #require(await fixture.store.completions(accountID: "account-a").first)
        guard case .failure(.responseTooLarge) = receipt.outcome else { Issue.record("Expected bounded failure receipt"); return }
        try await fixture.store.acknowledge(id, accountID: "account-a")
        _ = try await fixture.insert()
    }

    @Test(arguments: ["snapshot", "policy", "version", "invalidPolicy"])
    func testInvalidRecordBecomesReceiptWithoutBlockingValidWork(corruption: String) async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let invalidID = try await fixture.insert()
        let validID = try await fixture.insert()
        let context = ModelContext(fixture.store.modelContainer)
        context.autosaveEnabled = false
        let record = try #require(context.fetch(FetchDescriptor<OfflineQueueSchemaV1.Record>()).first { $0.id == invalidID })
        switch corruption {
        case "snapshot": record.snapshot = Data("invalid".utf8)
        case "policy": record.policy = Data("invalid".utf8)
        case "invalidPolicy":
            let data = try #require(record.policy)
            var policy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            policy["jitterFraction"] = 2
            record.policy = try JSONSerialization.data(withJSONObject: policy)
        default:
            record.snapshot = try JSONEncoder().encode(OfflineRequestSnapshot(version: 999, url: fixture.snapshot.url,
                                                                               method: "POST", headers: [:], body: nil,
                                                                               requiresAuthentication: false))
        }
        record.nextAttemptAt = fixture.clock.now()
        try context.save()
        let reopened = try OfflineQueueStore.open(configuration: fixture.configuration)
        if corruption == "snapshot" {
            try await reopened.recover(configuration: fixture.configuration, now: fixture.clock.now())
        } else if corruption == "version" {
            #expect(try await reopened.nextPendingRequest(configuration: fixture.configuration, now: fixture.clock.now()) == nil)
        }
        // The live pending query must also isolate bad records without launch recovery.
        let pending = try await reopened.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now())
        #expect(pending.map(\.id) == [validID])
        try await reopened.recover(configuration: fixture.configuration, now: fixture.clock.now())
        let receipt = try #require(await reopened.completions(accountID: "account-a").first)
        #expect(receipt.id == invalidID)
        guard case .failure(.invalidRecord) = receipt.outcome else { Issue.record("Expected invalid-record receipt"); return }
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: reopened,
                                        now: { fixture.clock.now() }, random: { 0.5 }, sleep: { _ in },
                                        transport: { _, _, _ in throw JWWNetworkError.invalidRequest })
        try await queue.cancelAll()
        #expect(try await queue.unacknowledgedCompletions().count == 2)
    }

    @Test
    func testCapacityIsIndependentAcrossAccounts() async throws {
        let fixture = try OfflineQueueFixture(maximumRecords: 1, maximumPayloadBytes: 512, maximumStoredBytes: 4_096)
        defer { try? fixture.remove() }
        let id = try await fixture.insert()
        _ = try await fixture.store.finish(id, outcome: .failure(.cancelled), configuration: fixture.configuration, now: fixture.clock.now())
        let other = try OfflineQueueConfiguration(storeURL: fixture.configuration.storeURL, accountID: "account-b",
                                                  maximumRecords: 1, maximumPayloadBytes: 512, maximumStoredBytes: 4_096)
        let otherID = UUID()
        try await fixture.store.insert(id: otherID, operation: "test", snapshot: fixture.snapshot, policy: RetryPolicy(schedule: .fixed(10)),
                                       timing: (fixture.clock.now(), fixture.clock.now()), configuration: other)
        _ = try await fixture.store.finish(otherID, outcome: .success(statusCode: 200, data: Data(repeating: 1, count: 500)),
                                           configuration: other, now: fixture.clock.now())
        let receipt = try #require(await fixture.store.completions(accountID: "account-b").first)
        guard case .success = receipt.outcome else { Issue.record("Another account consumed the byte budget"); return }
        await #expect(throws: OfflineQueueError.self) {
            try await fixture.store.insert(operation: "test", snapshot: fixture.snapshot, policy: RetryPolicy(schedule: .fixed(10)),
                                           timing: (fixture.clock.now(), fixture.clock.now()), configuration: other)
        }
        #expect(try await fixture.store.completions(accountID: "account-a").count == 1)
    }

    @Test
    func testAccountingTracksReceiptReplacementCleanupAndReopen() async throws {
        let fixture = try OfflineQueueFixture(maximumRecords: 3, maximumPayloadBytes: 8_192, maximumStoredBytes: 12_288,
                                               receiptRetention: 10)
        defer { try? fixture.remove() }
        let large = OfflineRequestSnapshot(version: 1, url: fixture.snapshot.url, method: "POST", headers: [:],
                                           body: Data(repeating: 1, count: 5_000), requiresAuthentication: false)
        let id = UUID()
        try await fixture.store.insert(id: id, operation: "large", snapshot: large, policy: RetryPolicy(schedule: .fixed(10)),
                                       timing: (fixture.clock.now(), fixture.clock.now()), configuration: fixture.configuration)
        _ = try await fixture.insert()
        _ = try await fixture.store.finish(id, outcome: .success(statusCode: 200, data: Data()),
                                           configuration: fixture.configuration, now: fixture.clock.now())
        _ = try await fixture.insert()
        let reopened = try OfflineQueueStore.open(configuration: fixture.configuration)
        await #expect(throws: OfflineQueueError.self) {
            try await reopened.insert(operation: "full", snapshot: fixture.snapshot, policy: RetryPolicy(schedule: .fixed(10)),
                                       timing: (fixture.clock.now(), fixture.clock.now()), configuration: fixture.configuration)
        }
        fixture.clock.advance(11)
        try await reopened.sweep(configuration: fixture.configuration, now: fixture.clock.now())
        try await reopened.insert(operation: "replacement", snapshot: fixture.snapshot, policy: RetryPolicy(schedule: .fixed(10)),
                                   timing: (fixture.clock.now(), fixture.clock.now()), configuration: fixture.configuration)
        #expect(try await reopened.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).count == 3)
    }

    @Test
    func testInvalidStoreIsNotReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.store")
        let original = Data("not a database".utf8)
        try original.write(to: url)
        let configuration = try OfflineQueueConfiguration(storeURL: url, accountID: "test")
        #expect(throws: (any Error).self) { try OfflineQueueStore.open(configuration: configuration) }
        #expect(try Data(contentsOf: url) == original)
    }
    @Test
    func testFailedSaveRollsBackAttemptAndDeletion() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let id = try await fixture.insert()
        let schema = Schema(versionedSchema: OfflineQueueSchemaV1.self)
        let configuration = ModelConfiguration("OfflineRequests", schema: schema, url: fixture.configuration.storeURL,
                                               allowsSave: false, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: OfflineQueueMigrationPlan.self, configurations: [configuration])
        let readOnly = OfflineQueueStore(modelContainer: container)
        await #expect(throws: (any Error).self) {
            try await readOnly.reserve(id, recoveryDate: fixture.clock.now(), accountID: "account-a")
        }
        let pending = try #require(await readOnly.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).first)
        #expect(pending.attemptsStarted == 1)
        #expect(pending.nextAttemptAt == fixture.clock.now().addingTimeInterval(10))
        await #expect(throws: (any Error).self) {
            try await readOnly.finish(id, outcome: .success(statusCode: 200, data: Data()),
                                      configuration: fixture.configuration, now: fixture.clock.now())
        }
        #expect(try await readOnly.completions(accountID: "account-a").isEmpty)
        #expect(try await readOnly.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).count == 1)
        _ = try await fixture.store.finish(id, outcome: .failure(.cancelled), configuration: fixture.configuration, now: fixture.clock.now())
        let receiptContainer = try ModelContainer(for: schema, migrationPlan: OfflineQueueMigrationPlan.self, configurations: [configuration])
        let receipts = OfflineQueueStore(modelContainer: receiptContainer)
        await #expect(throws: (any Error).self) { try await receipts.acknowledge(id, accountID: "account-a") }
        #expect(try await receipts.completions(accountID: "account-a").count == 1)
        #expect(try await receipts.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
    }
}
