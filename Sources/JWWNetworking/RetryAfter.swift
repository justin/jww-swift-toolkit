import Foundation

/// Only the status and retry deadline cross into queue scheduling; response headers are not persisted.
struct HTTPRetryFailure: Error {
    let statusCode: Int
    let retryAfter: Date?
    var networkError: JWWNetworkError {
        .requestFailed(code: statusCode, message: HTTPURLResponse.localizedString(forStatusCode: statusCode))
    }
}

enum RetryAfter {
    static func date(_ header: String?, now: Date) -> Date? {
        guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value.count <= 128 else { return nil }
        if value.utf8.allSatisfy({ (48...57).contains($0) }), let seconds = Double(value), seconds.isFinite {
            return now.addingTimeInterval(min(seconds, Date.distantFuture.timeIntervalSince(now)))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
