import Foundation

public enum UITestTimeout {
    /// The default amount of time to wait for an expectation to time out.
    public static let unitTestExpectation: TimeInterval = 2.0

    /// The default amount of time to wait for an item to appear on screen during a UI test.
    public static let uiTestExpectation: TimeInterval = 10.0

    /// The multiplier to use when determing how long to wait for a UI element to appear.
    public static let appearMultiplier: TimeInterval = 1.0

    /// The multiplier to use when determing how long to wait for a UI element to disappear.
    public static let disappearMultiplier: TimeInterval = 1.0
}
