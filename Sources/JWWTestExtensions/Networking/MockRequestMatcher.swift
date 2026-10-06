import Foundation

/// Exact URL and method matching with optional header and body constraints.
public struct MockRequestMatcher: Sendable {
    /// HTTP methods supported by the convenience API; the string initializer supports other methods.
    public enum Method: String, Sendable {
        /// Retrieve a resource.
        case get = "GET"
        /// Submit a resource.
        case post = "POST"
        /// Replace a resource.
        case put = "PUT"
        /// Partially update a resource.
        case patch = "PATCH"
        /// Delete a resource.
        case delete = "DELETE"
        /// Retrieve response headers.
        case head = "HEAD"
        /// Retrieve supported communication options.
        case options = "OPTIONS"
    }

    /// The expected HTTP method, compared case-sensitively.
    public let method: String
    /// The full URL, including query order.
    public let url: URL
    /// Required headers. Header names are compared case-insensitively, values exactly.
    public let headers: [String: String]
    /// Expected bytes; nil leaves the request body unconstrained.
    public let body: Data?

    /// Create an expectation for a standard HTTP method.
    public init(_ method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.init(method: method.rawValue, url: url, headers: headers, body: body)
    }

    /// Create an expectation including custom HTTP methods.
    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    /// Returns diagnostic reasons for every unmet request constraint; an empty array means a match.
    ///
    /// The URL comparison includes scheme, host, port, path, and query ordering. Header names are
    /// case-insensitive; header values and body bytes are exact. The caller must materialize body streams
    /// before matching. Header values and body contents are omitted from diagnostics.
    func mismatches(_ request: URLRequest) -> [String] {
        var reasons: [String] = []
        if request.httpMethod != method { reasons.append("method expected \(method)") }
        if request.url?.absoluteString != url.absoluteString { reasons.append("URL expected \(url.absoluteString)") }
        for key in headers.keys.sorted() where request.value(forHTTPHeaderField: key) != headers[key] {
            reasons.append("header \(key) differs")
        }
        if let body, request.httpBody != body { reasons.append("body differs (expected \(body.count) bytes)") }
        return reasons
    }
}
