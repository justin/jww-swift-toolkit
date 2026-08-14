#if canImport(AppKit)
import Testing
import Cocoa
@testable import JWWAppKit

@MainActor
struct NSViewExtensionTests {
    /// Validate we can set `usesAutoLayout` to true and it sets the underlying propery to the expected value.
    @Test
    func testEnablingAutoLayoutOnView() {
        let view = NSView()
        view.usesAutoLayout = true

        #expect(view.translatesAutoresizingMaskIntoConstraints == false)
    }

    /// Validate we can set `usesAutoLayout` to false and it sets the underlying propery to the expected value.
    @Test
    func testDisablingAutoLayoutOnView() {
        let view = NSView()
        view.usesAutoLayout = false

        #expect(view.translatesAutoresizingMaskIntoConstraints == true)
    }
}
#endif
