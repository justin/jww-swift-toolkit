import Foundation
import Synchronization

/// A thin owner of Foundation upload/download tasks, including background-session reconnection.
///
/// Create one owner per background identifier and install callbacks before reconnecting. Journal intent before
/// submitting; retain immutable upload files until completion. This type does not persist, retry, refresh tokens,
/// or schedule work. Background sessions follow redirects regardless of redirect-delegate implementations.
public final class HTTPTransferSession: Sendable {
    /// A read-only task projection for reconciling an application's journal after relaunch.
    public struct Snapshot: Sendable {
        /// Foundation session identifier; nil for an in-process session.
        public let sessionIdentifier: String?
        /// Foundation task identifier, scoped to its session.
        public let taskIdentifier: Int
        /// Caller-supplied opaque identity. Nil identifies an unrecognized restored task.
        public let id: String?
        /// Whether the task sends a file or receives one.
        public let kind: Kind
        /// Current Foundation task state.
        public let state: URLSessionTask.State
        /// Body bytes sent so far.
        public let sent: HTTPTransferProgress
        /// Body bytes received so far.
        public let received: HTTPTransferProgress

        init(task: URLSessionTask, session: URLSession) {
            sessionIdentifier = session.configuration.identifier
            taskIdentifier = task.taskIdentifier
            id = task.taskDescription
            kind = task is URLSessionUploadTask ? .upload : .download
            state = task.state
            sent = .init(direction: .upload, completed: task.countOfBytesSent, expected: task.countOfBytesExpectedToSend)
            received = .init(direction: .download, completed: task.countOfBytesReceived, expected: task.countOfBytesExpectedToReceive)
        }
    }

    /// The two file operations supported by this adapter.
    public enum Kind: Sendable {
        /// Upload an app-owned file.
        case upload
        /// Download and synchronously claim a temporary file.
        case download
    }

    /// A transport result; application validation and publication remain separate.
    public enum Completion: Sendable {
        /// The caller successfully claimed the file. No temporary Foundation URL escapes the callback.
        case download(HTTPURLResponse)
        /// The complete, bounded response to an upload. Persist a decoded receipt before acknowledging background events.
        case upload(HTTPURLResponse, Data)
    }

    /// Fixed synchronous callbacks delivered on one serial Foundation delegate queue.
    ///
    /// Return promptly. Arrange any asynchronous app processing yourself and wait for it before calling UIKit's
    /// background completion handler. Callbacks must not synchronously wait for that delegate queue.
    public struct Callbacks: Sendable {
        let progress: @Sendable (Snapshot, HTTPTransferProgress) -> Void
        let claimDownload: @Sendable (Snapshot, HTTPURLResponse, URL) throws -> Void
        let completed: @Sendable (Snapshot, Result<Completion, JWWNetworkError>) -> Void
        let finishedBackgroundEvents: @Sendable () -> Void

        /// Installs handlers before a session can deliver restored events.
        ///
        /// `claimDownload` must move or copy the file into caller-selected storage before returning, or throw.
        /// `completed` is delivered once per task in this process, not exactly once across process termination.
        /// `finishedBackgroundEvents` signals Foundation's event boundary, not completion of app-owned work.
        public init(progress: @escaping @Sendable (Snapshot, HTTPTransferProgress) -> Void = { _, _ in },
                    claimDownload: @escaping @Sendable (Snapshot, HTTPURLResponse, URL) throws -> Void,
                    completed: @escaping @Sendable (Snapshot, Result<Completion, JWWNetworkError>) -> Void,
                    finishedBackgroundEvents: @escaping @Sendable () -> Void = {}) {
            self.progress = progress
            self.claimDownload = claimDownload
            self.completed = completed
            self.finishedBackgroundEvents = finishedBackgroundEvents
        }
    }

    private let client: HTTPClient
    private let session: URLSession
    private let closed = Mutex(false)

    /// Creates a session using the supplied configuration and fixed callbacks.
    ///
    /// Pass `.background(withIdentifier:)` for system-owned transfers; default/ephemeral configurations are useful
    /// for in-process transfers and deterministic tests. Preparation uses `client`, but transport uses this session.
    /// The response limit defaults to 1 MiB and must be positive. An oversized upload response fails without retry,
    /// even if the server committed the upload. Account, destination, and cellular policies belong to the caller.
    public init(client: HTTPClient, configuration: URLSessionConfiguration, callbacks: Callbacks,
                maximumUploadResponseBytes: Int = 1_048_576) throws(JWWNetworkError) {
        guard maximumUploadResponseBytes > 0 else { throw .invalidRequest }
        self.client = client
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "JWWNetworking.file-transfers"
        session = URLSession(configuration: configuration,
                             delegate: HTTPTransferDelegate(callbacks: callbacks, maximumResponseBytes: maximumUploadResponseBytes),
                             delegateQueue: queue)
    }

    /// Prepares and submits a download, assigning its journal identity before resuming.
    /// Cancellation of this submission after it returns does not cancel the durable transfer; use `cancel(id:)`.
    @discardableResult
    public func startDownload(template: some NetworkRequestTemplate, id: String) async throws(JWWNetworkError) -> Snapshot {
        guard !id.isEmpty else { throw .invalidRequest }
        let request = try await client.prepareTransfer(template)
        return try submit(id: id) { session.downloadTask(with: request) }
    }

    /// Prepares and submits an immutable file body; conflicting template/delegate bodies are rejected.
    /// Cancellation cannot undo a remote commit. This operation never automatically retries an ambiguous result.
    @discardableResult
    public func startUpload(template: some NetworkRequestTemplate, fromFile file: URL, id: String)
        async throws(JWWNetworkError) -> Snapshot {
        guard !id.isEmpty else { throw .invalidRequest }
        let request = try await client.prepareTransfer(template)
        try HTTPClient.validateUpload(request, file: file)
        return try submit(id: id) { session.uploadTask(with: request, fromFile: file) }
    }

    /// Includes suspended/running restored tasks. Reconcile unknown identities against the app's account journal.
    public func tasks() async -> [Snapshot] {
        await session.allTasks.map { Snapshot(task: $0, session: session) }
    }

    /// Cancels all submitted tasks carrying this identity; it does not remove remote objects or local files.
    public func cancel(id: String) async {
        for task in await session.allTasks where task.taskDescription == id { task.cancel() }
    }

    /// Releases the Foundation session after finishing outstanding work, or cancels it when explicitly requested.
    /// No further submissions are accepted. Keep the owner alive for the application's background session lifetime.
    public func invalidate(cancelOutstanding: Bool = false) {
        closed.withLock { closed in
            guard !closed else { return }
            closed = true
            if cancelOutstanding { session.invalidateAndCancel() } else { session.finishTasksAndInvalidate() }
        }
    }

    private func submit(id: String, create: () -> URLSessionTask) throws(JWWNetworkError) -> Snapshot {
        do {
            return try closed.withLock { closed in
                guard !closed else { throw JWWNetworkError.invalidRequest }
                try Task.checkCancellation()
                let task = create()
                task.taskDescription = id
                task.resume()
                return Snapshot(task: task, session: session)
            }
        } catch { throw error as? JWWNetworkError ?? .networkError(error) }
    }
}
