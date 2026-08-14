#if canImport(UIKit) && !os(watchOS)
import UIKit

/// Protocol that defines the components needed for a reusable cell.
public protocol ReuseIdentifiableCell {
    /// Default reuse identifier for the reusable cell.
    static var reuseIdentifier: String { get }
}

/// Protocol that defines the components needed for a reusable cell.
public protocol ReuseIdentifiableNib: ReuseIdentifiableCell {
    /// Nib object to load when generating the cell.
    static var nib: UINib { get }
}
#endif
