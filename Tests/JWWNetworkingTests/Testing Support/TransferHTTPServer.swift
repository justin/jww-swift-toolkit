import Foundation
import Network
import Synchronization

/// Loopback HTTP fixture for actual Foundation file tasks, redirects, and response chunks.
/// It is deliberately limited to Content-Length requests and one request per connection.
final class TransferHTTPServer: Sendable {
    struct Request: Sendable {
        let head: String
        let body: Data
    }

    let listener: NWListener
    private let connections = Mutex<[NWConnection]>([])
    private let queue = DispatchQueue(label: "JWWNetworking.transfer-test-server")

    init(handler: @escaping @Sendable (Request, NWConnection) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connections.withLock { $0.append(connection) }
            connection.start(queue: queue)
            RequestReader(connection: connection, handler: handler).read()
        }
    }

    func start() async throws -> URL {
        let started = Mutex(false)
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    let wasStarted = started.withLock { value in
                        let previous = value
                        value = true
                        return previous
                    }
                    if let port = listener.port, !wasStarted {
                        continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/file")!)
                    }
                case .failed(let error):
                    let wasStarted = started.withLock { value in
                        let previous = value
                        value = true
                        return previous
                    }
                    if !wasStarted { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        connections.withLock { values in
            values.forEach { $0.cancel() }
            values.removeAll()
        }
    }

    static func respond(_ connection: NWConnection, status: Int = 200, headers: [String: String] = [:], body: Data) {
        var fields = headers
        fields["Content-Type"] = fields["Content-Type"] ?? "application/octet-stream"
        fields["Content-Length"] = String(body.count)
        fields["Connection"] = "close"
        let head = "HTTP/1.1 \(status) Test\r\n" + fields.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Each reader is confined to its connection's serial callback queue.
private final class RequestReader: @unchecked Sendable {
    let connection: NWConnection
    let handler: @Sendable (TransferHTTPServer.Request, NWConnection) -> Void
    var buffer = Data()

    init(connection: NWConnection, handler: @escaping @Sendable (TransferHTTPServer.Request, NWConnection) -> Void) {
        self.connection = connection
        self.handler = handler
    }

    func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, ended, error in
            if let data { buffer.append(data) }
            if let separator = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: buffer[..<separator.lowerBound], encoding: .utf8) ?? ""
                let length = head.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                if buffer.count - separator.upperBound >= length {
                    handler(.init(head: head, body: Data(buffer[separator.upperBound...].prefix(length))), connection)
                    return
                }
            }
            if !ended, error == nil { read() } else { connection.cancel() }
        }
    }
}
