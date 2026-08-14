#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A view controller that can be loaded from a Storyboard.
public protocol StoryboardInitializable where Self: UIViewController {
    /// The unique identifier for fetching the view controller from a storyboard.
    /// This is analogous to the "Storyboard ID" value in Interface Builder.
    static var identifier: String { get }

    /// Instantiate a new instance of the view controller.
    static func instantiateFromStoryboard(_ storyboard: UIStoryboard) -> Self
}

// MARK: Default Implementations
// ====================================
// Default Implementations
// ====================================
public extension StoryboardInitializable {
    static var identifier: String {
        return String(describing: self)
    }

    static func instantiateFromStoryboard(_ storyboard: UIStoryboard) -> Self {
        // swiftlint:disable:next force_cast
        return storyboard.instantiateViewController(withIdentifier: identifier) as! Self
    }
}
#endif
