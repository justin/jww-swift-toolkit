import Foundation
import Synchronization
import Testing
@testable import JWWTestExtensions

struct ScopedMockURLProtocolTests {
    @Test(arguments: [false, true])
    func testExactlyOneTerminalCallback(failure: Bool) throws {
        let network = MockNetwork()
        defer { network.close() }
        let url = URL(string: "https://mock.invalid/lifecycle")!
        let outcome: MockOutcome = failure ? .failure(URLError(.timedOut)) : .response(.text("body"))
        try network.expect(.init(.get, url: url), outcome: outcome)
        let client = ProtocolClient()
        let protocolInstance = makeProtocol(network: network, url: url, client: client)
        protocolInstance.startLoading()
        protocolInstance.startLoading()
        protocolInstance.stopLoading()
        #expect(client.events == (failure ? ["failure"] : ["response", "data", "finish"]))
        try network.verify()
    }

    @Test
    func testStoppedProtocolDoesNotDeliverAfterRelease() throws {
        let network = MockNetwork()
        defer { network.close() }
        let url = URL(string: "https://mock.invalid/stopped")!
        let gate = MockResponseGate()
        try network.expect(.init(.get, url: url), outcome: .response(.text("body")), gate: gate)
        let client = ProtocolClient()
        let protocolInstance = makeProtocol(network: network, url: url, client: client)
        protocolInstance.startLoading()
        protocolInstance.stopLoading()
        gate.release()
        #expect(client.events.isEmpty)
        try network.verify()
    }

    @Test
    func testCancellationDuringResponseCallbackStopsFurtherDelivery() throws {
        let network = MockNetwork()
        defer { network.close() }
        let url = URL(string: "https://mock.invalid/cancel-in-callback")!
        try network.expect(.init(.get, url: url), outcome: .response(.text("body")))
        let client = ProtocolClient(cancelOnResponse: true)
        let protocolInstance = makeProtocol(network: network, url: url, client: client)
        protocolInstance.startLoading()
        #expect(client.events == ["response"])
        try network.verify()
    }

    @Test
    func testMissingRoutingFailsWithoutFinishing() {
        let client = ProtocolClient()
        let protocolInstance = ScopedMockURLProtocol(request: URLRequest(url: URL(string: "https://mock.invalid")!),
                                              cachedResponse: nil, client: client)
        protocolInstance.startLoading()
        #expect(client.events == ["failure"])
    }

    private func makeProtocol(network: MockNetwork, url: URL, client: ProtocolClient) -> ScopedMockURLProtocol {
        var request = URLRequest(url: url)
        let token = network.session.configuration.httpAdditionalHeaders?[MockNetworkRegistry.header] as? String
        request.setValue(token, forHTTPHeaderField: MockNetworkRegistry.header)
        return ScopedMockURLProtocol(request: request, cachedResponse: nil, client: client)
    }
}

private final class ProtocolClient: NSObject, URLProtocolClient, Sendable {
    private let cancelOnResponse: Bool
    private let recorded = Mutex<[String]>([])

    init(cancelOnResponse: Bool = false) {
        self.cancelOnResponse = cancelOnResponse
        super.init()
    }

    var events: [String] { recorded.withLock { $0 } }

    private func record(_ event: String) { recorded.withLock { $0.append(event) } }

    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: any Error) { record("failure") }
    func urlProtocolDidFinishLoading(_ protocol: URLProtocol) { record("finish") }
    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) { record("data") }
    func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {
        record("response")
        if cancelOnResponse { `protocol`.stopLoading() }
    }
    func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) { record("redirect") }
    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) { record("cache") }
    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) { record("challenge") }
    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) { record("cancel challenge") }
}
