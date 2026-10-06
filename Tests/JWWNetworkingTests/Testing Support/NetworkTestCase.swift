import XCTest
import JWWNetworking
import JWWTestExtensions

/// Shared client setup backed by the same isolated harness available to package consumers.
class NetworkTestCase: XCTestCase {
    var client: HTTPClient!
    var network: MockNetwork!
    var session: URLSession { network.session }

    override func setUp() async throws {
        try await super.setUp()
        network = MockNetwork()
        client = HTTPClient(configuration: HTTPClient.Configuration(baseURL: TestingConstants.baseURL), session: session)
    }

    override func tearDown() async throws {
        defer {
            network.close()
            network = nil
            client = nil
        }
        try network.verify()
        try await super.tearDown()
    }
}
