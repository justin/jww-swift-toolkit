import Foundation

/// A type that handles authentication challenges for an `HTTPClient`.
public protocol AuthenticationProvider: Actor {
    /// The access token to use for authentication.
    var accessToken: String { get async throws }

    /// Request a new access token using a refresh token.
    func refreshAccessToken(refreshToken: String) async throws -> String
}

public protocol HTTPClientDelegate: Sendable {
    func client(_ client: HTTPClient, willSendRequest request: inout URLRequest) async throws
}

public extension HTTPClientDelegate {
    func client(_ client: HTTPClient, willSendRequest request: inout URLRequest) async throws {
        // no-op
    }
}

final class DefaultHTTPClientDelegate: HTTPClientDelegate {}
