import CoreData
import Foundation

/// A description of the physical persistent store and its context policy.
///
/// Core Data can expose implementation details such as `/dev/null` for an in-memory store, so a
/// file URL alone cannot express the store's capabilities or test-resource ownership. This type
/// keeps the physical store choice separate from the post-load query-generation policy, allowing
/// callers to distinguish lightweight in-memory work from SQLite-backed integration work before
/// loading a store. It does not allocate or clean up SQLite resources; callers retain ownership of
/// every SQLite URL they provide.
public struct PersistentStoreProfile: Sendable, Equatable {
    /// The physical persistent-store implementation.
    public enum Storage: Sendable, Equatable {
        /// A true Core Data in-memory store.
        case inMemory

        /// A SQLite store at an explicit, caller-owned location.
        case sqlite(URL)
    }

    /// The query-generation policy required after loading the store.
    public enum QueryGenerationPolicy: Sendable, Equatable {
        /// Do not pin a query generation.
        case disabled

        /// Pin the context to the current query generation after loading.
        case required
    }

    /// An invalid store-profile configuration.
    public enum ConfigurationError: Error, Sendable, Equatable {
        /// A true in-memory store cannot use the toolkit's SQLite query-generation policy.
        case requiredQueryGenerationNeedsSQLite
    }

    /// The physical store used by the profile.
    public let storage: Storage

    /// The policy to apply to a context after the store has loaded.
    public let queryGenerationPolicy: QueryGenerationPolicy

    /// The SQLite store URL, or `nil` when the profile uses true in-memory storage.
    public var storeURL: URL? {
        guard case let .sqlite(url) = storage else {
            return nil
        }

        return url
    }

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    /// Creates a persistent-store profile.
    ///
    /// - Parameters:
    ///   - storage: The physical store implementation.
    ///   - queryGenerationPolicy: The required post-load context policy.
    ///
    /// - Throws: ``ConfigurationError/requiredQueryGenerationNeedsSQLite`` when an in-memory store
    ///   is combined with the SQLite query-generation policy.
    public init(storage: Storage, queryGenerationPolicy: QueryGenerationPolicy) throws(ConfigurationError) {
        self.storage = storage
        self.queryGenerationPolicy = queryGenerationPolicy
        try validate()
    }

    // MARK: Public Methods
    // ====================================
    // Public Methods
    // ====================================

    /// Creates a persistent-store description that matches this profile.
    ///
    /// - Returns: A description configured for the selected physical store.
    /// - Throws: A configuration error if the profile is invalid.
    public func persistentStoreDescription() throws -> NSPersistentStoreDescription {
        try validate()

        switch storage {
        case .inMemory:
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            return description

        case let .sqlite(url):
            let description = NSPersistentStoreDescription(url: url)
            description.type = NSSQLiteStoreType
            return description
        }
    }

    /// Applies this profile's query-generation policy to a loaded context.
    ///
    /// Call this from the context's declared isolation domain after its stores load.
    ///
    /// - Parameter context: The loaded managed object context.
    /// - Throws: A configuration error if the profile is invalid, or the Core Data error from
    ///   applying the required generation.
    public func applyQueryGenerationPolicy(to context: NSManagedObjectContext) throws {
        try validate()

        guard queryGenerationPolicy == .required else {
            return
        }

        try context.setQueryGenerationFrom(.current)
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    private func validate() throws(ConfigurationError) {
        guard case .inMemory = storage,
              queryGenerationPolicy == .required else {
            return
        }

        throw ConfigurationError.requiredQueryGenerationNeedsSQLite
    }
}
