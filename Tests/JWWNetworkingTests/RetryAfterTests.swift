import Foundation
import Testing
@testable import JWWNetworking

struct RetryAfterTests {
    @Test
    func parsesSecondsAndHTTPDatesButRejectsMalformedValues() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(RetryAfter.date("120", now: now) == now.addingTimeInterval(120))
        #expect(RetryAfter.date("Thu, 01 Jan 1970 00:20:00 GMT", now: now) == Date(timeIntervalSince1970: 1_200))
        for value in ["", "-1", "1.5", "later", "NaN", "Infinity"] { #expect(RetryAfter.date(value, now: now) == nil) }
    }

    @Test(arguments: [429, 502, 503, 504])
    func serverDeadlineSurvivesSchedulingAndDoesNotBlockOtherRequests(status: Int) async throws {
        let fixture = try OfflineQueueFixture(retryableHTTPStatusCodes: [429, 502, 503, 504])
        defer { try? fixture.remove() }
        let deadline = fixture.clock.now().addingTimeInterval(120)
        let transport = OfflineTestTransport([
            .success(HTTPResult(data: Data(), statusCode: status, retryAfter: deadline)),
            .success(HTTPResult(data: Data(#"{"value":"ok"}"#.utf8), statusCode: 200)),
            .success(HTTPResult(data: Data(), statusCode: status, retryAfter: deadline.addingTimeInterval(120)))
        ])
        let queue = fixture.queue(transport: transport)
        try await queue.start()
        let policy = try RetryPolicy(maximumRetries: 3, schedule: .fixed(10))
        let first = try await queue.send(template: fixture.template, policy: policy, operation: "first", replaySafety: .idempotent)
        guard case .queued(let id) = first else { Issue.record("Expected persisted retry"); return }
        #expect(try await queue.pendingStatuses().first?.nextAttemptAt == deadline)
        let second = try await queue.send(template: fixture.template, policy: policy, operation: "second", replaySafety: .idempotent)
        guard case .completed = second else { Issue.record("Independent request was blocked"); return }
        await queue.stop()
        fixture.clock.advance(120)
        try await queue.start()
        let limit = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < limit {
            let pending = try await queue.pendingStatuses()
            if pending.first?.nextAttemptAt == deadline.addingTimeInterval(120), pending.first?.isSending == false { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await queue.stop()
        let restored = try OfflineQueueStore.open(configuration: fixture.configuration)
        let pending = try #require(await restored.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).first)
        #expect(pending.id == id)
        #expect(pending.nextAttemptAt == deadline.addingTimeInterval(120))
        #expect(pending.attemptsStarted == 2)
    }
}
