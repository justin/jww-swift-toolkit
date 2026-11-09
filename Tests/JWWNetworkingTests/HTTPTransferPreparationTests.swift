import Foundation
import Synchronization
import Testing
@testable import JWWNetworking

@Suite(.timeLimit(.minutes(1)))
struct HTTPTransferPreparationTests {
    @Test
    func cancellationDuringPreparationDoesNotSubmitADurableTask() async throws {
        let gate = OfflineTestGate()
        let client = HTTPClient(configuration: .init(baseURL: nil), delegate: OfflinePreparingDelegate { await gate.wait() })
        let transfers = try HTTPTransferSession(client: client, configuration: .ephemeral, callbacks: .init(
            claimDownload: { _, _, _ in Issue.record("Unexpected download") },
            completed: { _, _ in Issue.record("Cancelled preparation submitted a task") }
        ))
        defer { transfers.invalidate(cancelOutstanding: true) }
        let task = Task {
            try await transfers.startDownload(template: StaticRequestFake(url: URL(string: "https://example.invalid/file")!), id: "cancelled")
        }
        for await _ in gate.entered { break }
        task.cancel()
        await gate.release()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch {
            #expect((error as? JWWNetworkError)?.isCancellation == true)
        }
        #expect(await transfers.tasks().isEmpty)
    }

    @Test
    func authenticationFailurePrecedesPreparationAndDispatch() async throws {
        let calls = Mutex(0)
        let authentication = OfflinePreparingAuthentication { throw URLError(.userAuthenticationRequired) }
        let client = HTTPClient(configuration: .init(baseURL: nil, authentication: authentication),
                                delegate: OfflinePreparingDelegate { calls.withLock { $0 += 1 } })
        do {
            try await client.stream(template: OfflineAuthenticatedRequest(url: URL(string: "https://example.invalid/file")!),
                                    receiveResponse: { _ in Issue.record("Unexpected response") }, receiveData: { _ in })
            Issue.record("Expected authentication failure")
        } catch {
            guard case .authenticationError(let underlying) = error else { Issue.record("Unexpected error: \(error)"); return }
            #expect((underlying as? URLError)?.code == .userAuthenticationRequired)
        }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test
    func foregroundUploadCancellationDoesNotWaitForServerResponse() async throws {
        let received = AsyncStream.makeStream(of: Void.self)
        let server = try TransferHTTPServer { _, _ in received.continuation.yield(()) }
        defer { server.stop() }
        let url = try await server.start()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("body".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = HTTPClient(configuration: .init(baseURL: nil))
        let task = Task { try await client.upload(template: StaticRequestFake(url: url, method: .post), fromFile: file) }
        for await _ in received.stream { break }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch {
            #expect((error as? JWWNetworkError)?.isCancellation == true)
        }
    }

    @Test
    func backgroundEventNotificationDoesNotAcknowledgeAppWork() {
        // Synthetic delegate evidence only: the app, not this callback, must drain async processing and acknowledge UIKit.
        let finished = Mutex(0)
        let delegate = HTTPTransferDelegate(callbacks: .init(claimDownload: { _, _, _ in }, completed: { _, _ in },
                                                            finishedBackgroundEvents: { finished.withLock { $0 += 1 } }),
                                            maximumResponseBytes: 16)
        delegate.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        #expect(finished.withLock { $0 } == 1)
    }
}
