import Foundation
import Testing
@testable import JWWTestExtensions

@Suite(.timeLimit(.minutes(1)))
struct MockNetworkTests {
    private let url = URL(string: "https://mock.invalid/items?q=1")!

    @Test
    func testConcurrentSessionsAreIsolated() async throws {
        let first = MockNetwork()
        let second = MockNetwork()
        defer {
            first.close()
            second.close()
        }
        try first.expect(.init(.get, url: url), outcome: .response(.text("first")))
        try second.expect(.init(.get, url: url), outcome: .response(.text("second")))
        async let firstResult = first.session.data(from: url)
        async let secondResult = second.session.data(from: url)
        let (one, two) = try await (firstResult, secondResult)
        #expect(String(data: one.0, encoding: .utf8) == "first")
        #expect(String(data: two.0, encoding: .utf8) == "second")
        try first.verify()
        try second.verify()
        first.close()
        try second.expect(.init(.get, url: url), outcome: .response(.text("still active")))
        let (data, _) = try await second.session.data(from: url)
        #expect(String(data: data, encoding: .utf8) == "still active")
        try second.verify()
    }

    @Test(arguments: [
        "http://mock.invalid/items?q=1", "https://wrong.invalid/items?q=1",
        "https://mock.invalid:8080/items?q=1", "https://mock.invalid/other?q=1",
        "https://mock.invalid/items?q=2"
    ])
    func testWrongURLFailsAndRemainsAVerificationFailure(actual: String) async throws {
        let network = MockNetwork()
        defer { network.close() }
        try network.expect(.init(.get, url: url), outcome: .response(.text("wrong fixture")), fileID: "Fixture.swift", line: 42)
        await #expect(throws: (any Error).self) {
            try await network.session.data(from: URL(string: actual)!)
        }
        do {
            try network.verify()
            Issue.record("Verification accepted an unexpected request")
        } catch {
            #expect(String(describing: error).contains("Fixture.swift:42"))
            #expect(String(describing: error).contains(actual))
        }
    }

    @Test(arguments: ["method", "header", "body", "query order"])
    func testRequestConstraintsFail(field: String) async throws {
        let network = MockNetwork()
        defer { network.close() }
        let expectedURL = URL(string: "https://mock.invalid/items?a=1&b=2")!
        try network.expect(.init(.post, url: expectedURL, headers: ["X-Test": "expected"], body: Data("expected".utf8)),
                           outcome: .response(.init()))
        var request = URLRequest(url: expectedURL)
        request.httpMethod = field == "method" ? "DELETE" : "POST"
        request.setValue(field == "header" ? "wrong" : "expected", forHTTPHeaderField: "X-Test")
        request.httpBody = Data((field == "body" ? "wrong" : "expected").utf8)
        if field == "query order" { request.url = URL(string: "https://mock.invalid/items?b=2&a=1")! }
        await #expect(throws: (any Error).self) { try await network.session.data(for: request) }
        #expect(throws: MockNetworkError.self) { try network.verify() }
    }

    @Test(arguments: [false, true])
    func testRecordsBodyAndMatchesHeaderNamesCaseInsensitively(streamed: Bool) async throws {
        try await withMockNetwork { network in
            let body = Data("request body".utf8)
            try network.expect(.init(.post, url: url, headers: ["x-test": "value"], body: body), outcome: .response(.init(statusCode: 204)))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("value", forHTTPHeaderField: "X-Test")
            if streamed { request.httpBodyStream = InputStream(data: body) } else { request.httpBody = body }
            let (data, response) = try await network.session.data(for: request)
            #expect(data.isEmpty)
            #expect((response as? HTTPURLResponse)?.statusCode == 204)
            #expect(network.requests.count == 1)
            #expect(network.requests.first?.httpBody == body)
            #expect(network.requests.first?.value(forHTTPHeaderField: MockNetworkRegistry.header) == nil)
        }
    }

    @Test
    func testRemovalUsesRegistrationIdentity() async throws {
        try await withMockNetwork { network in
            try network.expect(.init(.get, url: url), outcome: .response(.text("first")))
            let second = try network.expect(.init(.get, url: url), outcome: .response(.text("second")))
            network.remove(second)
            let (data, _) = try await network.session.data(from: url)
            #expect(String(data: data, encoding: .utf8) == "first")
        }
    }

    @Test
    func testSequenceAndExhaustion() async throws {
        let network = MockNetwork()
        defer { network.close() }
        try network.expect(.init(.get, url: url), outcomes: [.failure(URLError(.timedOut)), .response(.text("recovered"))])
        await #expect(throws: URLError.self) { try await network.session.data(from: url) }
        let (data, _) = try await network.session.data(from: url)
        #expect(String(data: data, encoding: .utf8) == "recovered")
        try network.verify()
        await #expect(throws: (any Error).self) { try await network.session.data(from: url) }
        #expect(throws: MockNetworkError.self) { try network.verify() }
    }

    @Test
    func testCountsAndSetupErrors() async throws {
        try await withMockNetwork { network in
            #expect(throws: MockNetworkError.self) { try network.expect(.init(.get, url: url), outcome: .response(.init()), count: 0) }
            #expect(throws: MockNetworkError.self) { try network.expect(.init(.get, url: url), outcomes: []) }
            try network.expect(.init(.get, url: url), outcome: .response(.init(statusCode: 299)), count: 2)
            #expect(throws: MockNetworkError.self) { try network.verify() }
            for _ in 0..<2 {
                let (_, response) = try await network.session.data(from: url)
                #expect((response as? HTTPURLResponse)?.statusCode == 299)
            }
        }
    }

    @Test
    func testTransportErrorPreservesDetails() async throws {
        try await withMockNetwork { network in
            let failure = NSError(domain: "FixtureTransport", code: 73, userInfo: [NSLocalizedDescriptionKey: "fixture failure"])
            try network.expect(.init(.get, url: url), outcome: .failure(failure))
            do {
                _ = try await network.session.data(from: url)
                Issue.record("Expected transport failure")
            } catch {
                let received = error as NSError
                #expect(received.domain == failure.domain)
                #expect(received.code == failure.code)
                #expect(received.localizedDescription == failure.localizedDescription)
            }
        }
    }

    @Test
    func testMissingExpectationsFailClosed() async throws {
        let network = MockNetwork()
        defer { network.close() }
        await #expect(throws: (any Error).self) { try await network.session.data(from: url) }
        #expect(throws: MockNetworkError.self) { try network.verify() }
    }

    @Test
    func testScopeVerifiesUnusedExpectations() async throws {
        await #expect(throws: MockNetworkError.self) {
            try await withMockNetwork { network in
                try network.expect(.init(.get, url: url), outcome: .response(.init()))
            }
        }
    }

    @Test
    func testScopePreservesBodyErrorAndCloses() async throws {
        enum BodyError: Error { case expected }
        var escaped: MockNetwork?
        await #expect(throws: BodyError.self) {
            try await withMockNetwork { network in
                escaped = network
                try network.expect(.init(.get, url: url), outcome: .response(.init()))
                throw BodyError.expected
            }
        }
        let network = try #require(escaped)
        #expect(throws: MockNetworkError.self) { try network.expect(.init(.get, url: url), outcome: .response(.init())) }
        #expect(throws: MockNetworkError.self) { try network.verify() }
    }

    @Test(arguments: [false, true])
    func testCancellationWhileResponseIsHeld(closeHarness: Bool) async throws {
        let network = MockNetwork()
        defer { network.close() }
        let gate = MockResponseGate()
        try network.expect(.init(.get, url: url), outcome: .response(.text("held")), gate: gate)
        let task = Task { try await network.session.data(from: url) }
        try await gate.waitUntilRequested()
        try network.verify()
        if closeHarness { network.close() } else { task.cancel() }
        do {
            _ = try await task.value
            Issue.record("Cancelled request delivered a response")
        } catch {
            #expect((error as? URLError)?.code == .cancelled)
        }
        gate.release()
    }

    @Test
    func testGateReleaseDeliversResponse() async throws {
        try await withMockNetwork { network in
            let gate = MockResponseGate()
            try network.expect(.init(.get, url: url), outcome: .response(.text("released")), gate: gate)
            let task = Task { try await network.session.data(from: url) }
            try await gate.waitUntilRequested()
            gate.release()
            let (data, _) = try await task.value
            #expect(String(data: data, encoding: .utf8) == "released")
        }
    }

    @Test
    func testConcurrentRequestsConsumeEachOutcomeOnce() async throws {
        try await withMockNetwork { network in
            let outcomes = (0..<20).map { MockOutcome.response(.text(String($0))) }
            try network.expect(.init(.get, url: url), outcomes: outcomes)
            let bodies = try await withThrowingTaskGroup(of: Data.self) { group in
                for _ in outcomes {
                    group.addTask { try await network.session.data(from: url).0 }
                }
                var bodies = Set<Data>()
                for try await body in group { bodies.insert(body) }
                return bodies
            }
            #expect(bodies == Set((0..<20).map { Data(String($0).utf8) }))
            #expect(network.requests.count == 20)
        }
    }

    @Test
    @MainActor
    func testCancelledScopeClosesHarness() async throws {
        let gate = MockResponseGate()
        var escaped: MockNetwork?
        let task = Task {
            try await withMockNetwork { network in
                escaped = network
                try network.expect(.init(.get, url: url), outcome: .response(.init()), gate: gate)
                do {
                    _ = try await network.session.data(from: url)
                } catch {
                    // Let the scope detect cancellation even when the body handles the transport error.
                }
                return network
            }
        }
        try await gate.waitUntilRequested()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let network = try #require(escaped)
        #expect(throws: MockNetworkError.self) { try network.verify() }
        gate.release()
    }

    @Test
    func testGateObserverCanBeCancelled() async throws {
        let gate = MockResponseGate()
        let task = Task { try await gate.waitUntilRequested() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
