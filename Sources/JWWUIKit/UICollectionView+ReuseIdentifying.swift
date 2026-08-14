#if canImport(UIKit) && !os(watchOS)
import UIKit

public extension UICollectionView {
    /// Registers a nib object containing a cell that conforms to `ReuseIdentifiableNib` with the collection view
    func registerReusableNib<T: ReuseIdentifiableNib>(_ cellClass: T.Type) {
        register(cellClass.nib, forCellWithReuseIdentifier: cellClass.reuseIdentifier)
    }

    /// Returns a reusable table view cell that conforms to `ReuseIdentifiableCell` and adds it to the table.
    func dequeueReusable<T: ReuseIdentifiableCell>(_ cellClass: T.Type, forIndexPath indexPath: IndexPath) -> T {
        guard let cell = dequeueReusableCell(withReuseIdentifier: cellClass.reuseIdentifier,
                                             for: indexPath) as? T else {
            fatalError("Misconfigured cell type, \(cellClass)!")
        }

        return cell
    }
}
#endif
