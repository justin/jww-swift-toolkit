import XCTest

/// The primary class for defining UI test cases in test bundles.
open class XCUITestCase: XCTestCase {
    /// `XCUIApplication` instance that can be used for all UI tests.
    @MainActor lazy open var app: XCUIApplication = {
        let app = XCUIApplication()
        app.launchArguments += ["ui-testing"]
        return app
    }()

    /// Waits the amount of time you specify for the element’s exists property to become true.
    public func waitForElementToAppear(_ element: XCUIElement, timeout: TimeInterval = 1.5 * UITestTimeout.appearMultiplier) {
        waitForCondition(element: element, predicate: NSPredicate(format: "exists == true"), timeout: timeout)
    }

    /// Waits the amount of time you specify for the element’s exists property to become false.
    public func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval = 6.5 * UITestTimeout.disappearMultiplier) {
        waitForCondition(element: element, predicate: NSPredicate(format: "exists == false"), timeout: timeout)
    }

    func waitForCondition(element: XCUIElement, predicate: NSPredicate, timeout: TimeInterval = 6.5 * UITestTimeout.appearMultiplier) {
        let conditionalExpectation = expectation(for: predicate, evaluatedWith: element, handler: nil)
        wait(for: [conditionalExpectation], timeout: timeout)
    }
}
