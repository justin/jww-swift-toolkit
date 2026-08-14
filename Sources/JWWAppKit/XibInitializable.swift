#if canImport(AppKit)
import AppKit

/// Protocol that defines required attributes to load a view from a Xib file
@MainActor
public protocol XibInitializable {
    /// The main view in the xib.
    var contentView: NSView { get }

    /// The name of the nib file that contains our view resource(s).
    static var nibName: String { get }

    /// The bundle that we should load our nib from.
    static var bundle: Bundle { get }
}

extension XibInitializable where Self: NSView {
    public static var nibName: String {
        String(describing: self)
    }

    public static var bundle: Bundle {
        Bundle(for: self)
    }

    /// Load and return the primary view from a nib that matches the `XibInitializable` type.
    @MainActor
    public func loadFromXib() {
        let bundle = Self.bundle
        let nib = NSNib(nibNamed: Self.nibName, bundle: bundle)!
        _ = nib.instantiate(withOwner: self, topLevelObjects: nil)

        let contentConstraints = contentView.constraints
        contentView.subviews.forEach({ addSubview($0) })

        for constraint in contentConstraints {
            let firstItem = (constraint.firstItem as? NSView == contentView) ? self : constraint.firstItem
            let secondItem = (constraint.secondItem as? NSView == contentView) ? self : constraint.secondItem
            addConstraint(NSLayoutConstraint(item: firstItem as Any,
                                             attribute: constraint.firstAttribute,
                                             relatedBy: constraint.relation,
                                             toItem: secondItem,
                                             attribute: constraint.secondAttribute,
                                             multiplier: constraint.multiplier,
                                             constant: constraint.constant))
        }
    }
}
#endif
