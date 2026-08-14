import Foundation
import XCTest

/// Test helper that allows for injection of fixture data into a `URLSession` instance instead of hitting the network
/// directly.
public final class MockURLProtocol: URLProtocol {
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    public override class func canInit(with request: URLRequest) -> Bool {
        true
    }

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

    public override func stopLoading() {
        // No-Op
    }

    // MARK: Stub Response Management
    // ====================================
    // Stub Response Management
    // ====================================

    /// Add a new stub response to the list of returnable responses for a request.
    public class func addStub(_ stub: NetworkResponseStub) {
        Storage.shared.addStub(stub)
    }

    /// Remove a stub response from the list of returnable responses for a request.
    public class func removeStub(_ stub: NetworkResponseStub) {
        Storage.shared.removeStub(stub)
    }

    /// Remove all stub responses.
    public class func removeAllStubs() {
        Storage.shared.removeAllStubs()
    }

    /// Find a stub response that matches a given `URLRequest.url`.
    public class func stub(for request: URLRequest) -> NetworkResponseStub? {
        Storage.shared.stub(for: request)
    }

    // MARK: Storage
    // ====================================
    // Storage
    // ====================================

    /// Actor used to manage the list of stubbed responses that can be passed into the `MockedURLProtocol`.
    final class Storage: @unchecked Sendable {
        /// The shared instance of the Mocker, can be used to register and return mocks.
        static let shared = Storage()

        /// Array of response payload stubs that can be returned by the `MockURLProtocol`.
        private(set) var stubs: [NetworkResponseStub] = []

        private let queue = DispatchQueue(label: "com.pro-football-focus.pffkit.stubbed-responses", qos: .default, attributes: .concurrent)

        init() {
            URLProtocol.registerClass(MockURLProtocol.self)
        }

        /// Add a new stub response to the list of returnable responses for a request.
        func addStub(_ stub: NetworkResponseStub) {
            queue.async(flags: .barrier) { [self] in
                stubs.append(stub)
            }
        }

        /// Remove a stub response from the list of returnable responses for a request.
        func removeStub(_ stub: NetworkResponseStub) {
            queue.async(flags: .barrier) { [self] in
                if let index = stubs.firstIndex(of: stub) {
                    stubs.remove(at: index)
                }
            }
        }

        /// Remove all stub responses.
        func removeAllStubs() {
            queue.async(flags: .barrier) { [self] in
                stubs.removeAll()
            }
        }

        /// Find a stub response that matches a given `URLRequest.url`.
        func stub(for request: URLRequest) -> NetworkResponseStub? {
            queue.sync { [self] in
                return stubs.find(for: request)
            }
        }
    }

}
