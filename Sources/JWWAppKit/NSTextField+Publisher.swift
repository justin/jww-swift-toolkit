#if canImport(AppKit)
import AppKit
import Combine

public extension NSTextField {
    /// Publishes the field's string value when AppKit posts an editing-change notification for it.
    /// Does not emit an initial value or observe programmatic assignments to `stringValue`.
    /// Subscribe and edit the field on the main actor. The publisher does not retain the field.
    var textPublisher: AnyPublisher<String, Never> {
        NotificationCenter.default.publisher(for: NSControl.textDidChangeNotification)
            .compactMap { [weak self] notification in
                guard let self, notification.object as? NSTextField === self else {
                    return nil
                }

                return self.stringValue
            }
            .eraseToAnyPublisher()
    }
}
#endif
