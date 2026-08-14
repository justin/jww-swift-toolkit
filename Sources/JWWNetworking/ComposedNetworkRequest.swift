import Foundation

public protocol ComposedNetworkRequest {
    /// The type of response object that should be parsed.
    associatedtype Output
    /// The type of error that will be returned upon failure.
    associatedtype Failure = Error

    func run(using client: HTTPClient) async throws -> Output
}
