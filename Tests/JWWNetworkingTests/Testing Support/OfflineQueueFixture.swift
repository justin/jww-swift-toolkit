import Foundation
import Testing
@testable import JWWNetworking

final class OfflineTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000)

    func now() -> Date { lock.withLock { date } }
    func advance(_ interval: TimeInterval) { lock.withLock { date += interval } }
}

actor OfflineTestTransport {
    private var results: [Result<HTTPResult, JWWNetworkError>]
    private(set) var requests: [OfflineRequestSnapshot] = []

    init(_ results: [Result<HTTPResult, JWWNetworkError>]) { self.results = results }

    func send(_ request: URLRequest, requiresAuthentication: Bool, expiresAt: Date? = nil) throws -> HTTPResult {
        requests.append(OfflineRequestSnapshot(version: 1, url: request.url!, method: request.httpMethod ?? "GET",
                                               headers: request.allHTTPHeaderFields ?? [:], body: request.httpBody,
                                               requiresAuthentication: requiresAuthentication))
        guard !results.isEmpty else { throw JWWNetworkError.invalidRequest }
        return try results.removeFirst().get()
    }
}

struct OfflineQueueFixture {
    let directory: URL
    let configuration: OfflineQueueConfiguration
    let store: OfflineQueueStore
    let clock = OfflineTestClock()
    let client = HTTPClient(configuration: .init(baseURL: nil))

    init(maximumRecords: Int = 1_000, maximumPayloadBytes: Int = 1_048_576,
         maximumStoredBytes: Int = 20_971_520, receiptRetention: TimeInterval = 100) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configuration = try OfflineQueueConfiguration(storeURL: directory.appendingPathComponent("queue.store"), accountID: "account-a",
                                                       maximumRecords: maximumRecords, maximumPayloadBytes: maximumPayloadBytes,
                                                       maximumStoredBytes: maximumStoredBytes, receiptRetention: receiptRetention)
        store = try OfflineQueueStore.open(configuration: configuration)
    }

    var snapshot: OfflineRequestSnapshot {
        OfflineRequestSnapshot(version: 1, url: URL(string: "https://example.invalid/request")!, method: "POST",
                               headers: ["Idempotency-Key": "stable-key"], body: Data("body".utf8), requiresAuthentication: true)
    }

    var template: StaticRequestFake { StaticRequestFake(url: snapshot.url) }

    func queue(transport: OfflineTestTransport) -> OfflineRequestQueue {
        OfflineRequestQueue(client: client, configuration: configuration, store: store, now: { clock.now() }, random: { 0.5 },
                            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                            transport: { try await transport.send($0, requiresAuthentication: $1, expiresAt: $2) })
    }

    func insert(id: UUID = UUID(), policy: RetryPolicy? = nil) async throws -> UUID {
        let policy = try policy ?? RetryPolicy(maximumRetries: 2, schedule: .fixed(10))
        try await store.insert(id: id, operation: "test", snapshot: snapshot, policy: policy,
                               timing: (clock.now(), clock.now().addingTimeInterval(10)), configuration: configuration)
        return id
    }

    func remove() throws { try FileManager.default.removeItem(at: directory) }
}

func nextCompletion(in events: AsyncStream<OfflineRequestEvent>) async throws -> UUID {
    try await withThrowingTaskGroup(of: UUID.self) { group in
        group.addTask {
            for await event in events {
                switch event {
                case .completed(let id): return id
                case .storageFailure(let error): throw error
                }
            }
            throw CancellationError()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(10))
            throw URLError(.timedOut)
        }
        defer { group.cancelAll() }
        return try #require(await group.next())
    }
}

actor OfflineTestAuthentication: AuthenticationProvider {
    var accessToken = "first-token"
    func refreshAccessToken(refreshToken: String) async throws -> String { accessToken }
    func replaceToken() { accessToken = "second-token" }
}

