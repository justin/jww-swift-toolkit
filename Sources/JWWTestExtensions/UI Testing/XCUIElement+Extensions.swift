import XCTest

extension XCUIElement {
    /// Convenience function for waiting for the element to exist.
    ///
    /// - parameter timeout: Maximum time to wait for the element.
    public func wait(for timeout: TimeInterval = UITestTimeout.uiTestExpectation) {
        guard self.waitForExistence(timeout: timeout) else {
            XCTFail("UI Wait Timeout: '\(self)' did not come into existence after waiting for \(timeout) seconds.")
            return
        }
    }
}
