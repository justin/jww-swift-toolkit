#if canImport(UIKit) && !os(watchOS)
import UIKit

public extension UIViewController {
    /// Add the passed in `child` view controller to the current parent view controller.
    func add(_ child: UIViewController) {
        add(child, superview: view)
    }

    /// Add the passed in `child` view controller to the current parent view controller
    /// and affix it to the `superview.`.
    func add(_ child: UIViewController, at index: Int? = nil) {
        guard let index = index else {
            return add(child, superview: view)
        }

        addChild(child)
        view.insertSubview(child.view, at: index)
        child.didMove(toParent: self)
    }

    /// Add the passed in `child` view controller to the current parent view controller
    /// and affix it to the `superview.`.
    func add(_ child: UIViewController, superview: UIView) {
        addChild(child)
        superview.addSubview(child.view)
        child.didMove(toParent: self)
    }

    /// Remove the passed in `child` view controller from its parent.
    func remove(_ child: UIViewController?) {
        child?.remove()
    }

    /// Remove a view controller from its `parent` view controller.
    func remove() {
        assert(parent != nil, "Attempting to remove a view controller from a parent-child hierarchy that doesn't exist.")
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }
}
#endif
