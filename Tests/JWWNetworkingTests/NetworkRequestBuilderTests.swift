import XCTest
@testable import JWWNetworking
import JWWTestExtensions

/// Tests to exercise our `NetworkRequestBuilder` type.
final class NetworkRequestBuilderTests: NetworkTestCase {
    /// Validate we can properly convert a `GeneratedNetworkRequest` template into a valid `URLRequest`.
    func testBuildingRequestFromGeneratedTemplate() async throws {
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "key1", value: "value1"),
            URLQueryItem(name: "key2", value: "value2")
        ]
        let path = "/one/two/three"
        let expectedURL = URL(string: "https://localhost/one/two/three?key1=value1&key2=value2")
        let expectedMethod: HTTPMethod = .get
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL,
                                          path: path,
                                          queryItems: queryItems,
                                          method: expectedMethod)

        let result = try await NetworkRequestBuilder(template: template).build(for: client)

        XCTAssertNotNil(result.url)
        XCTAssertEqual(result.url, expectedURL)
        XCTAssertEqual(result.httpMethod, String(describing: expectedMethod))
    }

    /// Validate we can properly convert a `StaticURLRequest` template into a valid `URLRequest`.
    func testBuildingRequestFromStaticTemplate() async throws {
        let expectedURL = URL(staticString: "https://localhost/test")
        let expectedMethod: HTTPMethod = .post
        let template = StaticRequestFake(url: expectedURL, method: expectedMethod)

        let result = try await NetworkRequestBuilder(template: template).build(for: client)

        XCTAssertNotNil(result.url)
        XCTAssertEqual(result.url, expectedURL)
        XCTAssertEqual(result.httpMethod, String(describing: expectedMethod))
    }

    /// Validate we throw an error if we try to build a request from an base `NetworkRequest` type.
    func testBuildingRequestFromBaseTemplate() async throws {
        let template = InvalidNetworkRequest()

        await JWWAssertThrowsError(try await NetworkRequestBuilder(template: template).build(for: client)) { error in
            XCTAssertTrue(error is JWWNetworkError, "Expected error type returned to be a JWWNetworkError.")

            if let error = error as? JWWNetworkError, case .invalidTemplate = error {
                XCTFail("Expected error to be an invalidTemplate error.")
            }
        }
    }

    /// Validate if we set a header value on our request type it is added to the request.
    func testSettingRequestHeaders() async throws {
        let expectedHeaders: [String: String] = [
            "Foo": "Bar",
            "Fiz": "Buzz"
        ]

        let request = StaticRequestFake(url: TestingConstants.baseURL, headers: [
            HTTPRequestHeaderKey("Foo"): "Bar",
            HTTPRequestHeaderKey("Fiz"): "Buzz"
        ])

        let result = try await NetworkRequestBuilder(template: request).build(for: client)

        XCTAssertEqual(result.allHTTPHeaderFields, expectedHeaders)
    }

    /// Validate we don't include the question mark if the query parameters field is empty.
    func testNoQuestionMarkIfNoQueryParameters() async throws {
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL, path: "/fake-url", method: .get)

        let request = try await NetworkRequestBuilder(template: template).build(for: client)
        let result = try XCTUnwrap(request.url)

        XCTAssertFalse(result.absoluteString.hasSuffix("?"), "URL is \(result.absoluteURL)")
    }

    /// Validate we can set the user agent header on our request.
    func testSettingUserAgentHeader() async throws {
        let userAgent = "FakeUserAgent/1.0"
        let configuration = HTTPClient.Configuration(baseURL: TestingConstants.baseURL, userAgent: userAgent)
        let client = HTTPClient(configuration: configuration)

        let request = StaticRequestFake(url: TestingConstants.baseURL)

        let result = try await NetworkRequestBuilder(template: request).build(for: client)

        XCTAssertEqual(result.allHTTPHeaderFields?["User-Agent"], userAgent)
    }

    /// Validate if we do not set the user agent header on our request it falls back to the default.
    func testFallingBackToDefaultUserAgent() async throws {
        let request = StaticRequestFake(url: TestingConstants.baseURL)

        let result = try await NetworkRequestBuilder(template: request).build(for: client)

        XCTAssertNil(result.allHTTPHeaderFields?["User-Agent"])
    }
}
