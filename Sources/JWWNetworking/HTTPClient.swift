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
    ///   - delegate: Optional request preparation performed before every attempt.
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
        let request = try await builder.build(for: self)
        let response = try await execute(request: request)
        return try decode(response.data, template: type(of: template))
    }

    func decode<T: NetworkRequestTemplate>(_ data: Data, template: T.Type) throws(JWWNetworkError) -> T.Output {
        do {
            return try template.decode(response: data, with: configuration.decoder).0
        } catch {
            throw .decodingError(T.Output.self, data, error)
        }
    }

    func execute(request: URLRequest, requiresAuthentication: Bool = false,
                 validateReplay: Bool = false, expiresAt: Date? = nil,
                 now: @Sendable () -> Date = { Date() }) async throws(JWWNetworkError) -> HTTPResult {
        let idempotencyKey = request.value(forHTTPHeaderField: "Idempotency-Key")
        var request = request
        if requiresAuthentication, request.value(forHTTPHeaderField: "Authorization") == nil,
           let authentication = configuration.authentication {
            do {
                request.setValue("Bearer \(try await authentication.accessToken)", forHTTPHeaderField: "Authorization")
            } catch {
                throw .authenticationError(error)
            }
        }
        do {
            try await delegate.client(self, willSendRequest: &request)
        } catch {
            throw error as? JWWNetworkError ?? .untypedError(error: error)
        }
        if requiresAuthentication, request.value(forHTTPHeaderField: "Authorization") == nil {
            throw .authenticationError(URLError(.userAuthenticationRequired))
        }
        if validateReplay, request.httpBodyStream != nil || request.value(forHTTPHeaderField: "Idempotency-Key") != idempotencyKey {
            throw .invalidRequest
        }
        if let expiresAt, now() >= expiresAt {
            throw .untypedError(error: OfflineReplayExpired())
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .networkError(error)
        }
        guard let response = response as? HTTPURLResponse else {
            throw .invalidResponse(response)
        }
        guard HTTPURLResponse.successStatusCodes.contains(response.statusCode) else {
            throw .requestFailed(code: response.statusCode,
                                 message: HTTPURLResponse.localizedString(forStatusCode: response.statusCode))
        }
        return HTTPResult(data: data, statusCode: response.statusCode)
    }
}

struct HTTPResult: Sendable {
    let data: Data
    let statusCode: Int
}
