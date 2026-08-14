import Foundation
import JWWCore
@testable import JWWNetworking

/// Network request object that can have any of its values injected or adjusted.
struct NetworkRequestFake: GeneratedNetworkRequest {
    typealias Output = NetworkResponseFake

    var baseURL: URL?
    var path: String
    var method: HTTPMethod
    var queryItems: [URLQueryItem]
    var headers: [HTTPRequestHeaderKey: String]
    var body: Data?

    /// Create a new request template using the passed in components.
    init(baseURL: URL,
         path: String,
         queryItems: [URLQueryItem] = [],
         method: HTTPMethod,
         headers: [HTTPRequestHeaderKey: String] = [:],
         body: Data? = nil) {
        self.baseURL = baseURL
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }

}

/// Network response object we can use for basic tests.
struct NetworkResponseFake: Hashable, Sendable, Codable {
    /// The value to check against.
    let value: String
}

struct StaticRequestFake: StaticNetworkRequest {
    typealias Output = NetworkResponseFake
    let url: URL
    let method: HTTPMethod
    let body: Data?
    let headers: [HTTPRequestHeaderKey: String]

    /// Create a new request template using the passed in components.
    init(url: URL, method: HTTPMethod = .get, body: Data? = nil, headers: [HTTPRequestHeaderKey: String] = [:]) {
        self.url = url
        self.method = method
        self.body = body
        self.headers = headers
    }
}

/// Network request object that will always throw an error when being built since it is not a descendent
/// of 'GeneratedNetworkRequest' or 'StaticURLRequest'.
struct InvalidNetworkRequest: NetworkRequestTemplate {
    typealias Output = NetworkResponseFake

    let method: HTTPMethod = .get
    let body: Data? = nil
    let headers: [JWWNetworking.HTTPRequestHeaderKey: String] = [:]

    static func decode(response: Data, with decoder: JSONDecoder) throws -> (NetworkResponseFake, (any DecodingContext)?) {
        throw JWWNetworkError.invalidResponse(nil)
    }
}
