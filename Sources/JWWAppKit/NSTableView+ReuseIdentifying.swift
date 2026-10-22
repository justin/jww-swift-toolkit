#if canImport(AppKit)
import AppKit

public extension NSTableView {
    /// Registers a reusable view's nib using its reuse identifier.
    func registerReusableNib<T: NSView & ReuseIdentifiableNib>(_ viewClass: T.Type) {
        register(viewClass.nib, forIdentifier: viewClass.reuseIdentifier)
    }

    /// Creates or reuses a view with the specified type and reuse identifier, passing the owner to nib loading.
    /// Returns nil when AppKit cannot create or reuse a view. A mismatched view type is a programming error.
    func makeReusableView<T: NSView & ReuseIdentifiable>(_ viewClass: T.Type, owner: Any?) -> T? {
        guard let view = makeView(withIdentifier: viewClass.reuseIdentifier, owner: owner) else {
            return nil
        }

        guard let typedView = view as? T else {
            fatalError("Misconfigured table view type, \(viewClass)!")
        }

        return typedView
    }
}
#endif
