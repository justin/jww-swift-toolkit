import Foundation

/// Persists replay-safe requests after connectivity failures and retries them while the app runs.
///
/// Create one owner per store URL, call ``start()`` on launch, and call ``stop()`` before replacing
/// the queue or its account credentials. See <doc:OfflineRequests> for delivery and migration guarantees.
public actor OfflineRequestQueue {
    private let client: HTTPClient
    private let configuration: OfflineQueueConfiguration
    private let store: OfflineQueueStore
    private let now: @Sendable () -> Date
    private let random: @Sendable () -> Double
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let transport: @Sendable (URLRequest, Bool, Date?) async throws -> HTTPResult
    private let recover: @Sendable () async throws -> Void
    private let reserveAttempt: @Sendable (UUID, Date) async throws -> Bool
    private let nextDeadline: @Sendable () async throws -> Date?
    private var startup: (id: UUID, task: Task<Void, any Error>)?
    private var wakeRequested = false
    private var stopping: (id: UUID, task: Task<Void, Never>)?
    private var running = false
    private var processing = false
    private var worker: Task<Void, Never>?
    private var currentAttempt: Task<HTTPResult, any Error>?
    private var currentID: UUID?
    private var observers: [UUID: AsyncStream<OfflineRequestEvent>.Continuation] = [:]

    /// Opens the versioned store without resetting it on failure. Call ``start()`` before submitting retryable work.
    public init(client: HTTPClient, configuration: OfflineQueueConfiguration) throws {
        self.client = client
        self.configuration = configuration
        let store = try OfflineQueueStore.open(configuration: configuration)
        self.store = store
        self.recover = { try await store.recover(configuration: configuration, now: Date()) }
        self.reserveAttempt = { try await store.reserve($0, recoveryDate: $1, accountID: configuration.accountID) }
        self.nextDeadline = { try await store.nextDeadline(accountID: configuration.accountID) }
        self.now = { Date() }
        self.random = { Double.random(in: 0...1) }
        self.sleep = { try await Task.sleep(for: .seconds($0)) }
        self.transport = { request, requiresAuthentication, expiresAt in
            try await client.execute(request: request, requiresAuthentication: requiresAuthentication,
                                      validateReplay: true, expiresAt: expiresAt)
        }
    }

    init(client: HTTPClient, configuration: OfflineQueueConfiguration, store: OfflineQueueStore,
         now: @escaping @Sendable () -> Date, random: @escaping @Sendable () -> Double,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
         transport: @escaping @Sendable (URLRequest, Bool, Date?) async throws -> HTTPResult,
         reserveAttempt: (@Sendable (UUID, Date) async throws -> Bool)? = nil,
         nextDeadline: (@Sendable () async throws -> Date?)? = nil,
         recover: (@Sendable () async throws -> Void)? = nil) {
        self.client = client
        self.configuration = configuration
        self.store = store
        self.now = now
        self.random = random
        self.sleep = sleep
        self.transport = transport
        self.recover = recover ?? { try await store.recover(configuration: configuration, now: now()) }
        self.reserveAttempt = reserveAttempt ?? { try await store.reserve($0, recoveryDate: $1, accountID: configuration.accountID) }
        self.nextDeadline = nextDeadline ?? { try await store.nextDeadline(accountID: configuration.accountID) }
    }

    deinit {
        startup?.task.cancel()
        worker?.cancel()
        currentAttempt?.cancel()
        for observer in observers.values { observer.finish() }
    }

    // MARK: Public Methods
    // ====================================
    // Public Methods
    // ====================================

    /// Recovers pending work and starts scheduling. Safe to call again when the app becomes active.
    /// Waits for an overlapping stop to settle before recovering work.
    /// Storage and migration failures preserve the store and are thrown to the caller.
    public func start() async throws {
        while let stopping {
            await stopping.task.value
            finishStopping(stopping.id)
        }
        if let startup {
            try await startup.task.value
            finishStarting(startup.id)
            return
        }
        guard !running else {
            wake()
            return
        }
        let id = UUID()
        let recover = recover
        let task = Task { try await recover() }
        startup = (id, task)
        do {
            try await task.value
            finishStarting(id)
        } catch {
            if startup?.id == id { startup = nil }
            throw error
        }
    }

    private func finishStarting(_ id: UUID) {
        guard startup?.id == id else { return }
        startup = nil
        guard stopping == nil else { return }
        running = true
        wake()
    }

    /// Waits for startup recovery and the worker's active retry to settle, preserving pending operations.
    /// Also cancel and await any caller-owned initial submissions before changing account credentials.
    public func stop() async {
        if let stopping {
            await stopping.task.value
            finishStopping(stopping.id)
            return
        }
        running = false
        worker?.cancel()
        currentAttempt?.cancel()
        let worker = worker
        let startup = startup?.task
        let id = UUID()
        let task = Task {
            _ = try? await startup?.value
            if let worker { await worker.value }
        }
        stopping = (id, task)
        await task.value
        finishStopping(id)
    }

    private func finishStopping(_ id: UUID) {
        guard stopping?.id == id else { return }
        worker = nil
        startup = nil
        stopping = nil
    }

    /// Attempts delivery immediately, persisting only eligible connectivity failures.
    ///
    /// The supplied replay guarantee applies to the server operation, including any delegate modifications.
    /// `.none` and zero retries use the ordinary client without creating a queue record.
    public func send<T: NetworkRequestTemplate>(template: T, policy: RetryPolicy,
                                                operation: String, replaySafety: RequestReplaySafety) async throws -> RequestSubmission<T.Output>
    where T.Output: Sendable {
        try policy.validate()
        guard policy.isEnabled else { return .completed(try await client.send(template: template)) }
        guard running else { throw OfflineQueueError.stopped }
        guard !operation.isEmpty, operation.utf8.count <= 256 else { throw OfflineQueueError.unsupportedRequest }
        let createdAt = now()
        let request = try await makeRequest(template: template, replaySafety: replaySafety)
        let response: HTTPResult
        do {
            try Task.checkCancellation()
            response = try await transport(request, template is any AuthenticatedRequest, nil)
        } catch {
            try Task.checkCancellation()
            guard running else { throw OfflineQueueError.stopped }
            guard isConnectivityFailure(error) else { throw error }
            guard now() < createdAt.addingTimeInterval(policy.maximumAge) else { throw error }
            let snapshot = try makeSnapshot(request: request, requiresAuthentication: template is any AuthenticatedRequest)
            let id = UUID()
            try await store.sweep(configuration: configuration, now: now())
            try await store.insert(id: id, operation: operation, snapshot: snapshot, policy: policy,
                                   timing: (createdAt, nextDate(policy: policy, retry: 1)), configuration: configuration)
            wake()
            return .queued(id)
        }
        return .completed(try await client.decode(response.data, template: type(of: template)))
    }

    /// Returns durable receipts for this account. Reading does not acknowledge them.
    public func unacknowledgedCompletions() async throws -> [OfflineRequestCompletion] {
        try await store.sweep(configuration: configuration, now: now())
        return try await store.completions(accountID: configuration.accountID)
    }

    /// Deletes a terminal receipt after the app has handled it. Repeated acknowledgments are harmless.
    public func acknowledge(_ id: UUID) async throws {
        try await store.acknowledge(id, accountID: configuration.accountID)
    }

    /// Cancels a persisted operation and retains a cancellation receipt.
    public func cancel(_ id: UUID) async throws {
        if currentID == id {
            currentID = nil
            currentAttempt?.cancel()
        }
        try await complete(id, outcome: .failure(.cancelled))
        wake()
    }

    /// Stops scheduling and cancels all pending operations for this queue's account.
    public func cancelAll() async throws {
        await stop()
        for request in try await store.pendingRequests(configuration: configuration, now: now()) {
            try await complete(request.id, outcome: .failure(.cancelled))
        }
    }

    /// Observes live completion IDs and worker storage failures. Use the durable query to recover missed events.
    /// Cancelling observation does not cancel queued work.
    public func events() -> AsyncStream<OfflineRequestEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<OfflineRequestEvent>.makeStream(bufferingPolicy: .bufferingNewest(100))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    // MARK: Scheduling
    // ====================================
    // Scheduling
    // ====================================

    private func wake(after delay: TimeInterval = 0) {
        guard running else { return }
        guard !processing else {
            wakeRequested = true
            return
        }
        worker?.cancel()
        let sleep = sleep
        worker = Task { [weak self] in
            do {
                // Recheck long deadlines daily; avoid overflowing a clock duration for distant dates.
                if delay > 0 { try await sleep(min(delay, 86_400)) }
                try Task.checkCancellation()
                await self?.drain()
            } catch {
                // Stopping or replacing the timer leaves the persisted schedule unchanged.
            }
        }
    }

    private func drain() async {
        guard running, !processing else { return }
        processing = true
        do {
            // ponytail: one retry at a time; add bounded parallelism only if queue throughput requires it.
            while running, !Task.isCancelled {
                wakeRequested = false
                try await store.sweep(configuration: configuration, now: now())
                guard let request = try await store.nextPendingRequest(configuration: configuration, now: now()) else {
                    let deadline = try await nextDeadline()
                    if wakeRequested { continue }
                    processing = false
                    if let deadline { wake(after: max(0, deadline.timeIntervalSince(now()))) }
                    return
                }
                try await attempt(request)
            }
            processing = false
        } catch {
            processing = false
            running = false
            notify(.storageFailure(error))
        }
    }

    private func attempt(_ request: OfflinePendingRequest) async throws {
        guard request.attemptsStarted <= request.policy.maximumRetries else {
            try await complete(request.id, outcome: .failure(.retriesExhausted))
            return
        }
        let retryDelay = request.policy.delay(retry: request.attemptsStarted + 1, random: random())
        let recoveryDate = now().addingTimeInterval(retryDelay)
        currentID = request.id
        defer {
            currentID = nil
            currentAttempt = nil
        }
        guard try await reserveAttempt(request.id, recoveryDate) else { return }
        guard running, !Task.isCancelled, currentID == request.id else {
            try await store.reschedule(request.id, nextAttemptAt: recoveryDate, accountID: configuration.accountID)
            return
        }
        guard now() < request.expiresAt else {
            try await complete(request.id, outcome: .failure(.expired))
            return
        }
        let transport = transport
        let task = Task {
            try Task.checkCancellation()
            return try await transport(request.snapshot.request, request.snapshot.requiresAuthentication, request.expiresAt)
        }
        currentAttempt = task
        let result: Result<HTTPResult, any Error> = await task.result
        switch result {
        case .success(let response):
            try await complete(request.id, outcome: .success(statusCode: response.statusCode, data: response.data))
        case .failure(let error):
            let cancelled = error is CancellationError || (error as? JWWNetworkError)?.isCancellation == true
            if !running || Task.isCancelled, isConnectivityFailure(error) || cancelled {
                try await store.reschedule(request.id, nextAttemptAt: recoveryDate, accountID: configuration.accountID)
                return
            }
            if isConnectivityFailure(error) {
                if request.attemptsStarted >= request.policy.maximumRetries {
                    try await complete(request.id, outcome: .failure(.retriesExhausted))
                } else if now() >= request.expiresAt {
                    try await complete(request.id, outcome: .failure(.expired))
                } else {
                    try await store.reschedule(request.id,
                                               nextAttemptAt: now().addingTimeInterval(retryDelay),
                                               accountID: configuration.accountID)
                }
            } else {
                try await complete(request.id, outcome: .failure(terminalFailure(error)))
            }
        }
    }

    private func nextDate(policy: RetryPolicy, retry: Int) -> Date {
        now().addingTimeInterval(policy.delay(retry: retry, random: random()))
    }

    private func complete(_ id: UUID, outcome: OfflineRequestCompletion.Outcome) async throws {
        if try await store.finish(id, outcome: outcome, configuration: configuration, now: now()) {
            notify(.completed(id))
        }
    }

    private func notify(_ event: OfflineRequestEvent) {
        for observer in observers.values { observer.yield(event) }
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    // MARK: Request Preparation
    // ====================================
    // Request Preparation
    // ====================================

    private func makeRequest<T: NetworkRequestTemplate>(template: T,
                                                        replaySafety: RequestReplaySafety) async throws -> URLRequest {
        var request = try await NetworkRequestBuilder(template: template).build(for: client, includeAuthentication: false)
        if case .idempotencyKey(let key) = replaySafety {
            guard !key.isEmpty, key.utf8.count <= 256, !key.contains("\r"), !key.contains("\n") else {
                throw OfflineQueueError.unsupportedRequest
            }
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }

    private func makeSnapshot(request: URLRequest, requiresAuthentication: Bool) throws -> OfflineRequestSnapshot {
        guard let url = request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, request.httpBodyStream == nil else { throw OfflineQueueError.unsupportedRequest }
        let headers = request.allHTTPHeaderFields ?? [:]
        let forbidden: Set<String> = ["authorization", "proxy-authorization", "cookie", "set-cookie"]
        guard headers.keys.allSatisfy({ configuration.allowedHeaderNames.contains($0.lowercased()) && !forbidden.contains($0.lowercased()) }) else {
            throw OfflineQueueError.unsupportedRequest
        }
        guard (request.httpBody?.count ?? 0) <= configuration.maximumPayloadBytes else { throw OfflineQueueError.capacityExceeded }
        let snapshot = OfflineRequestSnapshot(version: 1, url: url, method: request.httpMethod ?? "GET", headers: headers,
                                              body: request.httpBody, requiresAuthentication: requiresAuthentication)
        guard try JSONEncoder().encode(snapshot).count <= configuration.maximumPayloadBytes else { throw OfflineQueueError.capacityExceeded }
        return snapshot
    }

    private func isConnectivityFailure(_ error: any Error) -> Bool {
        guard let error = error as? JWWNetworkError else { return false }
        return error.isRetriableError
    }

    private func terminalFailure(_ error: any Error) -> OfflineRequestCompletion.Failure {
        if error is CancellationError || (error as? JWWNetworkError)?.isCancellation == true { return .cancelled }
        guard let error = error as? JWWNetworkError else { return .invalidRequestOrResponse }
        switch error {
        case .untypedError(let underlying) where underlying is OfflineReplayExpired:
            return .expired
        case .authenticationError:
            return .authentication
        case .requestFailed(let code, _):
            return .httpStatus(code)
        case .networkError(let underlying as URLError):
            return underlying.code == .cancelled ? .cancelled : .transport(underlying.code.rawValue)
        default:
            return .invalidRequestOrResponse
        }
    }
}
