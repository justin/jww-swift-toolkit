#if canImport(AppKit)
import AppKit

/// A view controller that can be loaded from a Storyboard.
@MainActor
public protocol StoryboardInitializable {
    /// The unique identifier for fetching the view controller from a storyboard.
    /// This is analogous to the "Storyboard ID" value in Interface Builder.
    static var identifier: String { get }

    /// Instantiate a new instance of the view controller.
    static func instantiateFromStoryboard(_ storyboard: NSStoryboard) -> Self
}

// MARK: Default Implementations
// ====================================
// Default Implementations
// ====================================
public extension StoryboardInitializable {
    static var identifier: String {
        return String(describing: self)
    }
}

public extension StoryboardInitializable where Self: NSViewController {
    static func instantiateFromStoryboard(_ storyboard: NSStoryboard) -> Self {
        return storyboard.instantiateController(identifier: Self.identifier) { coder in
            Self(coder: coder)
        }
    }
}

public extension StoryboardInitializable where Self: NSWindowController {
    static func instantiateFromStoryboard(_ storyboard: NSStoryboard) -> Self {
        return storyboard.instantiateController(identifier: Self.identifier) { coder in
            Self(coder: coder)
        }
    }
}
#endif
