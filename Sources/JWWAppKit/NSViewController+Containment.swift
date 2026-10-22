#if canImport(AppKit)
import AppKit

public extension NSViewController {
    /// Adds a child controller and inserts its view into this controller's view.
    /// The caller is responsible for the child's frame, autoresizing mask, and constraints.
    func add(_ child: NSViewController) {
        add(child, superview: view)
    }

    /// Adds a child controller and inserts its view into the specified superview.
    /// The caller is responsible for the child's frame, autoresizing mask, and constraints.
    func add(_ child: NSViewController, superview: NSView) {
        addChild(child)
        superview.addSubview(child.view)
    }

    /// Removes this controller's view from its superview and removes the controller from its parent.
    func remove() {
        assert(parent != nil, "Attempting to remove a view controller from a parent-child hierarchy that doesn't exist.")
        view.removeFromSuperview()
        removeFromParent()
    }
}
#endif
