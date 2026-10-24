import Foundation
import Testing
import JWWTestExtensions

struct MockHTTPResponseTests {
    private struct Payload: Codable, Equatable {
        let serverKey: String
    }

    @Test
    func testJSONFactoryUsesSuppliedEncoderAndHeaders() async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let response = try MockHTTPResponse.json(Payload(serverKey: "value"), statusCode: 201,
                                                headers: ["content-type": "application/custom+json", "X-Test": "value"], encoder: encoder)
        let object = try #require(JSONSerialization.jsonObject(with: response.data) as? [String: String])
        #expect(object == ["server_key": "value"])
        #expect(response.headers["Content-Type"] == nil)
        try await withMockNetwork { network in
            let url = URL(string: "https://mock.invalid/created")!
            try network.expect(.init(.get, url: url), outcome: .response(response))
            let (data, received) = try await network.session.data(from: url)
            let http = try #require(received as? HTTPURLResponse)
            #expect(http.statusCode == 201)
            #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/custom+json")
            #expect(http.value(forHTTPHeaderField: "X-Test") == "value")
            #expect(data == response.data)
        }
        #expect(try MockHTTPResponse.json(["key": "value"]).headers["Content-Type"] == "application/json")
    }

    @Test
    func testEncodingFailureIsASetupError() {
        #expect(throws: EncodingError.self) { try MockHTTPResponse.json(Double.nan) }
    }

    @Test
    func testResourceFixturePreservesServerBytes() throws {
        let response = try MockHTTPResponse.fixture("response", extension: "json", bundle: .module)
        #expect(String(data: response.data, encoding: .utf8) == "{\"server_key\":\"from fixture\"}\n")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        #expect(try decoder.decode(Payload.self, from: response.data) == Payload(serverKey: "from fixture"))
        #expect(throws: MockNetworkError.self) {
            try MockHTTPResponse.fixture("does-not-exist", extension: "json", bundle: .module)
        }
    }

    @Test(arguments: [Data(), Data([0, 255, 128]), Data("{ invalid JSON".utf8)])
    func testRawPayloadIsDeliveredUnchanged(data: Data) async throws {
        try await withMockNetwork { network in
            let url = URL(string: "https://mock.invalid/raw")!
            try network.expect(.init(.get, url: url), outcome: .response(.init(data: data)))
            let (received, _) = try await network.session.data(from: url)
            #expect(received == data)
        }
    }
}
