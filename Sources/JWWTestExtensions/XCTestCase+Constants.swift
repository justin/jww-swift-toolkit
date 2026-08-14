import XCTest

public extension XCTestCase {
    /// The default amount of time to wait for an expectation to time out.
    static let defaultExpectationTimeout: TimeInterval = UITestTimeout.unitTestExpectation
}
