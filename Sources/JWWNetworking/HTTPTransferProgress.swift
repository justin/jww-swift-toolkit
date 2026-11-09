import Foundation

/// Byte counts reported by Foundation, without estimating an unknown total.
public struct HTTPTransferProgress: Sendable {
    /// Whether these counts describe an upload body or a download body.
    public enum Direction: Sendable {
        /// Bytes sent to the server.
        case upload
        /// Bytes received from the server.
        case download
    }

    /// Direction of the measured body.
    public let direction: Direction
    /// Number of bytes transferred so far.
    public let completedBytes: Int64
    /// Expected body size, or nil when Foundation does not know it.
    public let expectedBytes: Int64?

    init(direction: Direction, completed: Int64, expected: Int64) {
        self.direction = direction
        completedBytes = completed
        expectedBytes = expected < 0 ? nil : expected
    }
}
