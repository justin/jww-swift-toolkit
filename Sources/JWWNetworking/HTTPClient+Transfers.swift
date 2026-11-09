import Foundation

public extension HTTPClient {
    /// Uploads an immutable file, then validates and decodes the buffered response as for `send(template:)`.
    ///
    /// The file contains the complete request body, including any multipart envelope. Keep it until completion.
    /// Template or preparation-delegate bodies are rejected. Progress runs on Foundation's delegate queue;
    /// it must return promptly. Cancellation stops transport, but cannot undo a server-side commit.
    /// This operation does not retry, refresh credentials, or enter the offline queue.
    func upload<T: NetworkRequestTemplate>(template: T, fromFile file: URL,
                                           progress: @escaping @Sendable (HTTPTransferProgress) -> Void = { _ in })
        async throws(JWWNetworkError) -> T.Output {
        guard session.configuration.identifier == nil else { throw .invalidRequest }
        let request = try await prepareTransfer(template)
        try Self.validateUpload(request, file: file)
        let data: Data
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await session.upload(for: request, fromFile: file, delegate: UploadProgressDelegate(progress: progress))
        } catch { throw .networkError(error) }
        _ = try Self.validate(response)
        return try decode(data, template: type(of: template))
    }

    /// Delivers validated response headers followed by ordered chunks, without decoding the template's Output.
    ///
    /// Each callback is awaited before delivering further data. A callback failure or caller cancellation stops
    /// the task without replay. A dedicated session copies the client's configuration and forwards redirect and
    /// authentication challenges to its delegate on its delegate queue. Other session-delegate events are not forwarded.
    /// Only one callback runs at a time; the adapter does not buffer the body. Callbacks must cooperate with cancellation.
    func stream(template: some NetworkRequestTemplate,
                receiveResponse: @escaping @Sendable (HTTPURLResponse) async throws -> Void,
                receiveData: @escaping @Sendable (Data) async throws -> Void) async throws(JWWNetworkError) {
        guard session.configuration.identifier == nil else { throw .invalidRequest }
        let request = try await prepareTransfer(template)
        let stream = HTTPStreamDelegate(session: session, receiveResponse: receiveResponse, receiveData: receiveData)
        try await stream.run(request)
    }
}

extension HTTPClient {
    /// Refuses ambiguous bodies and non-file sources before submitting an upload.
    nonisolated static func validateUpload(_ request: URLRequest, file: URL) throws(JWWNetworkError) {
        guard request.httpBody == nil, request.httpBodyStream == nil, file.isFileURL else { throw .invalidRequest }
        do {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
            guard values.isRegularFile == true, values.isReadable == true else { throw CocoaError(.fileReadNoPermission) }
        } catch { throw .untypedError(error: error) }
    }
}

/// Overrides only progress; other task-delegate methods continue to the session delegate.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let progress: @Sendable (HTTPTransferProgress) -> Void

    init(progress: @escaping @Sendable (HTTPTransferProgress) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        progress(.init(direction: .upload, completed: totalBytesSent, expected: totalBytesExpectedToSend))
    }
}
