#if canImport(UIKit) && !os(watchOS)
import UIKit
import Combine

public extension UITextField {
    /// Publisher that will return the text contents of a `UITextField`.
    ///
    /// One notable change from the default delegate it is overriding. If the value of `text` is
    /// empty, we will return an empty string rather than nil.
    var textPublisher: AnyPublisher<String, Never> {
        publisher(for: .editingChanged)
            .map({ self.text })
            .replaceNil(with: "")
            .eraseToAnyPublisher()
    }
}
#endif
