#if canImport(AppKit)
import Testing
import AppKit
import JWWAppKit

/// Tests controller and view hierarchy changes without imposing a layout policy.
@MainActor
struct NSViewControllerContainmentTests {
    @Test
    func testAddingChildPreservesLayout() {
        let parent = NSViewController()
        parent.view = NSView()
        let child = NSViewController()
        child.view = NSView(frame: NSRect(x: 10, y: 20, width: 100, height: 80))
        child.view.autoresizingMask = [.width, .height]
        let originalFrame = child.view.frame

        parent.add(child)

        #expect(child.parent === parent)
        #expect(parent.children.contains { $0 === child })
        #expect(child.view.superview === parent.view)
        #expect(child.view.frame == originalFrame)
        #expect(child.view.autoresizingMask == [.width, .height])
        #expect(child.view.translatesAutoresizingMaskIntoConstraints)
    }

    @Test
    func testAddingChildToContainerAndRemovingIt() {
        let parent = NSViewController()
        parent.view = NSView()
        let container = NSView()
        parent.view.addSubview(container)
        let child = NSViewController()
        child.view = NSView()
        child.view.translatesAutoresizingMaskIntoConstraints = false

        parent.add(child, superview: container)

        #expect(child.parent === parent)
        #expect(child.view.superview === container)
        #expect(!child.view.translatesAutoresizingMaskIntoConstraints)

        child.remove()

        #expect(child.parent == nil)
        #expect(parent.children.isEmpty)
        #expect(child.view.superview == nil)
        #expect(container.superview === parent.view)
    }
}
#endif
