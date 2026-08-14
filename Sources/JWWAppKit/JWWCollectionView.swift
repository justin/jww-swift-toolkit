#if canImport(AppKit)
import AppKit

/// Typealias for closure that generates the custom context menu.
public typealias JWWContextMenuActionProvider = ([NSMenuItem]) -> NSMenu?

/// An object containing the configuration details for the contextual menu.
@MainActor
public class JWWContextMenuConfiguration: NSObject {
    /// The unique identifier for this configuration object.
    public let identifier: NSUserInterfaceItemIdentifier

    /// A block that provides a contextual menu to display.
    public let actionProvider: JWWContextMenuActionProvider

    /// Creates a menu configuration object with the specified action provider.
    ///
    /// - Parameters:
    ///   - identifier: The unique identifier for this configuration object.
    ///   - actionProvider: A block that provides a contextual menu to display.
    public init(identifier: NSUserInterfaceItemIdentifier, actionProvider: @escaping JWWContextMenuActionProvider) {
        self.identifier = identifier
        self.actionProvider = actionProvider
        super.init()
    }
}

/// Subclass of NSCollectionViewDelegate that adds additional methods for AppKit.
public protocol JWWCollectionViewDelegate: NSCollectionViewDelegate {
    /// Asks the delegate for a context-menu configuration for the items at the specified index path.
    ///
    /// - Parameters:
    ///   - collectionView: The collection view containing the items.
    ///   - indexPath: The index path corresponding to the item the menu acts on.
    ///   - point: The location of the interaction in the collection view’s coordinate space.
    /// - Returns: A contextual menu configuration object describing the menu to present. Returning nil prevents the interaction from beginning
    @MainActor
    func collectionView(_ collectionView: NSCollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> JWWContextMenuConfiguration?
}

/// Customized NSCollectionView with built-in support for displaying a right-click menu.
open class JWWCollectionView: NSCollectionView {
    // MARK: Menu Handling
    // ====================================
    // Menu Handling
    // ====================================

    open override func menu(for event: NSEvent) -> NSMenu? {
        // If we already set up the menu, just bail.
        guard menu == nil else {
            return menu
        }

        guard let delegate = delegate as? JWWCollectionViewDelegate else {
            return super.menu(for: event)
        }
        let point = convert(event.locationInWindow, from: nil)

        guard let indexPath = indexPathForItem(at: point) else {
            return super.menu(for: event)
        }

        guard let menuConfiguration = delegate.collectionView(self, contextMenuConfigurationForItemAt: indexPath, point: point) else {
            return super.menu(for: event)
        }

        // Start with any existing menu items from the default menu (if any)
        let defaultMenuItems: [NSMenuItem] = super.menu(for: event)?.items ?? []

        guard let producedMenu = menuConfiguration.actionProvider(defaultMenuItems) else {
            return super.menu(for: event)
        }

        defer { self.menu = producedMenu }
        return producedMenu
    }
}
#endif
