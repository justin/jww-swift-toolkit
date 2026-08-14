import XCTest
@testable import JWWTestExtensions

/// Tests to validate the NetworkResponseStub type.
final class NetworkResponseStubTests: XCTestCase {
    private let url = URL(string: "https://localhost")!

    func testSuccessInit() throws {
        let expectedURL = url
        let expectedCode = 200

        let stub = NetworkResponseStub(url: URL(string: "https://localhost")!, statusCode: 200)
        XCTAssertEqual(stub.url, expectedURL)
        XCTAssertEqual(stub.statusCode, expectedCode)
        XCTAssertNil(stub.data)
        XCTAssertNil(stub.error)
    }

    func testDataInit() throws {
        let expectedURL = url
        let expectedCode = 200
        let expectedPayload = try XCTUnwrap("This is a test payload".data(using: .utf8))

        let stub = NetworkResponseStub(url: URL(string: "https://localhost")!, statusCode: 200, data: expectedPayload)
        XCTAssertEqual(stub.url, expectedURL)
        XCTAssertEqual(stub.statusCode, expectedCode)
        XCTAssertNotNil(stub.data)
        XCTAssertEqual(stub.data, expectedPayload)
        XCTAssertNil(stub.error)
    }

    func testErrorInit() throws {
        let expectedURL = url
        let expectedError = URLError(.resourceUnavailable, userInfo: [
            "Test": "Payload"
        ])

        let stub = NetworkResponseStub(url: URL(string: "https://localhost")!, error: expectedError)
        XCTAssertEqual(stub.url, expectedURL)
        XCTAssertNotNil(stub.error)
    }

    /// Validate the equality of two stubs.
    func testEquality() throws {
        let stub1 = NetworkResponseStub(url: url, statusCode: 200)
        let stub2 = NetworkResponseStub(url: url, statusCode: 200)
        let stub3 = NetworkResponseStub(url: URL(string: "https://justinw.me")!, statusCode: 404)
        let stub4 = NetworkResponseStub(url: URL(string: "https://justinw.me")!, error: URLError(.badURL))
        let stub5 = NetworkResponseStub(url: url, statusCode: 400)

        XCTAssertEqual(stub1, stub2)
        XCTAssertNotEqual(stub1, stub3)
        XCTAssertNotEqual(stub1, stub4)
        XCTAssertNotEqual(stub1, stub5)
    }

    /// Validate we can find the right stub in a collection.
    func testFindingStubByURLRequest() async throws {
        let stub1 = NetworkResponseStub(url: url, statusCode: 200)
        let stub2 = NetworkResponseStub(url: url.appending(queryItems: [ URLQueryItem(name: "test", value: "1,2,3") ]), statusCode: 200)
        let stub3 = NetworkResponseStub(url: url.appending(queryItems: [ URLQueryItem(name: "test", value: "4,5,6") ]), statusCode: 404)

        let collection = [
            stub1,
            stub2,
            stub3
        ]

        let request = URLRequest(url: stub2.url)
        let result = collection.find(for: request)

        XCTAssertNotNil(result)
        XCTAssertEqual(result, stub2)
    }
}
