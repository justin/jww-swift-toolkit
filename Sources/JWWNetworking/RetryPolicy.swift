import Foundation

/// The spacing between automatic retry attempts. See <doc:OfflineRequests>.
public enum RetrySchedule: Codable, Sendable, Equatable {
    /// Send once without persisting or retrying failures.
    case none
    /// Wait the same number of seconds before each retry.
    case fixed(TimeInterval)
    /// Increase the interval until reaching the maximum, in seconds.
    case exponential(initialDelay: TimeInterval, multiplier: Double, maximumDelay: TimeInterval)
    /// Use each interval in order, then repeat the last interval.
    case intervals([TimeInterval])
}

/// Validated limits and timing for an offline operation.
public struct RetryPolicy: Codable, Sendable, Equatable {
    /// Retries after the initial attempt. Zero disables persistence.
    public let maximumRetries: Int
    /// The spacing between retries. `.none` disables persistence.
    public let schedule: RetrySchedule
    /// Random variation around the interval, from zero through one.
    public let jitterFraction: Double
    /// Maximum operation lifetime in seconds, measured from submission.
    public let maximumAge: TimeInterval

    /// Creates a policy, rejecting invalid retry counts, intervals, and jitter.
    /// Timing values must be finite. Retry-specific values are ignored for `.none`.
    public init(maximumRetries: Int = 3, schedule: RetrySchedule = .none,
                jitterFraction: Double = 0, maximumAge: TimeInterval = 86_400) throws {
        self.maximumRetries = maximumRetries
        self.schedule = schedule
        self.jitterFraction = jitterFraction
        self.maximumAge = maximumAge
        try validate()
    }

    var isEnabled: Bool { schedule != .none && maximumRetries > 0 }

    func validate() throws {
        guard schedule != .none else { return }
        guard maximumRetries >= 0, maximumRetries < Int.max,
              maximumAge.isFinite, maximumAge > 0,
              jitterFraction.isFinite, (0...1).contains(jitterFraction) else {
            throw OfflineQueueError.invalidPolicy
        }
        switch schedule {
        case .none:
            break
        case .fixed(let interval):
            guard interval.isFinite, interval > 0 else { throw OfflineQueueError.invalidPolicy }
        case .intervals(let intervals):
            guard !intervals.isEmpty, intervals.allSatisfy({ $0.isFinite && $0 > 0 }) else {
                throw OfflineQueueError.invalidPolicy
            }
        case .exponential(let initial, let multiplier, let maximum):
            guard initial.isFinite, initial > 0, multiplier.isFinite, multiplier >= 1,
                  maximum.isFinite, maximum >= initial else { throw OfflineQueueError.invalidPolicy }
        }
    }

    // Retry numbering starts at one. Randomness is injected so scheduling tests need no real sleeps.
    func delay(retry: Int, random: Double) -> TimeInterval {
        let interval: TimeInterval
        let cap: TimeInterval
        switch schedule {
        case .none:
            return 0
        case .fixed(let value):
            interval = value
            cap = .greatestFiniteMagnitude
        case .intervals(let values):
            interval = values[min(max(0, retry - 1), values.count - 1)]
            cap = .greatestFiniteMagnitude
        case .exponential(let initial, let multiplier, let maximum):
            interval = min(maximum, initial * pow(multiplier, Double(max(0, retry - 1))))
            cap = maximum
        }
        let factor = 1 + jitterFraction * (2 * min(1, max(0, random)) - 1)
        // Full jitter must still advance the schedule. Preserve subsecond configured intervals.
        return max(min(interval, 1), min(cap, interval * factor))
    }
}
