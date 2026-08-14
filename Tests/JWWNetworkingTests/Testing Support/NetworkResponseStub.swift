import Foundation

/// Custom type that allows us to set values we want to return in a `Foundation.URLResponse` or
/// `Foundation.HTTPURLResponse`.
struct NetworkResponseStub: Equatable {
  /// The URL for the response.
  let url: URL

  /// The response’s HTTP status code.
  let statusCode: Int

  /// All HTTP header fields of the response.
  let allHeaderFields: [String: String] = [:]

  /// The version of the HTTP response as returned by the server.
  let version = "HTTP/1.1"

  /// The response's body payload, if set.
  private(set) var data: Data?

  /// The response's generated error, if set.
  private(set) var error: Error?

  // MARK: Initialization
  // ====================================
  // Initialization
  // ====================================

  /// Create a mock response with a given status code.
  init(url: URL, statusCode: Int) {
    self.url = url
    self.statusCode = statusCode
  }

  /// Create a mock response with a status code and response body data.
  init(url: URL, statusCode: Int, data: Data) {
    self.init(url: url, statusCode: statusCode)
    self.data = data
  }

  /// Create a mock response with a status code and system error we want to pass back.
  init(url: URL, error: Error) {
    self.init(url: url, statusCode: (error as? CustomNSError)?.errorCode ?? -1)
    self.error = error
  }

  static func == (lhs: NetworkResponseStub, rhs: NetworkResponseStub) -> Bool {
    return lhs.url == rhs.url
  }
}
