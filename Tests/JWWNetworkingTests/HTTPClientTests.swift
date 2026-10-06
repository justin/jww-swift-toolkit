import XCTest
import JWWTestExtensions
@testable import JWWNetworking

/// Tests to validate the `HTTPClient` type.
final class HTTPClientTests: NetworkTestCase {
    /// Validate we can send a single request and return a valid payload.
    func testSuccessfulRequest() async throws {
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL, path: "/test", method: .get)
        let fakeResponse = NetworkResponseFake(value: "test-is-valid")
        try network.expect(.init(.get, url: URL(string: "https://localhost/test")!), outcome: .response(try .json(fakeResponse)))

        let result = try await client.send(template: template)

        XCTAssertEqual(result, fakeResponse)
    }

    /// Validate we can send a single request and have it throw an error.
    func testFailedRequest() async throws {
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL, path: "/test", method: .get)
        let error = URLError(.badURL)
        try network.expect(.init(.get, url: URL(string: "https://localhost/test")!), outcome: .failure(error))

        await JWWAssertThrowsError(try await client.send(template: template)) { error in
            guard let error = error as? JWWNetworkError, case .untypedError(let underlying) = error else {
                return XCTFail("Expected an untyped transport error, received \(error)")
            }
            XCTAssertEqual((underlying as? URLError)?.code, .badURL)
        }
    }

    func testHTTPErrorRetainsStatus() async throws {
        let url = URL(string: "https://localhost/rejected")!
        for status in [401, 429, 500] {
            try network.expect(.init(.get, url: url), outcome: .response(.text("server rejected request", statusCode: status)))
            do {
                _ = try await client.send(template: StaticRequestFake(url: url))
                XCTFail("Expected HTTP failure")
            } catch {
                guard case .requestFailed(let code, _) = error else { return XCTFail("Unexpected error: \(error)") }
                XCTAssertEqual(code, status)
            }
        }
    }

    func testMalformedJSONRetainsResponseBytes() async throws {
        let url = URL(string: "https://localhost/malformed")!
        let response = MockHTTPResponse.text("{ invalid JSON", contentType: "application/json")
        try network.expect(.init(.get, url: url), outcome: .response(response))
        do {
            _ = try await client.send(template: StaticRequestFake(url: url))
            XCTFail("Expected decoding failure")
        } catch {
            guard case .decodingError(_, let data, let underlying) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(data, response.data)
            XCTAssertTrue(underlying is DecodingError)
        }
    }
    /// Transport classification must reflect the URLSession error, not an untyped wrapper.
    func testConnectivityErrorClassification() async throws {
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL, path: "/offline", method: .get)
        try await addStubResponse(forTemplate: template, error: URLError(.notConnectedToInternet))
        do {
            _ = try await client.send(template: template)
            XCTFail("Expected a connectivity error")
        } catch {
            XCTAssertTrue(error.isRetriableError)
            XCTAssertTrue(error.isNetworkIssue)
        }
    }

    /// Disabling retries uses the ordinary transport and leaves the durable store empty.
    func testNoneDoesNotPersist() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL, path: "/once", method: .get)
        try await addStubResponse(forTemplate: template, error: URLError(.notConnectedToInternet))
        let queue = try OfflineRequestQueue(client: client, configuration: fixture.configuration)
        do {
            _ = try await queue.send(template: template, policy: RetryPolicy(schedule: .none), operation: "test", replaySafety: .idempotent)
            XCTFail("Expected the original connectivity failure")
        } catch let error as JWWNetworkError {
            XCTAssertTrue(error.isNetworkIssue)
        }
        let pending = try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now())
        XCTAssertTrue(pending.isEmpty)
    }
    /// Replay traverses the real URLSession transport with a fresh bearer token and stable operation key.
    func testReplayRefreshesAuthentication() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let authentication = OfflineTestAuthentication()
        let delegate = OfflineRecordingDelegate()
        let client = HTTPClient(configuration: .init(baseURL: nil, authentication: authentication), session: session, delegate: delegate)
        let queue = OfflineRequestQueue(client: client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 },
                                        sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                        transport: { request, requiresAuthentication, expiresAt in
            try await client.execute(request: request, requiresAuthentication: requiresAuthentication,
                                      validateReplay: true, expiresAt: expiresAt, now: { fixture.clock.now() })
        })
        let template = OfflineAuthenticatedRequest(url: fixture.snapshot.url)
        try await addStubResponse(forTemplate: template, error: URLError(.notConnectedToInternet))
        try await queue.start()
        let result = try await queue.send(template: template, policy: RetryPolicy(schedule: .fixed(10)), operation: "auth",
                                           replaySafety: .idempotencyKey("stable-key"))
        guard case .queued = result else { XCTFail("Expected persistence"); return }
        await queue.stop()
        let pending = try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now())
        XCTAssertNil(pending.first?.snapshot.headers["Authorization"])
        await authentication.replaceToken()
        try await addStubResponse(forTemplate: template, statusCode: 200, response: NetworkResponseFake(value: "success"))
        let events = await queue.events()
        fixture.clock.advance(10)
        try await queue.start()
        _ = try await nextCompletion(in: events)
        await queue.stop()
        XCTAssertEqual(delegate.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer first-token", "Bearer second-token"])
        XCTAssertEqual(delegate.requests.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }, ["stable-key", "stable-key"])
        XCTAssertEqual(delegate.requests.map(\.httpShouldHandleCookies), [true, false])
    }

    /// A base-typed template retains its subclass's custom response decoder on both immediate paths.
    func testSubclassDecoderDispatch() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let template: BaseDecodingRequest = SubclassDecodingRequest(url: fixture.snapshot.url)
        try await addStubResponse(forTemplate: template, statusCode: 200, response: NetworkResponseFake(value: "wire"))
        let immediate = try await client.send(template: template)
        XCTAssertEqual(immediate.value, "subclass")
        let queue = try OfflineRequestQueue(client: client, configuration: fixture.configuration)
        try await queue.start()
        let result = try await queue.send(template: template, policy: RetryPolicy(schedule: .fixed(10)),
                                          operation: "test", replaySafety: .idempotent)
        await queue.stop()
        guard case .completed(let output) = result else { XCTFail("Expected immediate response"); return }
        XCTAssertEqual(output.value, "subclass")
    }

    /// Shutdown during cancellation-aware preparation preserves the durable operation.
    func testStopDuringAuthenticationAndDelegatePreparation() async throws {
        for authenticating in [true, false] {
            let fixture = try OfflineQueueFixture()
            defer { try? fixture.remove() }
            _ = try await fixture.insert()
            fixture.clock.advance(10)
            let sleeper = OfflineTestSleeper()
            let authentication: any AuthenticationProvider = authenticating
                ? OfflinePreparingAuthentication { try await sleeper.sleep(3_600) } : OfflineTestAuthentication()
            let delegate: any HTTPClientDelegate = authenticating
                ? OfflineRecordingDelegate() : OfflinePreparingDelegate { try await sleeper.sleep(3_600) }
            let client = HTTPClient(configuration: .init(baseURL: nil, authentication: authentication), session: session, delegate: delegate)
            let queue = OfflineRequestQueue(client: client, configuration: fixture.configuration, store: fixture.store,
                                            now: { fixture.clock.now() }, random: { 0.5 },
                                            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                            transport: { request, requiresAuthentication, expiresAt in
                try await client.execute(request: request, requiresAuthentication: requiresAuthentication,
                                      validateReplay: true, expiresAt: expiresAt, now: { fixture.clock.now() })
            })
            try await queue.start()
            _ = try await nextDelay(in: sleeper.delays)
            await queue.stop()
            let pending = try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now())
            XCTAssertEqual(pending.count, 1)
            XCTAssertEqual(pending.first?.attemptsStarted, 2)
            let receipts = try await queue.unacknowledgedCompletions()
            XCTAssertTrue(receipts.isEmpty)
        }
    }

    /// Explicit credentials take precedence whether or not an authentication provider exists.
    func testRetryEnabledRequestPreservesExplicitAuthorization() async throws {
        for hasProvider in [true, false] {
            let fixture = try OfflineQueueFixture()
            defer { try? fixture.remove() }
            let authentication: (any AuthenticationProvider)? = hasProvider ? OfflineTestAuthentication() : nil
            let delegate = OfflineRecordingDelegate()
            let client = HTTPClient(configuration: .init(baseURL: nil, authentication: authentication), session: session, delegate: delegate)
            let template = OfflineAuthenticatedRequest(url: fixture.snapshot.url, headers: [.authorization: "Bearer explicit"])
            try await addStubResponse(forTemplate: template, statusCode: 200, response: NetworkResponseFake(value: "success"))
            let ordinary = try await client.send(template: template)
            let queue = try OfflineRequestQueue(client: client, configuration: fixture.configuration)
            try await queue.start()
            let result = try await queue.send(template: template, policy: RetryPolicy(schedule: .fixed(10)),
                                              operation: "test", replaySafety: .idempotent)
            await queue.stop()
            guard case .completed(let response) = result else { XCTFail("Expected immediate success"); return }
            XCTAssertEqual(response, ordinary)
            XCTAssertEqual(delegate.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer explicit", "Bearer explicit"])
        }
    }

    /// Preparation wrappers retain cancellation identity without changing genuine authentication failures.
    func testPreparationCancellationClassification() {
        XCTAssertTrue(JWWNetworkError.authenticationError(CancellationError()).isCancellation)
        XCTAssertTrue(JWWNetworkError.untypedError(error: URLError(.cancelled)).isCancellation)
        XCTAssertTrue(JWWNetworkError.authenticationError(JWWNetworkError.untypedError(error: CancellationError())).isCancellation)
        XCTAssertFalse(JWWNetworkError.authenticationError(URLError(.userAuthenticationRequired)).isCancellation)
        XCTAssertFalse(JWWNetworkError.requestFailed(code: 401, message: "Unauthorized").isCancellation)
    }

    /// Delegate credentials are generated again on replay and never enter the persisted snapshot.
    func testDelegateAuthenticationWithoutProvider() async throws {
        let fixture = try OfflineQueueFixture()
        defer { try? fixture.remove() }
        let delegate = OfflineRecordingDelegate(authorization: "Bearer first")
        let client = HTTPClient(configuration: .init(baseURL: nil), session: session, delegate: delegate)
        let queue = OfflineRequestQueue(client: client, configuration: fixture.configuration, store: fixture.store,
                                        now: { fixture.clock.now() }, random: { 0.5 },
                                        sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                        transport: { request, requiresAuthentication, expiresAt in
            try await client.execute(request: request, requiresAuthentication: requiresAuthentication,
                                      validateReplay: true, expiresAt: expiresAt, now: { fixture.clock.now() })
        })
        let template = OfflineAuthenticatedRequest(url: fixture.snapshot.url)
        try await addStubResponse(forTemplate: template, error: URLError(.notConnectedToInternet))
        try await queue.start()
        let submission = try await queue.send(template: template, policy: RetryPolicy(schedule: .fixed(10)),
                                               operation: "test", replaySafety: .idempotent)
        guard case .queued(let id) = submission else { XCTFail("Expected a queued request"); return }
        await queue.stop()
        let pending = try await fixture.store.pendingRequests(configuration: fixture.configuration, now: fixture.clock.now())
        XCTAssertNil(pending.first?.snapshot.headers["Authorization"])
        delegate.replaceAuthorization("Bearer second")
        try await addStubResponse(forTemplate: template, statusCode: 200, response: NetworkResponseFake(value: "success"))
        let events = await queue.events()
        fixture.clock.advance(10)
        try await queue.start()
        let completed = try await nextCompletion(in: events)
        XCTAssertEqual(completed, id)
        await queue.stop()
        XCTAssertEqual(delegate.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer first", "Bearer second"])
    }

    /// Expiration during either preparation stage produces a receipt without reaching URLSession.
    func testReplayExpirationDuringPreparation() async throws {
        for authenticating in [true, false] {
            let fixture = try OfflineQueueFixture()
            defer { try? fixture.remove() }
            let id = try await fixture.insert(policy: RetryPolicy(schedule: .fixed(10), maximumAge: 15))
            fixture.clock.advance(10)
            let gate = OfflineTestGate()
            let authentication: any AuthenticationProvider = authenticating
                ? OfflinePreparingAuthentication { await gate.wait() } : OfflineTestAuthentication()
            let delegate: any HTTPClientDelegate = authenticating
                ? OfflineRecordingDelegate() : OfflinePreparingDelegate { await gate.wait() }
            let client = HTTPClient(configuration: .init(baseURL: nil, authentication: authentication), session: session, delegate: delegate)
            let queue = OfflineRequestQueue(client: client, configuration: fixture.configuration, store: fixture.store,
                                            now: { fixture.clock.now() }, random: { 0.5 },
                                            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                                            transport: { request, requiresAuthentication, expiresAt in
                try await client.execute(request: request, requiresAuthentication: requiresAuthentication,
                                          validateReplay: true, expiresAt: expiresAt, now: { fixture.clock.now() })
            })
            // A successful stub makes any accidental transmission observable as a success receipt.
            addStubResponse(forURL: fixture.snapshot.url, statusCode: 200,
                             responseData: try JSONEncoder().encode(NetworkResponseFake(value: "must not send")))
            let events = await queue.events()
            try await queue.start()
            _ = try await nextDelay(in: gate.entered)
            fixture.clock.advance(6)
            await gate.release()
            let completed = try await nextCompletion(in: events)
            XCTAssertEqual(completed, id)
            await queue.stop()
            let receipts = try await queue.unacknowledgedCompletions()
            let receipt = try XCTUnwrap(receipts.first)
            guard case .failure(.expired) = receipt.outcome else { XCTFail("Expected expiration"); return }
        }
    }

}
