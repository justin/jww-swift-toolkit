import Foundation

/// Object that encapsulates data related to a response returned by the `HTTPClient`.
public struct NetworkResponse<Output> {

    /// The decoded value returned by the request.
    public let value: Output

    /// The response object returned by `URLSession`.
    public let response: URLResponse

    /// Optional. The decoding context used during value decoding.
    public let context: DecodingContext?
}
