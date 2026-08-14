#if canImport(AppKit)
import AppKit

extension NSGestureRecognizer {
    /// Convenience wrapper around the button mask values for a mouse button.
    public struct ButtonMask: OptionSet, Sendable {
        /// Left mouse button.
        public static let primary = ButtonMask(rawValue: 1 << 0)

        /// Right mouse button.
        public static let secondary = ButtonMask(rawValue: 1 << 1)

        /// Third mouse button.
        public static let other = ButtonMask(rawValue: 1 << 2)

        /// Create a new button mask from a raw integer value.
        ///
        /// - Parameter rawValue: The raw integer value to use for the button mask.
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// The underlying bitmask value of the button mask.
        public let rawValue: Int
    }
}

extension NSPanGestureRecognizer {
    /// The mouse buttons required to recognize the gesture.
    public var requiredButtons: ButtonMask {
        get { ButtonMask(rawValue: buttonMask) }
        set { buttonMask = newValue.rawValue }
    }
}

extension NSClickGestureRecognizer {
    /// The mouse buttons required to recognize the gesture.
    public var requiredButtons: ButtonMask {
        get { ButtonMask(rawValue: buttonMask) }
        set { buttonMask = newValue.rawValue }
    }
}

extension NSPressGestureRecognizer {
    /// The mouse buttons required to recognize the gesture.
    public var requiredButtons: ButtonMask {
        get { ButtonMask(rawValue: buttonMask) }
        set { buttonMask = newValue.rawValue }
    }
}
#endif
