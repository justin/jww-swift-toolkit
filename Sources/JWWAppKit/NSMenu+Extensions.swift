import Foundation
import AppKit

extension NSMenu {
    ///  Finds a menu item by its identifier, including items in submenus.
    /// - Note: This method flattens the hierarchy of menu items, so it will search through all items and their submenus.
    /// - Parameter identifier: The identifier of the menu item to find.
    /// - Returns: The first menu item that matches the identifier, or `nil` if no matching item is found.
    public func item(withIdentifier identifier: NSUserInterfaceItemIdentifier) -> NSMenuItem? {
        // Flatten the hierarchy to search all items and their submenu items
        let allItems = items.flatMap { item -> [NSMenuItem] in
            // Start with the current item
            var result = [item]
            // Add all submenu items if available
            if let submenu = item.submenu {
                result.append(contentsOf: submenu.items)
            }
            return result
        }

        // Find the first item that matches the identifier
        return allItems.first { $0.identifier == identifier }
    }
}
