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

        let response = try await client.send(request: template)

        XCTAssertEqual(response.value, fakeResponse)
    }

    /// Validate we can send a single request and have it throw an error.
    func testFailedRequest() async throws {
        let template = NetworkRequestFake(baseURL: TestingConstants.baseURL, path: "/test", method: .get)
        let error = URLError(.badURL)
        try await addStubResponse(forTemplate: template, error: error)

        await JWWAssertThrowsError(try await client.send(request: template)) { error in
            XCTAssertTrue(error is URLError, "Expected error type returned to be a URLError.")
        }
    }

    // MARK: Dependent Request Tests
    // ====================================
    // Dependent Request Tests
    // ====================================

    /// Validate we can parse a payload that requires two requests to generate its output.
    func testDependentRequestParsing() async throws {
        let requestOne = EventRequest()
        let requestTwo = TeamRequest()
        try await addStubResponse(forTemplate: requestOne,
                                  statusCode: 200,
                                  response: EventResponse(id: 123, homeTeamId: 16, awayTeamId: 24))

        try await addStubResponse(forTemplate: requestTwo,
                                  statusCode: 200,
                                  response: [
                                    Team(id: 16, name: "Chiefs"),
                                    Team(id: 24, name: "Eagles")
                                  ])

        let queue = DependentRequest()
        let expectedResult = Event(id: 123,
                                   homeTeam: Team(id: 16, name: "Chiefs"),
                                   awayTeam: Team(id: 24, name: "Eagles"))

        let result = try await client.send(collection: queue)

        XCTAssertEqual(result, expectedResult, "Expected.")
    }
}

struct DependentRequest: ComposedNetworkRequest {
    typealias Output = Event

    func run(using client: HTTPClient) async throws -> Event {
        let requestOne = EventRequest()
        let requestTwo = TeamRequest()
        let responseOne = try await client.send(request: requestOne)
        let responseTwo = try await client.send(request: requestTwo)

        let response = DependentResponse(responseOne: responseOne, responseTwo: responseTwo)
        return try response.resolve()
    }
}

struct EventRequest: NetworkRequest {
    typealias Output = EventResponse
    let method: JWWNetworking.HTTPMethod = .get
    let path: String = "/first"
    let body: Data? = nil
    let queryItems: [URLQueryItem] = []
    let headers: [JWWNetworking.HTTPRequestHeaderKey: String] = [:]
}

struct EventResponse: Codable {
    let id: Int
    let homeTeamId: Int
    let awayTeamId: Int
}

struct TeamRequest: NetworkRequest {
    typealias Output = [Team]

    let method: JWWNetworking.HTTPMethod = .get
    let path: String = "/second"
    let body: Data? = nil
    let queryItems: [URLQueryItem] = []
    let headers: [JWWNetworking.HTTPRequestHeaderKey: String] = [:]
}

private struct DependentResponse {
    let responseOne: NetworkResponse<EventResponse>
    let responseTwo: NetworkResponse<[Team]>

    func resolve() throws -> Event {
        let eventResponse = responseOne.value
        let homeTeam = responseTwo.value.first(where: { team in
            team.id == eventResponse.homeTeamId
        })
        let awayTeam = responseTwo.value.first(where: { team in
            team.id == eventResponse.awayTeamId
        })
        guard let homeTeam, let awayTeam else {
            throw URLError(.badURL)
        }

        return Event(id: eventResponse.id, homeTeam: homeTeam, awayTeam: awayTeam)
    }
}

struct Event: Hashable {
    let id: Int
    let homeTeam: Team
    let awayTeam: Team
}

struct Team: Hashable, Codable {
    let id: Int
    let name: String
}
