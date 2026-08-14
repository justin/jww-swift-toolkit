#if canImport(UIKit) && !os(watchOS)
import UIKit
import Combine

public extension UIControl {
    /// Publisher that emits a response when a control responds to an event.
    func publisher(for event: Event) -> EventPublisher {
        EventPublisher(control: self, event: event)
    }

    @MainActor
    struct EventPublisher: @MainActor Publisher {
        // swiftlint:disable nesting
        public typealias Output = Void
        public typealias Failure = Never
        // swiftlint:enable nesting

        fileprivate var control: UIControl
        fileprivate var event: Event

        public func receive<S: Subscriber>(subscriber: S) where Self.Failure == S.Failure, Self.Output == S.Input {
            let subscription = EventSubscription<S>(target: subscriber)
            subscriber.receive(subscription: subscription)
            control.addTarget(subscription, action: #selector(subscription.trigger), for: event)
        }
    }

    @MainActor
    private final class EventSubscription<Target: Subscriber>: @MainActor Subscription where Target.Input == Void {
        private var target: Target?

        init(target: Target) {
            self.target = target
        }

        func request(_ demand: Subscribers.Demand) {
            // No-op
        }

        func cancel() {
            target = nil
        }

        @objc
        func trigger() {
            // Whenever an event was triggered by the underlying
            // UIControl instance, we'll simply pass Void to our
            // target to emit that event:
            _ = target?.receive(())
        }

    }
}
#endif
