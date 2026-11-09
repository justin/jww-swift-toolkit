import Foundation
import Synchronization

/// One dedicated serial delegate queue provides backpressure without blocking the client's other requests.
final class HTTPStreamDelegate: NSObject, URLSessionDataDelegate {
    private struct State {
        var task: URLSessionDataTask?
        var callback: Task<Void, Never>?
        var continuation: CheckedContinuation<Void, any Error>?
        var failure: JWWNetworkError?
        var cancelled = false
    }

    private let state = Mutex(State())
    private let original: URLSession
    private let receiveResponse: @Sendable (HTTPURLResponse) async throws -> Void
    private let receiveData: @Sendable (Data) async throws -> Void

    init(session: URLSession, receiveResponse: @escaping @Sendable (HTTPURLResponse) async throws -> Void,
         receiveData: @escaping @Sendable (Data) async throws -> Void) {
        original = session
        self.receiveResponse = receiveResponse
        self.receiveData = receiveData
    }

    /// Keeps the stream's queue independent, while retaining configuration and the client's challenge/redirect policy.
    func run(_ request: URLRequest) async throws(JWWNetworkError) {
        let queue = OperationQueue()
        queue.name = "JWWNetworking.stream"
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: original.configuration, delegate: self, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    state.withLock { state in
                        guard !state.cancelled else { continuation.resume(throwing: URLError(.cancelled)); return }
                        state.continuation = continuation
                        let task = session.dataTask(with: request)
                        state.task = task
                        task.resume()
                    }
                }
            } onCancel: { self.cancel() }
        } catch { throw error as? JWWNetworkError ?? .networkError(error) }
    }

    private func cancel() {
        state.withLock { state in
            state.cancelled = true
            state.callback?.cancel()
            state.task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            let response = try HTTPClient.validate(response)
            try deliver { [receiveResponse] in try await receiveResponse(response) }
            completionHandler(.allow)
        } catch {
            fail(error)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard state.withLock({ $0.failure == nil && !$0.cancelled }) else { return }
        dataTask.suspend()
        defer { dataTask.resume() }
        do { try deliver { [receiveData] in try await receiveData(data) } } catch { fail(error) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        state.withLock { state in
            let failure = state.failure ?? error.map { JWWNetworkError.networkError($0) }
                ?? (state.cancelled ? .networkError(URLError(.cancelled)) : nil)
            if let failure { state.continuation?.resume(throwing: failure) } else { state.continuation?.resume() }
            state.continuation = nil
            state.task = nil
        }
    }

    /// Waiting occurs only on this stream's dedicated OperationQueue, never on an actor executor or the client's queue.
    /// There is one callback task at a time and no application-level body buffer or callback backlog.
    private func deliver(_ body: @escaping @Sendable () async throws -> Void) throws {
        // ponytail: one waiting delegate thread per stream; consider a bounded async channel only if measured concurrency requires it.
        let finished = DispatchSemaphore(value: 0)
        let result = Mutex<Result<Void, any Error>>(.success(()))
        state.withLock { state in
            state.callback = Task {
                defer { finished.signal() }
                do {
                    try Task.checkCancellation()
                    try await body()
                    try Task.checkCancellation()
                } catch { result.withLock { $0 = .failure(error) } }
            }
            if state.cancelled { state.callback?.cancel() }
        }
        finished.wait()
        state.withLock { $0.callback = nil }
        try result.withLock { try $0.get() }
    }

    private func fail(_ error: any Error) {
        state.withLock { state in
            state.failure = error as? JWWNetworkError ?? .untypedError(error: error)
            state.task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        original.delegateQueue.addOperation { [original] in
            if let redirect = (original.delegate as? any URLSessionTaskDelegate)?
                .urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:) {
                redirect(original, task, response, request, completionHandler)
            } else { completionHandler(request) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        original.delegateQueue.addOperation { [original] in
            if let authenticate = (original.delegate as? any URLSessionTaskDelegate)?.urlSession(_:task:didReceive:completionHandler:) {
                authenticate(original, task, challenge, completionHandler)
            } else { completionHandler(.performDefaultHandling, nil) }
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        original.delegateQueue.addOperation { [original] in
            if let authenticate = original.delegate?.urlSession(_:didReceive:completionHandler:) {
                authenticate(original, challenge, completionHandler)
            } else { completionHandler(.performDefaultHandling, nil) }
        }
    }
}
