import Foundation

/// An HTTP response, including unsuccessful status codes, delivered by a mock session.
public struct MockHTTPResponse: Sendable {
    /// The response status code. Custom numeric codes are supported.
    public let statusCode: Int
    /// Response headers passed through to Foundation.
    public let headers: [String: String]
    /// The response body, which may be empty or intentionally malformed.
    public let data: Data

    /// Create a response from exact bytes.
    public init(statusCode: Int = 200, headers: [String: String] = [:], data: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }

    /// Encode a value during setup, throwing immediately if encoding fails.
    public static func json<Value: Encodable>(_ value: Value, statusCode: Int = 200,
                                              headers: [String: String] = [:], encoder: JSONEncoder = JSONEncoder()) throws -> Self {
        Self(statusCode: statusCode, headers: contentHeaders(headers, defaultType: "application/json"), data: try encoder.encode(value))
    }

    /// Create a UTF-8 response, including intentionally malformed JSON.
    public static func text(_ text: String, statusCode: Int = 200,
                            headers: [String: String] = [:], contentType: String = "text/plain; charset=utf-8") -> Self {
        Self(statusCode: statusCode, headers: contentHeaders(headers, defaultType: contentType), data: Data(text.utf8))
    }

    /// Load exact bytes from the caller's resource bundle. Loading errors are setup errors.
    public static func fixture(_ name: String, extension fileExtension: String, bundle: Bundle,
                               statusCode: Int = 200, headers: [String: String] = [:]) throws -> Self {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            throw MockNetworkError("Missing fixture \(name).\(fileExtension) in \(bundle.bundlePath)")
        }
        return Self(statusCode: statusCode, headers: headers, data: try Data(contentsOf: url))
    }

    /// Adds a default content type only when no case-insensitive Content-Type key exists.
    /// Preserves the caller's header spelling and values, including explicit overrides.
    private static func contentHeaders(_ headers: [String: String], defaultType: String) -> [String: String] {
        guard !headers.keys.contains(where: { $0.lowercased() == "content-type" }) else { return headers }
        return headers.merging(["Content-Type": defaultType]) { existing, _ in existing }
    }
}

/// A delivered HTTP response or a transport failure with no HTTP response.
public enum MockOutcome: Sendable {
    /// Deliver status, headers, and bytes, even for HTTP error statuses.
    case response(MockHTTPResponse)
    /// Fail with the supplied error, preserving its domain, code, and user information.
    case failure(any Error)
}

/// A setup, matching, or verification failure in a mock network.
public struct MockNetworkError: Error, Sendable, CustomStringConvertible, LocalizedError {
    /// A diagnostic describing the request and expectation involved.
    public let description: String
    /// The diagnostic used by Foundation when bridging this error.
    public var errorDescription: String? { description }

    /// Creates a diagnostic error from a setup, request-matching, or lifecycle failure.
    init(_ description: String) {
        self.description = description
    }
}
