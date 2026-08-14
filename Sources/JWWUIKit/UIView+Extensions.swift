#if canImport(UIKit) && !os(watchOS)
import UIKit

extension UIView {
    /// Boolean that returns true if the view is using Auto Layout. False otherwise.
    ///
    /// This is merely a convenience wrapper around `translatesAutoresizingMaskIntoConstraints` that inverts the
    /// logic.
    public var usesAutoLayout: Bool {
        get { return !translatesAutoresizingMaskIntoConstraints }
        set { translatesAutoresizingMaskIntoConstraints = !newValue }
    }
}
#endif
