import Foundation

/// Custom type that allows us to set values we want to return in a `Foundation.URLResponse` or
/// `Foundation.HTTPURLResponse`.
public struct NetworkResponseStub: Equatable, Sendable {
  /// The URL for the response.
  public let url: URL
  /// The response’s HTTP status code.
  public let statusCode: Int

  /// All HTTP header fields of the response.
  public let allHeaderFields: [String: String] = [:]

  /// The version of the HTTP response as returned by the server.
  public let version = "HTTP/2.0"

  /// The response's body payload, if set.
  public private(set) var data: Data?

  /// The response's generated error, if set.
  public private(set) var error: Error?

  // MARK: Initialization
  // ====================================
  // Initialization
  // ====================================

  /// Create a mock response with a given status code.
  public init(url: URL, statusCode: Int) {
    self.url = url
    self.statusCode = statusCode
  }

  /// Create a mock response with a status code and response body data.
  public init(url: URL, statusCode: Int, data: Data) {
    self.init(url: url, statusCode: statusCode)
    self.data = data
  }

  /// Create a mock response with a status code and system error we want to pass back.
  public init(url: URL, error: Error) {
    self.init(url: url, statusCode: (error as? CustomNSError)?.errorCode ?? -1)
    self.error = error
  }

  public static func == (lhs: NetworkResponseStub, rhs: NetworkResponseStub) -> Bool {
    return lhs.url == rhs.url && lhs.statusCode == rhs.statusCode
  }
}

extension Collection where Element == NetworkResponseStub {
  func find(for request: URLRequest) -> NetworkResponseStub? {
    guard let url = request.url,
      let requestComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      return nil
    }

    let filtered = reversed()
      .filter { stub in
        stub.url.pathComponents == request.url?.pathComponents
      }
      .first { stub in
        let components = URLComponents(url: stub.url, resolvingAgainstBaseURL: false)
        return components?.queryItems == requestComponents.queryItems
      }

    return filtered
  }
}
