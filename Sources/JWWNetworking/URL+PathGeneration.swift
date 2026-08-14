import Foundation

public typealias Path = URL.Path

/// Protocol that defines the values that can be extracted from a path component.
public protocol PathComponent {
    /// A string representation of a path component. This omits the leading "/" separator.
    var stringValue: String { get }

    /// A valid path value that can be passed into `URLComponents`.
    var pathValue: String { get }
}

public extension URL {
    /// An object that supports building the path piece of a URL from an array of different components.
    struct Path: Equatable {
        /// The separator between each path component.
        fileprivate static let separator = "/"

        /// Array of components that a part of the generated path.
        private let components: [PathComponent]

        /// Create and return a new `Path` object.
        ///
        /// - Parameter path: Array of path components.
        public init(_ path: PathComponent...) {
            self.init(path)
        }

        /// Create and return a new `Path` object.
        ///
        /// - Parameter path: Array of path components.
        public init(_ path: [PathComponent]) {
            let adjusted: [PathComponent] = path.map({ component in
                guard component.stringValue.hasPrefix(Path.separator) else {
                    return component
                }

                return String(component.stringValue.dropFirst())
            })

            self.components = adjusted
        }

        /// Append an additional component to an existing path.
        ///
        /// - Parameter path: The path component to append.
        public func appending(_ path: PathComponent...) -> Path {
            Path(self.components + path)
        }

        public static func + (lhs: Path, rhs: Path) -> Path {
            Path(lhs.components + rhs.components)
        }

        public static func == (lhs: URL.Path, rhs: URL.Path) -> Bool {
            lhs.pathValue == rhs.pathValue
        }
    }
}

// MARK: Collection + Sequence Conformance
// ========================================
// Collection + Sequence Conformance
// ========================================
extension Path: Collection {
    public typealias Element = PathComponent
    public typealias Iterator = AnyIterator<Element>

    public func makeIterator() -> Iterator {
        var iterator = components.makeIterator()

        return AnyIterator {
            return iterator.next()
        }
    }

    public var startIndex: Int {
        components.startIndex
    }

    public var endIndex: Int {
        components.endIndex
    }

    public subscript(position: Int) -> Element {
        components[position]
    }

    // swiftlint:disable:next identifier_name
    public func index(after i: Int) -> Int {
        components.index(after: i)
    }
}

// MARK: PathComponent Conformances
// ====================================
// PathComponent Conformances
// ====================================
extension Path: PathComponent {
    public var stringValue: String {
        components
            .map(\.stringValue)
            .joined(separator: Path.separator)
    }

    public var pathValue: String {
        components
            .map(\.pathValue)
            .joined()
    }
}

extension String: PathComponent {
    public var stringValue: String {
        return self
    }
}

extension Int: PathComponent {
    public var stringValue: String {
        String(describing: self)
    }
}

extension PathComponent {
    public var pathValue: String {
        let pathValue: String
        switch stringValue {
        case _ where stringValue.isEmpty:
            pathValue = ""
        default:
            pathValue = Path.separator + stringValue
        }

        return pathValue
    }
}
