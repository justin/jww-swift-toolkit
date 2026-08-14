import Foundation

/// Test helper that allows for injection of fixture data into a `URLSession` instance instead of hitting the network
/// directly.
final class MockURLProtocol: URLProtocol {
    /// Potential errors that can occur when loading a stub payload.
    enum MockError: Error {
        case missingStub
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override func startLoading() {
        guard let stub = MockNetwork.shared.stub(for: request) else {
            client?.urlProtocol(self, didFailWithError: MockError.missingStub)
            return
        }

        if let data = stub.data {
            client?.urlProtocol(self, didLoad: data)
        }

        defer {
            client?.urlProtocolDidFinishLoading(self)
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
        }
    }

    override func stopLoading() {
        // No-Op
    }
}
