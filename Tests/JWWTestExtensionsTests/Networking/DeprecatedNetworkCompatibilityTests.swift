import Foundation
import XCTest
import JWWTestExtensions

/// Exercise the deprecated API through public imports, as an existing consumer would.
@available(*, deprecated, message: "Compatibility coverage for the deprecated networking API.")
final class DeprecatedNetworkCompatibilityTests: MockedNetworkTestCase {
    func testSuperclassHelperAndRepeatedResponses() async throws {
        let url = URL(string: "https://legacy.invalid/items?q=1")!
        let data = Data("legacy response".utf8)
        await addStubResponse(forURL: url, statusCode: 201, responseData: data)

        for _ in 0..<2 {
            let (received, response) = try await session.data(from: url)
            XCTAssertEqual(received, data)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201)
        }
    }

    func testStaticRegistrationMatchingAndRemoval() throws {
        let url = URL(string: "https://legacy.invalid/items?q=1")!
        let first = NetworkResponseStub(url: url, statusCode: 200, data: Data("first".utf8))
        let second = NetworkResponseStub(url: url, statusCode: 404)
        MockURLProtocol.addStub(first)
        MockURLProtocol.addStub(second)

        var request = URLRequest(url: URL(string: "http://different.invalid:8080/items?q=1")!)
        request.httpMethod = "DELETE"
        XCTAssertEqual(MockURLProtocol.stub(for: request), second)
        MockURLProtocol.removeStub(second)
        XCTAssertEqual(MockURLProtocol.stub(for: request), first)
        XCTAssertEqual(first.allHeaderFields, [:])
        XCTAssertEqual(first.version, "HTTP/2.0")
        XCTAssertNil(first.error)
        XCTAssertEqual(first, NetworkResponseStub(url: url, statusCode: 200))
        MockURLProtocol.removeAllStubs()
        XCTAssertNil(MockURLProtocol.stub(for: request))
    }

    func testTransportErrorAndMissingStub() async throws {
        let url = URL(string: "https://legacy.invalid/failure")!
        MockURLProtocol.addStub(NetworkResponseStub(url: url, error: URLError(.timedOut)))
        do {
            _ = try await session.data(from: url)
            XCTFail("Expected the registered error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        MockURLProtocol.removeAllStubs()
        do {
            _ = try await session.data(from: url)
            XCTFail("Expected a missing-stub error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .fileDoesNotExist)
        }
    }

    func testGlobalStubsCannotSatisfyScopedExpectations() async throws {
        let url = URL(string: "https://legacy.invalid/shared")!
        MockURLProtocol.addStub(NetworkResponseStub(url: url, statusCode: 200, data: Data("legacy".utf8)))
        let scoped = MockNetwork()
        defer { scoped.close() }
        try scoped.expect(.init(.get, url: url), outcome: .response(.text("scoped")))
        let (data, _) = try await scoped.session.data(from: url)
        XCTAssertEqual(data, Data("scoped".utf8))
        try scoped.verify()
        do {
            _ = try await scoped.session.data(from: url)
            XCTFail("An exhausted scoped expectation must not fall back to global stubs")
        } catch {
            XCTAssertThrowsError(try scoped.verify())
        }
        let (legacyData, _) = try await session.data(from: url)
        XCTAssertEqual(legacyData, Data("legacy".utf8))
    }
}
