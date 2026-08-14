import XCTest
import os

enum TestingConstants {
    /// Throwaway URL that can be used for testing purposes.
    static let baseURL: URL = URL(string: "https://localhost")!
}

extension Logger {
    /// Default logger for UI.
    static let testing = Logger(subsystem: "com.justinwme.jww-networking", category: "testing")
}
