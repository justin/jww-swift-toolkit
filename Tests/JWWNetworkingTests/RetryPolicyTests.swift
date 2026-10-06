import Foundation
import Testing
@testable import JWWNetworking

struct RetryPolicyTests {
    @Test
    func testExponentialBackoffCapsAndPersists() throws {
        let policy = try RetryPolicy(maximumRetries: 6, schedule: .exponential(initialDelay: 5, multiplier: 2, maximumDelay: 60))
        #expect((1...6).map { policy.delay(retry: $0, random: 0.5) } == [5, 10, 20, 40, 60, 60])
        let decoded = try JSONDecoder().decode(RetryPolicy.self, from: JSONEncoder().encode(policy))
        #expect(decoded == policy)
        #expect(policy.delay(retry: Int.max, random: 1) == 60)
    }

    @Test
    func testFixedIntervalsAndJitter() throws {
        let fixed = try RetryPolicy(schedule: .fixed(10), jitterFraction: 0.2)
        #expect(fixed.delay(retry: 1, random: 0) == 8)
        #expect(fixed.delay(retry: 2, random: 1) == 12)
        let intervals = try RetryPolicy(schedule: .intervals([5, 30, 120]))
        #expect((1...4).map { intervals.delay(retry: $0, random: 0.5) } == [5, 30, 120, 120])
        let capped = try RetryPolicy(schedule: .exponential(initialDelay: 10, multiplier: 2, maximumDelay: 10), jitterFraction: 0.2)
        #expect(capped.delay(retry: 1, random: 1) == 10)
    }

    @Test
    func testFullJitterAlwaysAdvancesSchedule() throws {
        for schedule in [RetrySchedule.fixed(10), .intervals([10]),
                         .exponential(initialDelay: 10, multiplier: 2, maximumDelay: 60)] {
            let policy = try RetryPolicy(schedule: schedule, jitterFraction: 1)
            #expect(policy.delay(retry: 1, random: 0) == 1)
        }
        let subsecond = try RetryPolicy(schedule: .fixed(0.1), jitterFraction: 1)
        #expect(subsecond.delay(retry: 1, random: 0) == 0.1)
    }

    @Test
    func testNoRetryPolicies() throws {
        #expect(try !RetryPolicy(schedule: .none).isEnabled)
        #expect(try !RetryPolicy(maximumRetries: 0, schedule: .fixed(10)).isEnabled)
        #expect(try !RetryPolicy(maximumRetries: -1, schedule: .none, jitterFraction: .nan).isEnabled)
    }

    @Test
    func testInvalidPoliciesAreRejected() {
        for schedule in [RetrySchedule.fixed(0), .fixed(.infinity), .intervals([]), .intervals([1, -1]),
                         .exponential(initialDelay: 5, multiplier: 0.5, maximumDelay: 60),
                         .exponential(initialDelay: 5, multiplier: 2, maximumDelay: 4)] {
            #expect(throws: OfflineQueueError.self) { try RetryPolicy(schedule: schedule) }
        }
        #expect(throws: OfflineQueueError.self) { try RetryPolicy(maximumRetries: -1, schedule: .fixed(1)) }
        #expect(throws: OfflineQueueError.self) { try RetryPolicy(schedule: .fixed(1), jitterFraction: .nan) }
        #expect(throws: OfflineQueueError.self) { try RetryPolicy(schedule: .fixed(1), maximumAge: 0) }
    }
}
