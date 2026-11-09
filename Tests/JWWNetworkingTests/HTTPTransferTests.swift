import Foundation
import Network
import Synchronization
import Testing
@testable import JWWNetworking

@Suite(.timeLimit(.minutes(1)))
struct HTTPTransferTests {
    @Test
    func fileUploadPreparesOnceSendsExactBytesAndDecodes() async throws {
        let contents = Data(repeating: 42, count: 128 * 1024)
        let received = Mutex<TransferHTTPServer.Request?>(nil)
        let server = try TransferHTTPServer { request, connection in
            received.withLock { $0 = request }
            TransferHTTPServer.respond(connection, body: Data(#"{"value":"uploaded"}"#.utf8))
        }
        defer { server.stop() }
        let url = try await server.start()
        let file = try temporaryFile(contents)
        defer { try? FileManager.default.removeItem(at: file) }
        let preparation = TransferPreparation()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let client = HTTPClient(configuration: .init(baseURL: nil, userAgent: "Toolkit", authentication: TransferAuthentication()),
                                session: session, delegate: preparation)
        let progress = Mutex<[Int64]>([])
        let result = try await client.upload(template: TransferRequest(url: url), fromFile: file) { value in
            progress.withLock { $0.append(value.completedBytes) }
        }
        #expect(result.value == "uploaded")
        #expect(preparation.calls.withLock { $0 } == 1)
        #expect(received.withLock { $0?.body } == contents)
        let head = try #require(received.withLock { $0?.head.lowercased() })
        #expect(head.contains("authorization: bearer explicit"))
        #expect(head.contains("x-prepared: yes"))
        #expect(head.contains("user-agent: toolkit"))
        #expect(progress.withLock { $0.last } == Int64(contents.count))
    }

    @Test
    func uploadPreservesSessionAuthenticationDelegate() async throws {
        let server = try TransferHTTPServer { _, connection in
            TransferHTTPServer.respond(connection, status: 401, headers: ["WWW-Authenticate": "Basic realm=\"upload\""], body: Data())
        }
        defer { server.stop() }
        let url = try await server.start()
        let delegate = TransferCancelAuthentication()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let client = HTTPClient(configuration: .init(baseURL: nil), session: session)
        let file = try temporaryFile(Data("upload".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await client.upload(template: StaticRequestFake(url: url, method: .post), fromFile: file)
            Issue.record("Expected cancelled authentication")
        } catch {
            #expect(delegate.calls.withLock { $0 } == 1)
        }
    }

    @Test
    func uploadRejectsPreparedBodyAndMissingFileWithoutSending() async throws {
        let file = try temporaryFile(Data())
        defer { try? FileManager.default.removeItem(at: file) }
        let preparation = TransferPreparation(addBody: true)
        let client = HTTPClient(configuration: .init(baseURL: nil), delegate: preparation)
        let request = StaticRequestFake(url: URL(string: "https://example.invalid/upload")!, method: .post)
        do {
            _ = try await client.upload(template: request, fromFile: file)
            Issue.record("Expected conflicting body rejection")
        } catch { if case .invalidRequest = error {} else { Issue.record("Unexpected error: \(error)") } }
        let plain = HTTPClient(configuration: .init(baseURL: nil))
        do {
            _ = try await plain.upload(template: request, fromFile: file.appendingPathComponent("missing"))
            Issue.record("Expected missing-file rejection")
        } catch { if case .untypedError = error {} else { Issue.record("Unexpected error: \(error)") } }
    }

    @Test
    func streamingDeliversSmallChunkBeforeEOFAndPreservesOrder() async throws {
        let connection = Mutex<NWConnection?>(nil)
        let server = try TransferHTTPServer { _, client in
            connection.withLock { $0 = client }
            let head = "HTTP/1.1 206 Partial Content\r\nContent-Type: application/octet-stream\r\n"
                + "X-Content-Type-Options: nosniff\r\nContent-Length: 6\r\nContent-Range: bytes 0-5/6\r\n\r\nabc"
            client.send(content: Data(head.utf8),
                        completion: .contentProcessed { _ in })
        }
        defer { server.stop() }
        let url = try await server.start()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let client = HTTPClient(configuration: .init(baseURL: nil), session: session)
        let bytes = Mutex(Data())
        let headersReceived = Mutex(false)
        try await client.stream(template: StaticRequestFake(url: url), receiveResponse: { response in
            #expect(response.statusCode == 206)
            #expect(response.value(forHTTPHeaderField: "Content-Range") == "bytes 0-5/6")
            headersReceived.withLock { $0 = true }
        }, receiveData: { data in
            #expect(headersReceived.withLock { $0 })
            let count = bytes.withLock { value in value.append(data); return value.count }
            if count == 3 {
                // The server cannot complete until the client has consumed the first small chunk.
                try await Task.sleep(for: .milliseconds(20))
                connection.withLock { $0 }?.send(content: Data("def".utf8), completion: .contentProcessed { _ in })
            }
        })
        #expect(bytes.withLock { $0 } == Data("abcdef".utf8))
    }

    @Test(arguments: [200, 401])
    func streamRejectsHeadersWithoutDeliveringBody(status: Int) async throws {
        let server = try TransferHTTPServer { _, connection in
            TransferHTTPServer.respond(connection, status: status, body: Data("not delivered".utf8))
        }
        defer { server.stop() }
        let url = try await server.start()
        let client = HTTPClient(configuration: .init(baseURL: nil))
        do {
            try await client.stream(template: StaticRequestFake(url: url), receiveResponse: { _ in
                throw JWWNetworkError.invalidRequest
            }, receiveData: { _ in Issue.record("Rejected body was delivered") })
            Issue.record("Expected rejection")
        } catch {
            switch error {
            case .invalidRequest: #expect(status == 200)
            case .requestFailed(let code, _): #expect(code == status)
            default: Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test
    func streamingPreservesSessionRedirectDelegate() async throws {
        let requests = Mutex(0)
        let server = try TransferHTTPServer { _, connection in
            requests.withLock { $0 += 1 }
            TransferHTTPServer.respond(connection, status: 302, headers: ["Location": "/other"], body: Data())
        }
        defer { server.stop() }
        let url = try await server.start()
        let session = URLSession(configuration: .ephemeral, delegate: TransferRefuseRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let client = HTTPClient(configuration: .init(baseURL: nil), session: session)
        do {
            try await client.stream(template: StaticRequestFake(url: url), receiveResponse: { _ in }, receiveData: { _ in })
            Issue.record("Expected refused redirect")
        } catch {
            guard case .requestFailed(let code, _) = error else { Issue.record("Unexpected error: \(error)"); return }
            #expect(code == 302)
        }
        #expect(requests.withLock { $0 } == 1)
    }

    @Test
    func uploadPreservesSessionRedirectDelegate() async throws {
        let requests = Mutex(0)
        let server = try TransferHTTPServer { _, connection in
            requests.withLock { $0 += 1 }
            TransferHTTPServer.respond(connection, status: 302, headers: ["Location": "/other"], body: Data())
        }
        defer { server.stop() }
        let url = try await server.start()
        let session = URLSession(configuration: .ephemeral, delegate: TransferRefuseRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let client = HTTPClient(configuration: .init(baseURL: nil), session: session)
        let file = try temporaryFile(Data("upload".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await client.upload(template: TransferRequest(url: url), fromFile: file)
            Issue.record("Expected refused redirect")
        } catch {
            guard case .requestFailed(let code, _) = error else { Issue.record("Unexpected error: \(error)"); return }
            #expect(code == 302)
        }
        #expect(requests.withLock { $0 } == 1)
    }

    @Test
    func streamCancellationWhileAwaitingBodyStopsTransport() async throws {
        let headers = AsyncStream.makeStream(of: Void.self)
        let server = try TransferHTTPServer { _, connection in
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
                + "X-Content-Type-Options: nosniff\r\nContent-Length: 10\r\n\r\na"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        }
        defer { server.stop() }
        let url = try await server.start()
        let client = HTTPClient(configuration: .init(baseURL: nil))
        let task = Task {
            try await client.stream(template: StaticRequestFake(url: url), receiveResponse: { _ in headers.continuation.yield(()) },
                                    receiveData: { _ in })
        }
        for await _ in headers.stream { break }
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") } catch {
            #expect((error as? JWWNetworkError)?.isCancellation == true)
        }
    }

    @Test
    func fileSessionUploadsAndDownloadsWithOpaqueIdentities() async throws {
        let contents = Data("file contents".utf8)
        let server = try TransferHTTPServer { request, connection in
            TransferHTTPServer.respond(connection, body: request.head.hasPrefix("POST") ? Data(#"{"url":"stored"}"#.utf8) : contents)
        }
        defer { server.stop() }
        let url = try await server.start()
        let source = try temporaryFile(contents)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        let events = AsyncStream.makeStream(of: (HTTPTransferSession.Snapshot, Result<HTTPTransferSession.Completion, JWWNetworkError>).self)
        let client = HTTPClient(configuration: .init(baseURL: nil))
        let transfers = try HTTPTransferSession(client: client, configuration: .ephemeral, callbacks: .init(claimDownload: { snapshot, _, file in
            #expect(snapshot.id == "download")
            try FileManager.default.moveItem(at: file, to: destination)
        }, completed: { events.continuation.yield(($0, $1)) }))
        defer { transfers.invalidate(cancelOutstanding: true) }
        let upload = try await transfers.startUpload(template: StaticRequestFake(url: url, method: .post), fromFile: source, id: "upload")
        #expect(upload.id == "upload")
        try await transfers.startDownload(template: StaticRequestFake(url: url), id: "download")
        var completed = Set<String>()
        for await (snapshot, result) in events.stream {
            completed.insert(try #require(snapshot.id))
            switch try result.get() {
            case .download(let response):
                #expect(response.statusCode == 200)
                #expect(try Data(contentsOf: destination) == contents)
            case .upload(_, let data): #expect(data == Data(#"{"url":"stored"}"#.utf8))
            }
            if completed.count == 2 { break }
        }
        #expect(completed == ["upload", "download"])
    }

    @Test(arguments: [200, 403])
    func uploadSessionBoundsResponsesAndPreservesHTTPFailure(status: Int) async throws {
        let server = try TransferHTTPServer { _, connection in
            TransferHTTPServer.respond(connection, status: status, body: Data(repeating: 0, count: 32))
        }
        defer { server.stop() }
        let url = try await server.start()
        let file = try temporaryFile(Data())
        defer { try? FileManager.default.removeItem(at: file) }
        let result = AsyncStream.makeStream(of: Result<HTTPTransferSession.Completion, JWWNetworkError>.self)
        let transfers = try HTTPTransferSession(client: HTTPClient(configuration: .init(baseURL: nil)), configuration: .ephemeral,
                                                callbacks: .init(claimDownload: { _, _, _ in Issue.record("Unexpected download") },
                                                                 completed: { _, value in result.continuation.yield(value) }),
                                                maximumUploadResponseBytes: 16)
        defer { transfers.invalidate(cancelOutstanding: true) }
        try await transfers.startUpload(template: StaticRequestFake(url: url, method: .post), fromFile: file, id: "bounded")
        for await value in result.stream {
            guard case .failure(let error) = value else { Issue.record("Expected failure"); break }
            switch error {
            case .requestFailed(let code, _): #expect(code == 403 && status == 403)
            case .networkError(let underlying):
                #expect(status == 200)
                #expect((underlying as? URLError)?.code == .dataLengthExceedsMaximum)
            default: Issue.record("Unexpected error: \(error)")
            }
            break
        }
    }

    @Test
    func streamHandlesLargeBodyWithoutAccumulatingItInTheConsumer() async throws {
        let length = 8 * 1024 * 1024
        let server = try TransferHTTPServer { _, connection in
            TransferHTTPServer.respond(connection, body: Data(repeating: 17, count: length))
        }
        defer { server.stop() }
        let url = try await server.start()
        let counts = Mutex((total: 0, chunks: 0))
        try await HTTPClient(configuration: .init(baseURL: nil)).stream(template: StaticRequestFake(url: url),
                                                                       receiveResponse: { _ in }, receiveData: { data in
            #expect(data.allSatisfy { $0 == 17 })
            counts.withLock { $0.total += data.count; $0.chunks += 1 }
        })
        #expect(counts.withLock { $0.total } == length)
        #expect(counts.withLock { $0.chunks } > 1)
    }

    @Test
    func slowStreamCallbackCanUseTheSameHTTPClient() async throws {
        let server = try TransferHTTPServer { request, connection in
            let body = request.head.contains("/other") ? Data(#"{"value":"nested"}"#.utf8) : Data("stream".utf8)
            TransferHTTPServer.respond(connection, body: body)
        }
        defer { server.stop() }
        let url = try await server.start()
        let session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: .main)
        defer { session.invalidateAndCancel() }
        let client = HTTPClient(configuration: .init(baseURL: nil), session: session)
        try await client.stream(template: StaticRequestFake(url: url), receiveResponse: { _ in }, receiveData: { _ in
            try await Task.sleep(for: .milliseconds(10))
            let response = try await client.send(template: StaticRequestFake(url: url.deletingLastPathComponent().appendingPathComponent("other")))
            #expect(response.value == "nested")
        })
    }

    @Test
    func foregroundUploadDoesNotReplayHTTPFailures() async throws {
        let attempts = Mutex(0)
        let server = try TransferHTTPServer { _, connection in
            attempts.withLock { $0 += 1 }
            TransferHTTPServer.respond(connection, status: 503, body: Data())
        }
        defer { server.stop() }
        let url = try await server.start()
        let file = try temporaryFile(Data())
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await HTTPClient(configuration: .init(baseURL: nil)).upload(template: StaticRequestFake(url: url, method: .post), fromFile: file)
            Issue.record("Expected HTTP failure")
        } catch {
            guard case .requestFailed(let code, _) = error else { Issue.record("Unexpected error: \(error)"); return }
            #expect(code == 503)
        }
        #expect(attempts.withLock { $0 } == 1)
    }

    @Test
    func downloadHTTPFailureNeverClaimsTheErrorBody() async throws {
        let server = try TransferHTTPServer { _, connection in
            TransferHTTPServer.respond(connection, status: 404, body: Data("missing".utf8))
        }
        defer { server.stop() }
        let url = try await server.start()
        let events = AsyncStream.makeStream(of: Result<HTTPTransferSession.Completion, JWWNetworkError>.self)
        let transfers = try HTTPTransferSession(client: HTTPClient(configuration: .init(baseURL: nil)), configuration: .ephemeral,
                                                callbacks: .init(claimDownload: { _, _, _ in Issue.record("Error body claimed as a file") },
                                                                 completed: { _, result in events.continuation.yield(result) }))
        defer { transfers.invalidate(cancelOutstanding: true) }
        try await transfers.startDownload(template: StaticRequestFake(url: url), id: "missing")
        for await result in events.stream {
            guard case .failure(.requestFailed(let code, _)) = result else { Issue.record("Expected HTTP failure"); break }
            #expect(code == 404)
            break
        }
    }

    @Test
    func downloadClaimFailureIsReportedAndDoesNotBecomeSuccess() async throws {
        let server = try TransferHTTPServer { _, connection in TransferHTTPServer.respond(connection, body: Data("file".utf8)) }
        defer { server.stop() }
        let url = try await server.start()
        let events = AsyncStream.makeStream(of: Result<HTTPTransferSession.Completion, JWWNetworkError>.self)
        let claims = Mutex(0)
        let transfers = try HTTPTransferSession(client: HTTPClient(configuration: .init(baseURL: nil)), configuration: .ephemeral,
                                                callbacks: .init(claimDownload: { _, _, location in
            #expect(FileManager.default.fileExists(atPath: location.path))
            claims.withLock { $0 += 1 }
            throw CocoaError(.fileWriteNoPermission)
        }, completed: { _, result in events.continuation.yield(result) }))
        defer { transfers.invalidate(cancelOutstanding: true) }
        try await transfers.startDownload(template: StaticRequestFake(url: url), id: "move-failure")
        for await result in events.stream {
            guard case .failure(.untypedError(let error)) = result else { Issue.record("Expected file error"); break }
            #expect((error as? CocoaError)?.code == .fileWriteNoPermission)
            break
        }
        #expect(claims.withLock { $0 } == 1)
    }

    @Test
    func taskSnapshotsAndExplicitCancellationUseCallerIdentity() async throws {
        let received = AsyncStream.makeStream(of: Void.self)
        let server = try TransferHTTPServer { _, _ in received.continuation.yield(()) }
        defer { server.stop() }
        let url = try await server.start()
        let events = AsyncStream.makeStream(of: Result<HTTPTransferSession.Completion, JWWNetworkError>.self)
        let transfers = try HTTPTransferSession(client: HTTPClient(configuration: .init(baseURL: nil)), configuration: .ephemeral,
                                                callbacks: .init(claimDownload: { _, _, _ in Issue.record("Unexpected file") },
                                                                 completed: { _, result in events.continuation.yield(result) }))
        defer { transfers.invalidate(cancelOutstanding: true) }
        let submitted = try await transfers.startDownload(template: StaticRequestFake(url: url), id: "journal-id")
        for await _ in received.stream { break }
        let tasks = await transfers.tasks()
        #expect(tasks.count == 1)
        #expect(tasks.first?.id == "journal-id")
        #expect(tasks.first?.taskIdentifier == submitted.taskIdentifier)
        #expect(HTTPTransferProgress(direction: .download, completed: 0, expected: -1).expectedBytes == nil)
        await transfers.cancel(id: "journal-id")
        for await result in events.stream {
            guard case .failure(let error) = result else { Issue.record("Expected cancellation"); break }
            #expect(error.isCancellation)
            break
        }
        transfers.invalidate()
        do {
            try await transfers.startDownload(template: StaticRequestFake(url: url), id: "closed")
            Issue.record("Closed session accepted submission")
        } catch { if case .invalidRequest = error {} else { Issue.record("Unexpected error: \(error)") } }
    }

    @Test
    func uploadResponseLimitAlsoAppliesWithoutContentLength() async throws {
        let server = try TransferHTTPServer { _, connection in
            connection.send(content: Data("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n0123456789".utf8),
                            completion: .contentProcessed { _ in connection.cancel() })
        }
        defer { server.stop() }
        let url = try await server.start()
        let source = try temporaryFile(Data())
        defer { try? FileManager.default.removeItem(at: source) }
        let events = AsyncStream.makeStream(of: Result<HTTPTransferSession.Completion, JWWNetworkError>.self)
        let transfers = try HTTPTransferSession(client: HTTPClient(configuration: .init(baseURL: nil)), configuration: .ephemeral,
                                                callbacks: .init(claimDownload: { _, _, _ in }, completed: { _, result in
            events.continuation.yield(result)
        }), maximumUploadResponseBytes: 4)
        defer { transfers.invalidate(cancelOutstanding: true) }
        try await transfers.startUpload(template: StaticRequestFake(url: url, method: .post), fromFile: source, id: "unknown-length")
        for await result in events.stream {
            guard case .failure(.networkError(let error)) = result else { Issue.record("Expected limit error"); break }
            #expect((error as? URLError)?.code == .dataLengthExceedsMaximum)
            break
        }
    }

    @Test
    func streamReportsCallbackAndTruncatedBodyFailures() async throws {
        let server = try TransferHTTPServer { _, connection in
            connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: 100\r\n\r\nshort".utf8),
                            completion: .contentProcessed { _ in connection.cancel() })
        }
        defer { server.stop() }
        let url = try await server.start()
        for failCallback in [true, false] {
            do {
                try await HTTPClient(configuration: .init(baseURL: nil)).stream(template: StaticRequestFake(url: url),
                                                                               receiveResponse: { _ in }, receiveData: { _ in
                    if failCallback { throw JWWNetworkError.invalidRequest }
                })
                Issue.record("Expected failed stream")
            } catch {
                if failCallback {
                    if case .invalidRequest = error {} else { Issue.record("Unexpected callback error: \(error)") }
                } else {
                    if case .networkError = error {} else { Issue.record("Unexpected transport error: \(error)") }
                }
            }
        }
    }
}

private func temporaryFile(_ data: Data) throws -> URL {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try data.write(to: file)
    return file
}

private struct TransferRequest: StaticNetworkRequest, AuthenticatedRequest {
    typealias Output = NetworkResponseFake
    let url: URL
    let method = HTTPMethod.post
    let body: Data? = nil
    let authenticationType = AuthenticationType.bearer
    let headers: [HTTPRequestHeaderKey: String] = [.authorization: "Bearer explicit"]
}

private actor TransferAuthentication: AuthenticationProvider {
    var accessToken: String { "provider-token" }
    func refreshAccessToken(refreshToken: String) async throws -> String { "unused" }
}

private final class TransferPreparation: HTTPClientDelegate {
    let calls = Mutex(0)
    let addBody: Bool
    init(addBody: Bool = false) { self.addBody = addBody }
    func client(_ client: HTTPClient, willSendRequest request: inout URLRequest) async throws {
        calls.withLock { $0 += 1 }
        request.setValue("yes", forHTTPHeaderField: "X-Prepared")
        if addBody { request.httpBody = Data() }
    }
}

private final class TransferRefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class TransferCancelAuthentication: NSObject, URLSessionTaskDelegate {
    let calls = Mutex(0)

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        calls.withLock { $0 += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
