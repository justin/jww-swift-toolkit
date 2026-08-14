#if canImport(UIKit) && !os(watchOS)
import UIKit

/// Protocol that defines required attributes to load a view from a Xib file
public protocol XibInitializable {
    /// The name of the nib file that contains our view resource(s).
    static var nibName: String { get }

    /// The bundle that we should load our nib from.
    static var bundle: Bundle { get }
}

@MainActor
extension XibInitializable where Self: UIView {
    /// Load and return the primary view from a nib that matches the `XibInitializable` type.
    public func loadFromXib() -> UIView {
        let nib = UINib(nibName: Self.nibName, bundle: Self.bundle)
        guard let view = nib.instantiate(withOwner: self, options: nil).first as? UIView else {
            fatalError("Unable to load a matching view of type \(String(describing: self)) from xib.")
        }

        return view
    }
}
#endif