final class OfflineRecordingDelegate: HTTPClientDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [URLRequest] = []
    private var authorization: String?
    var requests: [URLRequest] { lock.withLock { captured } }

    init(authorization: String? = nil) { self.authorization = authorization }

    func replaceAuthorization(_ value: String) { lock.withLock { authorization = value } }

    func client(_ client: HTTPClient, willSendRequest request: inout URLRequest) async throws {
        if let authorization = lock.withLock({ authorization }) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        lock.withLock { captured.append(request) }
    }
}

struct OfflineAuthenticatedRequest: StaticNetworkRequest, AuthenticatedRequest {
    typealias Output = NetworkResponseFake
    let url: URL
    let method = HTTPMethod.post
    let headers: [HTTPRequestHeaderKey: String]
    let body: Data? = nil
    let authenticationType = AuthenticationType.bearer

    init(url: URL, headers: [HTTPRequestHeaderKey: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

actor OfflineTestSleeper {
    let delays: AsyncStream<TimeInterval>
    private let continuation: AsyncStream<TimeInterval>.Continuation
    private var pending: [UUID: CheckedContinuation<Void, any Error>] = [:]

    init() {
        (delays, continuation) = AsyncStream<TimeInterval>.makeStream()
    }

    func sleep(_ delay: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    waiter.resume(throwing: CancellationError())
                } else {
                    pending[id] = waiter
                    continuation.yield(delay)
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func resume() {
        let waiters = pending.values
        pending.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func cancel(_ id: UUID) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

func nextDelay(in delays: AsyncStream<TimeInterval>) async throws -> TimeInterval {
    try await withThrowingTaskGroup(of: TimeInterval.self) { group in
        group.addTask {
            for await delay in delays { return delay }
            throw CancellationError()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(10))
            throw URLError(.timedOut)
        }
        defer { group.cancelAll() }
        return try #require(await group.next())
    }
}

actor OfflineBlockedTransport {
    let started: AsyncStream<TimeInterval>
    private let signal: AsyncStream<TimeInterval>.Continuation
    let cancelled: AsyncStream<TimeInterval>
    private let cancellationSignal: AsyncStream<TimeInterval>.Continuation
    private var continuation: CheckedContinuation<HTTPResult, any Error>?
    private(set) var calls = 0
    private let initialFailure: Bool

    init(initialFailure: Bool = true) {
        self.initialFailure = initialFailure
        (started, signal) = AsyncStream<TimeInterval>.makeStream()
        (cancelled, cancellationSignal) = AsyncStream<TimeInterval>.makeStream()
    }

    func send(_ request: URLRequest, requiresAuthentication: Bool, expiresAt: Date? = nil) async throws -> HTTPResult {
        calls += 1
        if calls == 1, initialFailure { throw JWWNetworkError.networkError(URLError(.notConnectedToInternet)) }
        let cancellationSignal = cancellationSignal
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPResult, any Error>) in
                self.continuation = continuation
                signal.yield(1)
            }
        } onCancel: {
            cancellationSignal.yield(1)
        }
    }

    func finish(error: JWWNetworkError? = nil) {
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: HTTPResult(data: Data(), statusCode: 204))
        }
        continuation = nil
    }
}

/// Pauses an asynchronous operation at a known boundary until the test releases it.
actor OfflineTestGate {
    let entered: AsyncStream<TimeInterval>
    private let signal: AsyncStream<TimeInterval>.Continuation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init() { (entered, signal) = AsyncStream<TimeInterval>.makeStream() }

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            signal.yield(1)
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

actor OfflinePreparingAuthentication: AuthenticationProvider {
    let prepare: @Sendable () async throws -> Void

    init(prepare: @escaping @Sendable () async throws -> Void) { self.prepare = prepare }

    var accessToken: String {
        get async throws {
            try await prepare()
            return "token"
        }
    }

    func refreshAccessToken(refreshToken: String) async throws -> String { try await accessToken }
}

final class OfflinePreparingDelegate: HTTPClientDelegate {
    let prepare: @Sendable () async throws -> Void

    init(prepare: @escaping @Sendable () async throws -> Void) { self.prepare = prepare }

    func client(_ client: HTTPClient, willSendRequest request: inout URLRequest) async throws {
        try await prepare()
    }
}
