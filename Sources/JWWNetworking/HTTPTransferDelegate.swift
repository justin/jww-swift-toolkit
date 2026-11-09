import Foundation

/// Mutable response state is confined to the session's serial delegate queue; no app callbacks run under a lock.
final class HTTPTransferDelegate: NSObject, URLSessionDownloadDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private struct Pending {
        var data = Data()
        var download: HTTPURLResponse?
        var failure: JWWNetworkError?
    }

    private let callbacks: HTTPTransferSession.Callbacks
    private let maximumResponseBytes: Int
    private var pending: [Int: Pending] = [:]

    init(callbacks: HTTPTransferSession.Callbacks, maximumResponseBytes: Int) {
        self.callbacks = callbacks
        self.maximumResponseBytes = maximumResponseBytes
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        callbacks.progress(.init(task: downloadTask, session: session),
                           .init(direction: .download, completed: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        callbacks.progress(.init(task: task, session: session),
                           .init(direction: .upload, completed: totalBytesSent, expected: totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        var result = pending[downloadTask.taskIdentifier] ?? Pending()
        guard result.download == nil, result.failure == nil else { return }
        do {
            let response = try HTTPClient.validate(downloadTask.response)
            try callbacks.claimDownload(.init(task: downloadTask, session: session), response, location)
            result.download = response
        } catch { result.failure = error as? JWWNetworkError ?? .untypedError(error: error) }
        pending[downloadTask.taskIdentifier] = result
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            let response = try HTTPClient.validate(response)
            guard response.expectedContentLength <= maximumResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
            completionHandler(.allow)
        } catch {
            pending[dataTask.taskIdentifier, default: Pending()].failure = error as? JWWNetworkError ?? .networkError(error)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var result = pending[dataTask.taskIdentifier] ?? Pending()
        guard result.failure == nil else { return }
        if data.count > maximumResponseBytes - result.data.count {
            result.data = Data()
            result.failure = .networkError(URLError(.dataLengthExceedsMaximum))
            dataTask.cancel()
        } else {
            result.data.append(data)
        }
        pending[dataTask.taskIdentifier] = result
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let pending = pending.removeValue(forKey: task.taskIdentifier) ?? Pending()
        let result: Result<HTTPTransferSession.Completion, JWWNetworkError>
        do {
            if let failure = pending.failure { throw failure }
            if let error { throw JWWNetworkError.networkError(error) }
            let response = try HTTPClient.validate(task.response)
            if task is URLSessionUploadTask {
                result = .success(.upload(response, pending.data))
            } else {
                guard pending.download != nil else { throw JWWNetworkError.invalidResponse(task.response) }
                result = .success(.download(response))
            }
        } catch { result = .failure(error as? JWWNetworkError ?? .untypedError(error: error)) }
        callbacks.completed(.init(task: task, session: session), result)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        callbacks.finishedBackgroundEvents()
    }
}
