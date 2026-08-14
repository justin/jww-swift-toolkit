import XCTest
import JWWTestExtensions
import JWWNetworking

/// Tests to validate the `HTTPClient` type.
final class HTTPClientTests: NetworkTestCase {
    /// Validate we can send a single request and return a valid payload.
    func testSuccessfulRequest() async throws {
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL, path: "/test", method: .get)
        let fakeResponse = NetworkResponseFake(value: "test-is-valid")
        try await addStubResponse(forTemplate: template, statusCode: 200, response: fakeResponse)

        let result = try await client.send(template: template)

        XCTAssertEqual(result, fakeResponse)
    }

    /// Validate we can send a single request and have it throw an error.
    func testFailedRequest() async throws {
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL, path: "/test", method: .get)
        let error = URLError(.badURL)
        try await addStubResponse(forTemplate: template, error: error)

        await JWWAssertThrowsError(try await client.send(template: template)) { error in
            XCTAssertTrue(error is JWWNetworkError, "Expected error type returned to be a JWWNetworkError.")
        }
    }
}
