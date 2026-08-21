#if canImport(AppKit)
import AppKit

extension NSView {
    @MainActor
    @propertyWrapper
    public struct JWWViewLoading<Value> {
        private var storedValue: Value?

        /// Undocumented but widespread subscript method for accessing the wrapped object. This
        /// technique is alluded to in the original property wrappers Swift Evolution proposal,
        /// and has remained consistently available. Since the technique informs static generation
        /// of property wrapper "sugar", I think it's safe to rely upon it even for shipping code.
        /// https://github.com/apple/swift-evolution/blob/main/proposals/0258-property-wrappers.md#referencing-the-enclosing-self-in-a-wrapper-type
        public static subscript<T: NSView>(_enclosingInstance instance: T,
            wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
            storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
        ) -> Value {
            get {
                instance[keyPath: storageKeyPath].storedValue!
            }
            set {
                instance[keyPath: storageKeyPath].storedValue = newValue
            }
        }

        // MARK: Initialization
        // ====================================
        // Initialization
        // ====================================

        public init() {
            self.storedValue = nil
        }

        public init(value: Value) {
            self.storedValue = value
        }

        /// Compatibility guard against attempted use on non-reference types
        @available(*, unavailable,
                    message: "This property wrapper is only available on classes because it accesses its container using reference semantics"
        )
        public var wrappedValue: Value {
            fatalError("Unsupported")
        }
    }
}
#endif
