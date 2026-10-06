import Foundation
import Testing
@testable import JWWNetworking

struct OfflineRequestQueueTests {
    @Test
    func testOfflineThenSuccessPreservesIdentityAndCleansUp() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let transport = OfflineTestTransport([.failure(.networkError(URLError(.notConnectedToInternet))),
                                              .success(HTTPResult(data: Data("result".utf8), statusCode: 201))])
        let queue = fixture.queue(transport: transport)
        try await queue.start()
        let submission = try await queue.send(template: fixture.template, policy: RetryPolicy(schedule: .fixed(10)),
                                               operation: "update", replaySafety: .idempotencyKey("one-operation"))
        guard case .queued(let id) = submission else { Issue.record("Expected a persisted request"); return }
        await queue.stop()
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).count == 1)
        let events = await queue.events()
        fixture.clock.advance(10)
        try await queue.start()
        #expect(try await nextCompletion(in: events) == id)
        await queue.stop()
        let receipt = try #require(await queue.unacknowledgedCompletions().first)
        guard case .success(let status, let data) = receipt.outcome else { Issue.record("Expected success"); return }
        #expect(status == 201)
        #expect(data == Data("result".utf8))
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.headers["Idempotency-Key"] == "one-operation" })
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
        try await queue.acknowledge(id)
        try await queue.acknowledge(id)
        #expect(try await queue.unacknowledgedCompletions().isEmpty)
    }

    @Test
    func testRetryLimitIncludesOnlyOneInitialAttempt() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let offline = JWWNetworkError.networkError(URLError(.networkConnectionLost))
        let transport = OfflineTestTransport([.failure(offline), .failure(offline)])
        let queue = fixture.queue(transport: transport)
        try await queue.start()
        _ = try await queue.send(template: fixture.template, policy: RetryPolicy(maximumRetries: 1, schedule: .fixed(10)),
                                 operation: "update", replaySafety: .idempotent)
        await queue.stop()
        let events = await queue.events()
        fixture.clock.advance(10)
        try await queue.start()
        _ = try await nextCompletion(in: events)
        await queue.stop()
        let receipt = try #require(await queue.unacknowledgedCompletions().first)
        guard case .failure(.retriesExhausted) = receipt.outcome else { Issue.record("Expected exhaustion"); return }
        #expect(await transport.requests.count == 2)
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
    }

    @Test
    func testPermanentFailureAndDecodingFailureNeverPersist() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let transport = OfflineTestTransport([.failure(.requestFailed(code: 401, message: "Unauthorized")),
                                              .success(HTTPResult(data: Data("invalid JSON".utf8), statusCode: 200))])
        let queue = fixture.queue(transport: transport)
        try await queue.start()
        for _ in 0..<2 {
            await #expect(throws: JWWNetworkError.self) {
                try await queue.send(template: fixture.template, policy: RetryPolicy(schedule: .fixed(10)),
                                     operation: "update", replaySafety: .idempotent)
            }
        }
        await queue.stop()
        #expect(await transport.requests.count == 2)
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
    }

    @Test
    func testCancellationAndForbiddenCredentials() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let offline = JWWNetworkError.networkError(URLError(.notConnectedToInternet))
        let transport = OfflineTestTransport([.failure(offline), .failure(offline)])
        let queue = fixture.queue(transport: transport)
        try await queue.start()
        let secretRequest = StaticRequestFake(url: fixture.snapshot.url, headers: [.authorization: "Bearer secret"])
        await #expect(throws: OfflineQueueError.self) {
            try await queue.send(template: secretRequest, policy: RetryPolicy(schedule: .fixed(10)), operation: "test", replaySafety: .idempotent)
        }
        let submission = try await queue.send(template: fixture.template, policy: RetryPolicy(schedule: .fixed(10)),
                                               operation: "test", replaySafety: .idempotent)
        guard case .queued(let id) = submission else { Issue.record("Expected queued request"); return }
        try await queue.cancel(id)
        await queue.stop()
        let receipt = try #require(await queue.unacknowledgedCompletions().first)
        guard case .failure(.cancelled) = receipt.outcome else { Issue.record("Expected cancellation"); return }
        #expect(await transport.requests.count == 2)
    }

    @Test
    func testFullQueueThrowsInsteadOfClaimingDurability() async throws {
        let fixture = try OfflineQueueFixture(maximumRecords: 1)
        defer { try? fixture.remove() }
        _ = try await fixture.insert()
        let transport = OfflineTestTransport([.failure(.networkError(URLError(.notConnectedToInternet)))])
        let queue = fixture.queue(transport: transport)
        try await queue.start()
        await #expect(throws: OfflineQueueError.self) {
            try await queue.send(template: fixture.template, policy: RetryPolicy(schedule: .fixed(10)), operation: "test", replaySafety: .idempotent)
        }
        await queue.stop()
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).count == 1)
    }
    @Test
    func testWorkerWaitsForBackoffWithoutRestarting() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let offline = JWWNetworkError.networkError(URLError(.timedOut))
        let transport = OfflineTestTransport([.failure(offline), .failure(offline), .success(HTTPResult(data: Data(), statusCode: 204))])
        let sleeper = OfflineTestSleeper()
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 }, sleep: { try await sleeper.sleep($0) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) })
        let delays = await sleeper.delays
        let events = await queue.events()
        try await queue.start()
        _ = try await queue.send(template: fixture.template,
                                 policy: RetryPolicy(maximumRetries: 2, schedule: .exponential(initialDelay: 5, multiplier: 2, maximumDelay: 60)),
                                 operation: "test", replaySafety: .idempotent)
        #expect(try await nextDelay(in: delays) == 5)
        #expect(await transport.requests.count == 1)
        fixture.clock.advance(5)
        await sleeper.resume()
        #expect(try await nextDelay(in: delays) == 10)
        #expect(await transport.requests.count == 2)
        fixture.clock.advance(10)
        await sleeper.resume()
        _ = try await nextCompletion(in: events)
        await queue.stop()
        #expect(await transport.requests.count == 3)
    }
    @Test
    func testLateSuccessCannotOverwriteCancellation() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let transport = OfflineBlockedTransport()
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 },
                                        sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) })
        try await queue.start()
        let submission = try await queue.send(template: fixture.template, policy: RetryPolicy(schedule: .fixed(10)),
                                               operation: "test", replaySafety: .idempotent)
        guard case .queued(let id) = submission else { Issue.record("Expected a queued operation"); return }
        await queue.stop()
        fixture.clock.advance(10)
        try await queue.start()
        _ = try await nextDelay(in: transport.started)
        try await queue.cancel(id)
        await transport.finish()
        await queue.stop()
        let receipt = try #require(await queue.unacknowledgedCompletions().first)
        guard case .failure(.cancelled) = receipt.outcome else { Issue.record("Cancellation was overwritten"); return }
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
    }

    @Test
    func testImmediateSuccessIgnoresPersistenceLimitsAndHeaderAllowlist() async throws {
        let fixture = try OfflineQueueFixture(maximumPayloadBytes: 512)
        defer { try? fixture.remove() }
        let value = String(repeating: "a", count: 1_024)
        let data = try JSONEncoder().encode(NetworkResponseFake(value: value))
        let transport = OfflineTestTransport([.success(HTTPResult(data: data, statusCode: 200))])
        let queue = fixture.queue(transport: transport)
        let template = StaticRequestFake(url: fixture.snapshot.url, body: Data(repeating: 1, count: 1_024),
                                         headers: [.authorization: "Bearer transient", HTTPRequestHeaderKey("X-Client-Version"): "1"])
        try await queue.start()
        let result = try await queue.send(template: template, policy: RetryPolicy(schedule: .fixed(10)),
                                          operation: "test", replaySafety: .idempotencyKey("stable"))
        guard case .completed(let output) = result else { Issue.record("Expected immediate success"); return }
        #expect(output.value == value)
        #expect(await transport.requests.first?.headers["Authorization"] == "Bearer transient")
        #expect(await transport.requests.first?.headers["X-Client-Version"] == "1")
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
        await queue.stop()
    }

    @Test
    func testRestartWaitsForStoppingWorkerAndSchedulesPendingWork() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let transport = OfflineBlockedTransport()
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 },
                                        sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) })
        try await queue.start()
        _ = try await queue.send(template: fixture.template, policy: RetryPolicy(schedule: .fixed(10)),
                                 operation: "first", replaySafety: .idempotent)
        await queue.stop()
        _ = try await fixture.insert()
        fixture.clock.advance(10)
        try await queue.start()
        _ = try await nextDelay(in: transport.started)
        let stop = Task { await queue.stop() }
        _ = try await nextDelay(in: transport.cancelled)
        let restart = Task { try await queue.start() }
        await transport.finish()
        await stop.value
        try await restart.value
        _ = try await nextDelay(in: transport.started)
        await transport.finish()
        await queue.stop()
        #expect(try await queue.unacknowledgedCompletions().count == 2)
    }

    @Test
    func testSubmissionDuringIdleTransitionPreservesWake() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let gate = OfflineTestGate()
        let transport = OfflineTestTransport([.failure(.networkError(URLError(.notConnectedToInternet))),
                                              .success(HTTPResult(data: Data(), statusCode: 204))])
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 },
                                        sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) }, nextDeadline: {
            let deadline = try await fixture.store.nextDeadline(accountID: fixture.configuration.accountID)
            await gate.wait()
            return deadline
        })
        let events = await queue.events()
        try await queue.start()
        _ = try await nextDelay(in: gate.entered)
        let result = try await queue.send(template: fixture.template, policy: RetryPolicy(schedule: .fixed(10)),
                                          operation: "test", replaySafety: .idempotent)
        guard case .queued(let id) = result else { Issue.record("Expected queued work"); return }
        fixture.clock.advance(10)
        await gate.release()
        #expect(try await nextCompletion(in: events) == id)
        await queue.stop()
        #expect(await transport.requests.count == 2)
    }

    @Test
    func testCancellationDuringReservationPreventsTransport() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let id = try await fixture.insert()
        fixture.clock.advance(10)
        let gate = OfflineTestGate()
        let sleeper = OfflineTestSleeper()
        let transport = OfflineTestTransport([])
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 }, sleep: { try await sleeper.sleep($0) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) },
                                        reserveAttempt: { id, date in
            let reserved = try await fixture.store.reserve(id, recoveryDate: date, accountID: fixture.configuration.accountID)
            await gate.wait()
            return reserved
        })
        try await queue.start()
        _ = try await nextDelay(in: gate.entered)
        try await queue.cancel(id)
        await gate.release()
        _ = try await nextDelay(in: sleeper.delays)
        await queue.stop()
        #expect(await transport.requests.isEmpty)
        let receipt = try #require(await queue.unacknowledgedCompletions().first)
        guard case .failure(.cancelled) = receipt.outcome else { Issue.record("Expected cancellation"); return }
    }

    @Test
    func testExpirationDuringReservationPreventsTransport() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let id = try await fixture.insert(policy: RetryPolicy(schedule: .fixed(10), maximumAge: 15))
        fixture.clock.advance(10)
        let gate = OfflineTestGate()
        let transport = OfflineTestTransport([])
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 },
                                        sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) },
                                        reserveAttempt: { id, date in
            let reserved = try await fixture.store.reserve(id, recoveryDate: date, accountID: fixture.configuration.accountID)
            await gate.wait()
            return reserved
        })
        let events = await queue.events()
        try await queue.start()
        _ = try await nextDelay(in: gate.entered)
        fixture.clock.advance(6)
        await gate.release()
        #expect(try await nextCompletion(in: events) == id)
        await queue.stop()
        #expect(await transport.requests.isEmpty)
        let receipt = try #require(await queue.unacknowledgedCompletions().first)
        guard case .failure(.expired) = receipt.outcome else { Issue.record("Expected expiration"); return }
    }

    @Test(arguments: [401, 429, 503])
    func testStoppingPreservesTerminalHTTPFailure(status: Int) async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        _ = try await fixture.insert()
        fixture.clock.advance(10)
        let transport = OfflineBlockedTransport(initialFailure: false)
        let sleeper = OfflineTestSleeper()
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 }, sleep: { try await sleeper.sleep($0) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) })
        try await queue.start()
        _ = try await nextDelay(in: transport.started)
        let stop = Task { await queue.stop() }
        _ = try await nextDelay(in: transport.cancelled)
        await transport.finish(error: .requestFailed(code: status, message: "Terminal status"))
        await stop.value
        let receipt = try #require(await queue.unacknowledgedCompletions().first)
        guard case .failure(.httpStatus(let code)) = receipt.outcome else { Issue.record("Expected HTTP failure"); return }
        #expect(code == status)
        try await queue.start()
        _ = try await nextDelay(in: sleeper.delays)
        await queue.stop()
        #expect(await transport.calls == 1)
    }

    @Test(arguments: [URLError.cancelled, URLError.networkConnectionLost])
    func testStoppingPreservesInterruptedRetry(errorCode: URLError.Code) async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        _ = try await fixture.insert()
        fixture.clock.advance(10)
        let transport = OfflineBlockedTransport(initialFailure: false)
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 },
                                        sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) })
        try await queue.start()
        _ = try await nextDelay(in: transport.started)
        let stop = Task { await queue.stop() }
        _ = try await nextDelay(in: transport.cancelled)
        await transport.finish(error: .networkError(URLError(errorCode)))
        await stop.value
        #expect(try await queue.unacknowledgedCompletions().isEmpty)
        let pending = try #require(await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).first)
        #expect(pending.attemptsStarted == 2)
        #expect(pending.nextAttemptAt > fixture.clock.now())
    }

    @Test
    func testShutdownWaitsForStartupRecovery() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        _ = try await fixture.insert()
        fixture.clock.advance(10)
        let recovery = OfflineTestGate()
        let transport = OfflineTestTransport([.success(HTTPResult(data: Data(), statusCode: 204))])
        let sleeper = OfflineTestSleeper()
        let queue = OfflineRequestQueue(client: fixture.client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 }, sleep: { try await sleeper.sleep($0) },
                                        transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) }, recover: {
            await recovery.wait()
            try await fixture.store.recover(configuration: fixture.configuration, now: fixture.clock.now())
        })
        let start = Task { try await queue.start() }
        _ = try await nextDelay(in: recovery.entered)
        let stop = Task { await queue.stop() }
        let finishedBeforeRecovery = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await stop.value; return true }
            group.addTask {
                try? await Task.sleep(for: .seconds(1))
                return false
            }
            let finished = await group.next() ?? true
            await recovery.release()
            group.cancelAll()
            return finished
        }
        #expect(!finishedBeforeRecovery)
        try await start.value
        await stop.value
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).count == 1)
        #expect(await transport.requests.isEmpty)
        let events = await queue.events()
        try await queue.start()
        _ = try await nextCompletion(in: events)
        await queue.stop()
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: [400, 513])
    func testFailedUploadEnforcesRawAndEncodedSnapshotLimits(bodyBytes: Int) async throws {
        let fixture = try OfflineQueueFixture(maximumPayloadBytes: 512)
        defer { try? fixture.remove() }
        let transport = OfflineTestTransport([.failure(.networkError(URLError(.notConnectedToInternet)))])
        let queue = fixture.queue(transport: transport)
        let template = StaticRequestFake(url: fixture.snapshot.url, method: .post, body: Data(repeating: 1, count: bodyBytes))
        try await queue.start()
        do {
            _ = try await queue.send(template: template, policy: RetryPolicy(schedule: .fixed(10)),
                                     operation: "upload", replaySafety: .idempotent)
            Issue.record("Expected a capacity error")
        } catch OfflineQueueError.capacityExceeded {
            // Oversized uploads cannot claim durable acceptance.
        }
        await queue.stop()
        #expect(await transport.requests.count == 1)
        #expect(try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now()).isEmpty)
    }

}
