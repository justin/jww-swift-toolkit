#if canImport(AppKit)
import Testing
import Cocoa
@testable import JWWAppKit

/// Tests to validate the gesture recognizer extensions.
@MainActor
struct NSGestureRecognizerExtensionsTests {
    @Test("Primary Button Bit Mask")
    func primaryButtonBitMask() {
        #expect(NSGestureRecognizer.ButtonMask.primary.rawValue == 1)
    }

    @Test("Secondary Button Bit Mask")
    func secondaryButtonBitMask() {
        #expect(NSGestureRecognizer.ButtonMask.secondary.rawValue == 2)
    }

    @Test("Other Button Bit Mask")
    func otherButtonBitMask() {
        #expect(NSGestureRecognizer.ButtonMask.other.rawValue == 4)
    }

    @Test("Setting required buttons")
    func requiredButtons_shouldReturnMultipleButtons() {
        let gestureRecognizer = NSPanGestureRecognizer()
        gestureRecognizer.requiredButtons = [.primary, .secondary]
        #expect(gestureRecognizer.requiredButtons == [.primary, .secondary])
    }
}
#endif
