import Foundation

/// Primary client for accessing an HTTP API.
public actor HTTPClient {
    /// The network configuration to use for composing and sending requests.
    public let configuration: Configuration

    /// The `URLSession` instance for making requests.
    public let session: URLSession

    private let delegate: HTTPClientDelegate

    /// Object that contains configuration information for setting up the HTTP client.
    public final class Configuration: Sendable {
        /// Optional. The base URL to use for requests sent through the client. If this is not set,
        /// the client will use the URL provided in the request template. If neither is set the client will throw an error of type `JWWNetworkError.invalidRequest`.
        public let baseURL: URL?

        /// The user agent to use for requests sent through the client.
        public let userAgent: String?

        /// The default decoder for parsing payloads.
        public let decoder: JSONDecoder

        /// The default encoder for converting JSON payloads.
        public let encoder: JSONEncoder

        /// Optional. The authentication provider to use for setting the access token for requests.
        public let authentication: AuthenticationProvider?

        /// Create and return a new HTTPClient configuration instance.
        ///
        /// - Parameters:
        ///   - baseURL: Optional. The base URL to use for requests sent through the client. If this is not set,
        ///   the client will use the URL provided in the request template. If neither is set the client will throw an error.
        ///   - userAgent: The user agent to use for requests sent through the client.
        ///   - authentication: Optional. The authentication provider to use for setting the access token for requests.
        ///   - decoder: The default decoder for parsing payloads.
        ///   - encoder: The default encoder for converting JSON payloads.
        public init(baseURL: URL?,
                    userAgent: String? = nil,
                    authentication: AuthenticationProvider? = nil,
                    decoder: JSONDecoder = JSONDecoder(),
                    encoder: JSONEncoder = JSONEncoder()) {
            self.baseURL = baseURL
            self.userAgent = userAgent
            self.decoder = decoder
            self.encoder = encoder
            self.authentication = authentication
        }
    }

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    /// Create and return a new HTTPClient object.
    ///
    /// - Parameters:
    ///   - configuration: The network configuration to use for composing and sending requests.
    ///   - session: The `URLSession` instance for making requests.
    public init(configuration: Configuration, session: URLSession = .shared, delegate: HTTPClientDelegate? = nil) {
        self.session = session
        self.configuration = configuration
        self.delegate = delegate ?? DefaultHTTPClientDelegate()
    }

    // MARK: Public Methods
    // ====================================
    // Public Methods
    // ====================================

    /// Convert a request template into a network request and attempt to return the expected values.
    @discardableResult
    public func send<T: NetworkRequestTemplate>(template: T) async throws(JWWNetworkError) -> T.Output {
        let builder = NetworkRequestBuilder(template: template)
        var generatedRequest = try await builder.build(for: self)

        do {
            try await delegate.client(self, willSendRequest: &generatedRequest)

            let (data, response) = try await session.data(for: generatedRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JWWNetworkError.invalidResponse(response)
            }

            let statusCode = httpResponse.statusCode
            if statusCode == 401 {
                let message = HTTPURLResponse.localizedString(forStatusCode: statusCode)
                throw JWWNetworkError.requestFailed(code: statusCode, message: message)
            }

            guard HTTPURLResponse.successStatusCodes.contains(statusCode) else {
                let message = HTTPURLResponse.localizedString(forStatusCode: statusCode)
                throw JWWNetworkError.requestFailed(code: statusCode, message: message)
            }

            let decoder = configuration.decoder
            do {
                let (object, _) = try type(of: template).decode(response: data, with: decoder)
                return object
            } catch {
                throw JWWNetworkError.decodingError(type(of: template).Output.self, data, error)
            }
        } catch let error as JWWNetworkError {
            throw error
        } catch let error {
            throw JWWNetworkError.untypedError(error: error)
        }
    }
}
