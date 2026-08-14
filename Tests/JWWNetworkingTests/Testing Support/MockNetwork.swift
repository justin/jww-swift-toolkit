import Foundation

/// Object used to manage the list of stubbed responses that can be passed into the `MockedURLProtocol`.
final class MockNetwork: @unchecked Sendable {
    /// The shared instance that can be used to register and return response stubs.
    static let shared = MockNetwork()

    /// Array of response payload stubs that can be returned by the `MockURLProtocol`.
    private(set) var stubs: [NetworkResponseStub] = []

    private let queue = DispatchQueue(label: "com.justinwme.jww-networking.mock-responses", qos: .default, attributes: .concurrent)

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
            for stub in stubs.reversed() where stub.url == request.url {
                return stub
            }

            return nil
        }
    }
}
