#if canImport(UIKit) && !os(watchOS)
import UIKit

public extension UITableView {
    /// Registers a nib object containing a cell that conforms to `ReuseIdentifiableNib` with the table view
    func registerReusableNib<T: ReuseIdentifiableNib>(_ cellClass: T.Type) {
        register(cellClass.nib, forCellReuseIdentifier: cellClass.reuseIdentifier)
    }

    /// Returns a reusable table view cell that conforms to `ReuseIdentifiableCell` and adds it to the table.
    func dequeueReusableCell<T: ReuseIdentifiableCell>(_ cellClass: T.Type, forIndexPath indexPath: IndexPath) -> T {
        guard let cell = dequeueReusableCell(withIdentifier: cellClass.reuseIdentifier,
                                             for: indexPath) as? T else {
            fatalError("Misconfigured cell type, \(cellClass)!")
        }

        return cell
    }
}
#endif
