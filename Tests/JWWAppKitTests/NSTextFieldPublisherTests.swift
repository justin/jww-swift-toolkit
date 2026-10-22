#if canImport(AppKit)
import Testing
import AppKit
import Combine
import JWWAppKit

/// Tests editing notifications, subscription lifetime, and field ownership.
@MainActor
struct NSTextFieldPublisherTests {
    @Test
    func testPublishingOnlyEditsFromTheObservedField() {
        let field = NSTextField()
        let otherField = NSTextField()
        var values: [String] = []
        let subscription = field.textPublisher.sink { values.append($0) }

        field.stringValue = "Programmatic"
        #expect(values.isEmpty)

        otherField.stringValue = "Other"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: otherField)
        #expect(values.isEmpty)

        field.stringValue = "Edited"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        field.stringValue = ""
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        #expect(values == ["Edited", ""])

        subscription.cancel()
        field.stringValue = "After cancellation"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        #expect(values == ["Edited", ""])
    }

    @Test
    func testPublisherAndSubscriptionDoNotRetainField() {
        var field: NSTextField? = NSTextField()
        let fieldWasReleased = { [weak field] in field == nil }
        let publisher = field?.textPublisher
        var values: [String] = []
        let subscription = publisher?.sink { values.append($0) }

        field = nil

        #expect(fieldWasReleased())
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: NSTextField())
        #expect(values.isEmpty)
        withExtendedLifetime((publisher, subscription)) {}
    }
}
#endif
