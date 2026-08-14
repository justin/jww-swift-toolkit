import Foundation
import JWWCore

/// Typealias for `GeneratedNetworkRequest` to maintain backwards compatibility.
@available(*, deprecated, renamed: "GeneratedNetworkRequest")
public typealias NetworkRequest = GeneratedNetworkRequest

/// Protocol that defines the attributes and methods needed to generate a request that uses a predefined URL.
public protocol StaticNetworkRequest<Output, Failure>: NetworkRequestTemplate {
    /// The predefined URL for the request.
    var url: URL { get }
}

/// Protocol that defines the attributes and methods needed to generate a request JWWNetworking can understand.
public protocol GeneratedNetworkRequest<Output, Failure>: NetworkRequestTemplate {
    /// The base URL for the request. If nil, the client will use the URL provided in the `HTTPClient.Configuration`
    var baseURL: URL? { get }

    @available(*, deprecated, renamed: "baseURL")
    var url: URL? { get }

    /// The path for the request.
    var path: String { get }

    /// The query parameters to append to the request.
    var queryItems: [URLQueryItem] { get }
}

/// Protocol that defines the base attributes and methods needed to generate a request JWWNetworking can understand.
///
/// You shouldn't use this protocol directly. Instead, use `StaticURLRequest` or `GeneratedNetworkRequest`.
public protocol NetworkRequestTemplate<Output, Failure>: Sendable {
    /// The type of response object that should be parsed.
    associatedtype Output: Decodable
    /// The type of error that will be returned upon failure.
    associatedtype Failure = Error

    /// The HTTP method for the request.
    var method: HTTPMethod { get }

    /// Optional. Request body.
    var body: Data? { get }

    /// The headers to attach to the request.
    var headers: [HTTPRequestHeaderKey: String] { get }

    /// Decode the passed in Data and return a valid response object.
    /// - Parameter response: The `Data` object to decode.
    ///
    /// - Returns: A decoded object of type `ResponseObject`.
    static func decode(response: Data, with decoder: JSONDecoder) throws -> (Output, DecodingContext?)
}

// MARK: Default Implementations
// ====================================
// Default Implementations
// ====================================

extension NetworkRequestTemplate where Self: GeneratedNetworkRequest {
    public var url: URL? { baseURL }

    public static func decode(response: Data, with decoder: JSONDecoder) throws -> (Output, DecodingContext?) {
        let result = try decoder.decode(Output.self, from: response)
        return (result, decoder.context)
    }
}

extension NetworkRequestTemplate where Self: StaticNetworkRequest {
    public static func decode(response: Data, with decoder: JSONDecoder) throws -> (Output, DecodingContext?) {
        let result = try decoder.decode(Output.self, from: response)
        return (result, decoder.context)
    }
}

// MARK: Authenticated Requests
// ====================================
// Authenticated Requests
// ====================================

/// Protocol that defines the attributes and methods needed to generate an authenticated request
/// JWWNetworking can understand.
public protocol AuthenticatedRequest {
    /// The type of authentication to use for the request.
    var authenticationType: AuthenticationType { get }
}

/// Supported authentication types when making an `AuthenticatedRequest`
public enum AuthenticationType: Sendable, Equatable {
    /// Setting the Authorization field with a Bearer token.
    case bearer
}
