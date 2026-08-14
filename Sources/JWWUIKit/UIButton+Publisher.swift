#if canImport(UIKit) && !os(watchOS)
import UIKit
import Combine

public extension UIButton {
    /// Publisher that will return the text contents of a `UITextField`.
    var tapPublisher: EventPublisher {
        return publisher(for: .touchUpInside)
    }
}
#endif
