#if canImport(AppKit)
import AppKit

/// A reusable AppKit view or collection view item with a known identifier.
@MainActor
public protocol ReuseIdentifiable {
    /// The identifier used to register and retrieve this type.
    static var reuseIdentifier: NSUserInterfaceItemIdentifier { get }
}

/// A reusable AppKit view or collection view item loaded from a nib.
@MainActor
public protocol ReuseIdentifiableNib: ReuseIdentifiable {
    /// The nib containing the reusable view or collection view item.
    static var nib: NSNib { get }
}
#endif
