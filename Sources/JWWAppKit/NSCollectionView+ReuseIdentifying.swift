#if canImport(AppKit)
import AppKit

public extension NSCollectionView {
    /// Registers a collection view item class using its reuse identifier.
    func registerReusableClass<T: NSCollectionViewItem & ReuseIdentifiable>(_ itemClass: T.Type) {
        register(itemClass, forItemWithIdentifier: itemClass.reuseIdentifier)
    }

    /// Registers a collection view item's nib using its reuse identifier.
    func registerReusableNib<T: NSCollectionViewItem & ReuseIdentifiableNib>(_ itemClass: T.Type) {
        register(itemClass.nib, forItemWithIdentifier: itemClass.reuseIdentifier)
    }

    /// Creates or reuses an item with the specified type and reuse identifier.
    /// A registration that produces a different type is a programming error.
    func makeReusableItem<T: NSCollectionViewItem & ReuseIdentifiable>(_ itemClass: T.Type, for indexPath: IndexPath) -> T {
        guard let item = makeItem(withIdentifier: itemClass.reuseIdentifier, for: indexPath) as? T else {
            fatalError("Misconfigured collection view item type, \(itemClass)!")
        }

        return item
    }
}
#endif
