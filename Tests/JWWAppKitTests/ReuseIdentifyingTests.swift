#if canImport(AppKit)
import Testing
import AppKit
import JWWAppKit

/// Tests typed reuse with AppKit registration and the table view's creation contract.
@MainActor
struct ReuseIdentifyingTests {
    @Test
    func testCreatingRegisteredCollectionViewItem() {
        let collectionView = NSCollectionView()
        let dataSource = TestCollectionDataSource()
        collectionView.dataSource = dataSource
        collectionView.collectionViewLayout = NSCollectionViewFlowLayout()
        collectionView.registerReusableClass(TestCollectionItem.self)
        collectionView.reloadData()

        let item = collectionView.makeReusableItem(TestCollectionItem.self, for: IndexPath(item: 0, section: 0))

        #expect(item.identifier == TestCollectionItem.reuseIdentifier)
        withExtendedLifetime(dataSource) {}
    }

    @Test
    func testTableViewPassesIdentifierAndOwnerAndReturnsTypedView() {
        let tableView = TestTableView()
        let owner = NSObject()
        let cell = TestTableCell()
        tableView.createdView = cell

        let result = tableView.makeReusableView(TestTableCell.self, owner: owner)

        #expect(result === cell)
        #expect(tableView.requestedIdentifier == TestTableCell.reuseIdentifier)
        #expect(tableView.requestedOwner === owner)
    }

    @Test
    func testTableViewReturnsNilForUnregisteredView() {
        let tableView = NSTableView()

        #expect(tableView.makeReusableView(TestTableCell.self, owner: nil) == nil)
    }
}

/// Supplies a valid index path for native collection view item creation.
private final class TestCollectionDataSource: NSObject, NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        return collectionView.makeReusableItem(TestCollectionItem.self, for: indexPath)
    }
}

/// A programmatic collection view item with an explicit reuse identifier.
private final class TestCollectionItem: NSCollectionViewItem, ReuseIdentifiable {
    static var reuseIdentifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("CollectionItem") }

    override func loadView() {
        view = NSView()
    }
}

/// A table cell whose identifier can be used independently of a nib.
private final class TestTableCell: NSTableCellView, ReuseIdentifiable {
    static var reuseIdentifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier("TableCell") }
}

/// Records the native creation request, including the nib owner.
private final class TestTableView: NSTableView {
    var createdView: NSView?
    var requestedIdentifier: NSUserInterfaceItemIdentifier?
    weak var requestedOwner: AnyObject?

    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        requestedIdentifier = identifier
        requestedOwner = owner as AnyObject?
        return createdView
    }
}
#endif
