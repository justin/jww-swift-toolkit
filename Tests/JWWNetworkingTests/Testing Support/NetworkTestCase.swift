import XCTest
import JWWNetworking
import os

/// A test class for defining test cases, test methods, and performance tests. This subclass includes a `URLSession` instance that includes uses the
/// `MockURLProtocol` for injecting custom payload values and bypassing the network.
class NetworkTestCase: XCTestCase {
    /// The HTTPClient that can be used when running network tests.
    var client: HTTPClient!

    /// Ephemeral `URLSession` we use for mocking responses.
    final var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()

        let ephemeral = URLSessionConfiguration.ephemeral
        ephemeral.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: ephemeral)

        client = HTTPClient(configuration: HTTPClient.Configuration(baseURL: TestingConstants.baseURL), session: session)
    }

    override func tearDown() async throws {
        try await super.tearDown()

        client = nil

        session.invalidateAndCancel()
        session = nil

        MockNetwork.shared.removeAllStubs()
    }

    // MARK: Testing Helper Methods
    // ====================================
    // Testing Helper Methods
    // ====================================

    /// Convenience function to add a new response stub to the `MockURLProtocol` used by the `session`.
    ///
    /// - Parameters:
    ///   - template: The request template you want to stub a response for.
    ///   - statusCode: The status code to return when the URL is encountered.
    ///   - data: The encoded payload to return along with the response.
    func addStubResponse(forTemplate template: any NetworkRequest, statusCode: Int, responseData data: Data) async throws {
        let builder = try NetworkRequestBuilder(template: template).build(for: client)
        let url = try XCTUnwrap(builder.url)

        let stub = NetworkResponseStub(url: url, statusCode: statusCode, data: data)
        MockNetwork.shared.addStub(stub)
    }

    /// Convenience function to add a new response stub to the `MockURLProtocol` used by the `session`.
    ///
    /// - Parameters:
    ///   - template: The request template you want to stub a response for.
    ///   - statusCode: The status code to return when the URL is encountered.
    ///   - response: The response fake to return along with the response.
    func addStubResponse<T: NetworkRequest>(forTemplate template: T, statusCode: Int, response: T.Output) async throws {
        let builder = try NetworkRequestBuilder(template: template).build(for: client)
        let url = try XCTUnwrap(builder.url)
        let data = try client.configuration.encoder.encode(response)

        let stub = NetworkResponseStub(url: url, statusCode: statusCode, data: data)
        MockNetwork.shared.addStub(stub)
    }

    /// Convenience function to add a new response stub to the `MockURLProtocol` used by the `session`.
    ///
    /// - Parameters:
    ///   - template: The request template you want to stub a response for.
    ///   - error: The error to return upon failure.
    func addStubResponse(forTemplate template: any NetworkRequest, error: Error) async throws {
        let builder = try NetworkRequestBuilder(template: template).build(for: client)
        let url = try XCTUnwrap(builder.url)

        let stub = NetworkResponseStub(url: url, error: error)
        MockNetwork.shared.addStub(stub)
    }

    /// Convenience function to add a new response stub to the `MockURLProtocol` used by the `session`.
    ///
    /// - Parameters:
    ///   - url: The URL you want to stub a response for.
    ///   - statusCode: The status code to return when the URL is encountered.
    ///   - data: The encoded payload to return along with the response.
    func addStubResponse(forURL url: URL, statusCode: Int, responseData data: Data) {
        let stub = NetworkResponseStub(url: url, statusCode: statusCode, data: data)
        MockNetwork.shared.addStub(stub)
    }
}
