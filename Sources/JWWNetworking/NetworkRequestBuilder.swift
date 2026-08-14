import Foundation

/// Type that converst a network request template into a valid `URLRequest` object.
public final class NetworkRequestBuilder {
    /// The request template to convert into a `URLRequest`.
    public let template: any NetworkRequestTemplate

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    /// Create a new request builder.
    ///
    /// - Parameters:
    ///   - template: The request template to convert into a `URLRequest`.
    public init(template: some NetworkRequestTemplate) {
        self.template = template
    }

    // MARK: Action Methods
    // ====================================
    // Action Methods
    // ====================================

    /// Convert a request template into a valid `URLRequest`.
    ///
    /// - Returns: A valid `URLRequest` that can be passed into a `URLSession`.
    public func build(for client: HTTPClient) async throws(JWWNetworkError) -> URLRequest {
        switch template {
        case let generatedTemplate as any GeneratedNetworkRequest:
            return try await buildGeneratedRequest(template: generatedTemplate, client: client)
        case let staticURLTemplate as any StaticNetworkRequest:
            return try await buildURLRequest(template: staticURLTemplate, client: client)
        default:
            throw JWWNetworkError.invalidRequest
        }
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    private func buildGeneratedRequest(template: any GeneratedNetworkRequest, client: HTTPClient) async throws(JWWNetworkError) -> URLRequest {
        let url = template.baseURL ?? client.configuration.baseURL

        guard let url else {
            throw JWWNetworkError.invalidRequest
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.pathValue = Path(template.path)
        if !template.queryItems.isEmpty {
            components?.queryItems = template.queryItems
        }

        guard let url = components?.url else {
            throw JWWNetworkError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = String(describing: template.method)
        request.allHTTPHeaderFields = try await buildRequestHeaders(client: client)
        request.httpBody = template.body

        return request
    }

    private func buildRequestHeaders(client: HTTPClient) async throws(JWWNetworkError) -> [String: String] {
        var serviceHeaders: [String: String] = [:]

        if let userAgent = client.configuration.userAgent {
            serviceHeaders[HTTPRequestHeaderKey.userAgent.value] = userAgent
        }

        if let authenticationController = client.configuration.authentication, template is (any AuthenticatedRequest) {
            do {
                let token = try await authenticationController.accessToken
                serviceHeaders[HTTPRequestHeaderKey.authorization.value] = "Bearer \(token)"
            } catch {
                throw JWWNetworkError.authenticationError(error)
            }
        }

        let requestHeaders: [String: String] = template.headers.reduce(into: [:]) { result, x in
            result[x.key.value] = x.value
        }.merging(serviceHeaders) { (requestHeader, _) -> String in
            // Prefer request-specific headers to service-wide headers.
            return requestHeader
        }

        return requestHeaders
    }

    private func buildURLRequest(template: any StaticNetworkRequest, client: HTTPClient) async throws(JWWNetworkError) -> URLRequest {
        let url = template.url

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let url = components?.url else {
            throw JWWNetworkError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = String(describing: template.method)
        request.allHTTPHeaderFields = try await buildRequestHeaders(client: client)
        request.httpBody = template.body

        return request
    }
}

private extension URLComponents {
    /// Path support for `URLComponents`.
    var pathValue: Path {
        get {
            Path(path)
        }

        set {
            path = newValue.pathValue
        }
    }
}
