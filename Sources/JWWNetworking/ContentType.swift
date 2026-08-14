import Foundation

/// A type-safe value that can be used to declare the MIME type
public struct ContentType: Hashable, CustomStringConvertible, Sendable {
    /// The content type name that is passed as the value in the HTTP header.
    public let value: String

    /// Create a ContentType object
    ///
    /// - Parameter value: The content type name that is passed as the value in the HTTP header.
    public init(_ value: String) {
        self.value = value
    }

    public nonisolated var description: String {
        value
    }
}

public extension ContentType {
    /// Content type for plain text.
    static let text = ContentType("text/plain")

    /// Content type for JSON.
    static let json = ContentType("application/json")
}
