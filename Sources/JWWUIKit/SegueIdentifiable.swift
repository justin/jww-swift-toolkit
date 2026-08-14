#if canImport(UIKit) && !os(watchOS)
import UIKit

/// Protocol that declares that a view controller supports storyboard segues.
public protocol SegueIdentifiable {
    /// A type that provides the segue identification information.
    associatedtype SegueIdentifier: RawRepresentable
}

@MainActor
public extension SegueIdentifiable where Self: UIViewController, SegueIdentifier.RawValue == String {
    /// Type-safe alternative to `performSegue(withIdentifier:sender:)`.
    func performSegue(withIdentifier identifier: SegueIdentifier, sender: Any?) {
        performSegue(withIdentifier: identifier.rawValue, sender: sender)
    }

    /// Attempt to return a `SegueIdentifier` based off the passed in segue's `identifier` value.
    /// - Parameter segue: The storyboard segue to attempt to match to a `SegueIdentifier`.
    func segueIdentifier(for segue: UIStoryboardSegue) -> SegueIdentifier? {
        guard let identifier = segue.identifier else {
            return nil
        }

        return SegueIdentifier(rawValue: identifier)
    }
}
#endif
