import XCTest
import os

/// A test class for defining test cases, test methods, and performance tests. This subclass includes a `URLSession` instance that uses the
/// `MockURLProtocol` for injecting custom payload values and bypassing the network.
@available(*, deprecated, message: "Use withMockNetwork, or own a MockNetwork in your test setup and teardown.")
open class MockedNetworkTestCase: XCTestCase {
    /// Ephemeral `URLSession` we use for mocking responses.
    public final var session: URLSession!

    /// Creates an ephemeral session using the deprecated protocol and its shared global fixtures.
    open override func setUp() async throws {
        try await super.setUp()

        let ephemeral = URLSessionConfiguration.ephemeral
        ephemeral.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: ephemeral)
    }

    /// Invalidates the test session and removes all global stubs after superclass teardown.
    open override func tearDown() async throws {
        try await super.tearDown()

        session.invalidateAndCancel()
        session = nil

        MockURLProtocol.Storage.shared.removeAllStubs()
    }

    // MARK: Testing Helper Methods
    // ====================================
    // Testing Helper Methods
    // ====================================

    /// Convenience function to add a new response stub to the `MockURLProtocol` used by the `session`.
    ///
    /// - Parameters:
    ///   - url: The URL you want to stub a response for.
    ///   - statusCode: The status code to return when the URL is encountered.
    ///   - data: The encoded payload to return along with the response.
    open func addStubResponse(forURL url: URL, statusCode: Int, responseData data: Data) async {
        let stub = NetworkResponseStub(url: url, statusCode: statusCode, data: data)
        MockURLProtocol.Storage.shared.addStub(stub)
    }
}
