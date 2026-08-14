import Foundation

/// Primary client for accessing an HTTP API.
public actor HTTPClient {
    /// The network configuration to use for composing and sending requests.
    public nonisolated let configuration: Configuration

    /// The `URLSession` instance for making requests.
    public nonisolated let session: URLSession

    /// Object that contains configuration information for setting up the HTTP client.
    public struct Configuration: Sendable {
        /// The base URL to use for requests sent through the client.
        public let baseURL: URL

        /// The default decoder for parsing payloads.
        public let decoder: JSONDecoder

        /// The default encoder for converting JSON payloads.
        public let encoder: JSONEncoder

        /// Create and return a new HTTPClient configuration instance.
        ///
        /// - Parameters:
        ///   - baseURL: The base URL to use for requests sent through the client.
        ///   - decoder: The default decoder for parsing payloads.
        ///   - encoder: The default encoder for converting JSON payloads.
        public init(baseURL: URL, decoder: JSONDecoder = JSONDecoder(), encoder: JSONEncoder = JSONEncoder()) {
            self.baseURL = baseURL
            self.decoder = decoder
            self.encoder = encoder
        }
    }

    /// Encoder provided by the client configuration.
    private var encoder: JSONEncoder {
        configuration.encoder
    }

    /// Decoder provided by the client configuration.
    private var decoder: JSONDecoder {
        configuration.decoder
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
    public init(configuration: Configuration, session: URLSession = .shared) {
        self.session = session
        self.configuration = configuration
    }

    // MARK: Public Methods
    // ====================================
    // Public Methods
    // ====================================

    /// Convert a request template into a network request and attempt to return the expected values.
    @discardableResult
    public func send<T: NetworkRequest>(request: T) async throws -> NetworkResponse<T.Output> {
        let builder = NetworkRequestBuilder(template: request)
        let generatedRequest = try builder.build(for: self)

        let (data, response) = try await session.data(for: generatedRequest, delegate: nil)
        let (output, context) = try type(of: request).decode(response: data, with: decoder)

        let result = NetworkResponse(value: output, response: response, context: context)

        return result
    }

    /// Convert a request template into a network request and attempt to return the expected values.
    public func send<T: ComposedNetworkRequest>(collection: T) async throws -> T.Output {
        return try await collection.run(using: self)
    }
}
