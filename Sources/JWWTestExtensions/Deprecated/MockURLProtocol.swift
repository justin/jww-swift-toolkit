import Foundation
import Synchronization
import XCTest

/// Test helper that allows for injection of fixture data into a `URLSession` instance instead of hitting the network
/// directly.
@available(*, deprecated, message: "Use MockNetwork and its session-scoped expectations instead of global stubs.")
public final class MockURLProtocol: URLProtocol {
    /// Leaves the request unchanged for the deprecated path/query matcher.
    public override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    /// Accepts every intercepted request; a missing global stub is reported as a local error.
    public override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    /// Delivers the last matching global stub without consuming it.
    /// Reports `URLError.fileDoesNotExist` when no stub matches.
    public override func startLoading() {
        guard let stub = MockURLProtocol.stub(for: request) else {
            let error = URLError(.fileDoesNotExist, userInfo: [
                NSLocalizedFailureReasonErrorKey: "A stub for the URL does not exist: \(String(describing: request.url))",
                NSURLErrorFailingURLErrorKey: request.url as Any
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let response = HTTPURLResponse(url: stub.url,
                                          statusCode: stub.statusCode,
                                          httpVersion: stub.version,
                                          headerFields: stub.allHeaderFields) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = stub.data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    /// Performs no cancellation work because this compatibility protocol delivers its callbacks synchronously.
    public override func stopLoading() {
        // No-Op
    }

    // MARK: Stub Response Management
    // ====================================
    // Stub Response Management
    // ====================================

    /// Add a new stub response to the list of returnable responses for a request.
    public static func addStub(_ stub: NetworkResponseStub) {
        Storage.shared.addStub(stub)
    }

    /// Remove a stub response from the list of returnable responses for a request.
    public static func removeStub(_ stub: NetworkResponseStub) {
        Storage.shared.removeStub(stub)
    }

    /// Remove all stub responses.
    public static func removeAllStubs() {
        Storage.shared.removeAllStubs()
    }

    /// Finds the most recently registered stub matching the request path and query items.
    /// Scheme, host, port, and HTTP method are intentionally ignored for compatibility.
    public static func stub(for request: URLRequest) -> NetworkResponseStub? {
        Storage.shared.stub(for: request)
    }

    // MARK: Storage
    // ====================================
    // Storage
    // ====================================

    /// Synchronized storage used to manage the list of stubbed responses available to `MockURLProtocol`.
    final class Storage: Sendable {
        /// Global storage used by every session configured with the deprecated protocol.
        static let shared = Storage()

        /// Array of response payload stubs that can be returned by the `MockURLProtocol`.
        private let stubs = Mutex<[NetworkResponseStub]>([])

        /// Registers the compatibility protocol globally when its shared storage is first accessed.
        init() {
            URLProtocol.registerClass(MockURLProtocol.self)
        }

        /// Add a new stub response to the list of returnable responses for a request.
        func addStub(_ stub: NetworkResponseStub) {
            stubs.withLock { stubs in
                stubs.append(stub)
            }
        }

        /// Remove a stub response from the list of returnable responses for a request.
        func removeStub(_ stub: NetworkResponseStub) {
            stubs.withLock { stubs in
                if let index = stubs.firstIndex(of: stub) {
                    stubs.remove(at: index)
                }
            }
        }

        /// Remove all stub responses.
        func removeAllStubs() {
            stubs.withLock { stubs in
                stubs.removeAll()
            }
        }

        /// Returns the last path/query match without consuming it.
        func stub(for request: URLRequest) -> NetworkResponseStub? {
            stubs.withLock { stubs in
                return stubs.find(for: request)
            }
        }
    }

}
