import CoreData
import Foundation
import JWWCoreData

/// Creates and loads the concrete persistent container exercised by a Core Data test store.
public protocol CoreDataTestContainerFactory {
    /// The concrete persistent-container type exercised by the test.
    associatedtype Container: NSPersistentContainer

    /// Creates the concrete container using the supplied physical-store profile.
    @MainActor
    static func makeContainer(for profile: PersistentStoreProfile) throws -> Container

    /// Loads the concrete container and applies its application-owned lifecycle policy.
    @MainActor
    static func load(_ container: Container) async throws
}

/// The physical store available to a Core Data test resource.
public enum CoreDataTestStoreStorage: Sendable {
    /// A true in-memory Core Data store for lightweight tests.
    case memory

    /// A temporary SQLite store for tests that need SQLite capabilities.
    case sqlite
}

/// The errors raised by ``CoreDataTestStore``.
///
/// These live outside the generic store so that every specialization shares one error type. A type
/// nested in a generic is distinct per specialization, which would otherwise stop a caller from
/// handling failures from two different factories with a single `catch`.
public enum CoreDataTestStoreError {
    /// An error containing both an operation failure and a cleanup failure.
    public struct OperationAndCleanup: Error {
        /// The error thrown by the scoped operation.
        public let operationError: any Error

        /// The error thrown while cleaning up the test resource.
        public let cleanupError: any Error
    }

    /// An error containing both a store-release failure and a resource-release failure.
    public struct StoreAndResource: Error {
        /// The error thrown while unloading the container's persistent stores.
        public let storeError: any Error

        /// The error thrown while deleting the owned temporary directory.
        public let resourceError: any Error
    }

    /// An error raised when cleanup would exceed the resource's owned directory.
    public enum Cleanup: Error, Equatable, Sendable {
        /// The temporary directory no longer has the expected owned shape.
        case invalidOwnedDirectory

        /// A loaded store does not belong to this test resource.
        case unexpectedPersistentStore
    }
}

/// A main-actor-isolated Core Data store with an explicit, scoped test-resource lifecycle.
///
/// A store is either truly in memory or backed by a SQLite file in a uniquely owned temporary
/// directory. The caller supplies a factory for the concrete container and loader, so
/// container-level tests can exercise their application's actual Core Data setup without allowing
/// managed objects or contexts to escape their isolation domain.
@MainActor
public final class CoreDataTestStore<Factory: CoreDataTestContainerFactory> {
    /// The concrete persistent-container type supplied by the factory.
    public typealias Container = Factory.Container

    /// The physical store available to a test resource.
    public typealias Storage = CoreDataTestStoreStorage

    /// An error containing both an operation failure and a cleanup failure.
    public typealias OperationAndCleanupError = CoreDataTestStoreError.OperationAndCleanup

    /// An error containing both a store-release failure and a resource-release failure.
    public typealias StoreAndResourceCleanupError = CoreDataTestStoreError.StoreAndResource

    /// An error raised when cleanup would exceed the resource's owned directory.
    public typealias CleanupError = CoreDataTestStoreError.Cleanup

    /// The loaded client-supplied container.
    public let container: Container

    /// The profile configured for the container.
    public let profile: PersistentStoreProfile

    /// The SQLite store URL, or `nil` for a true in-memory store.
    public let storeURL: URL?

    private let resource: Resource
    private var isCleanedUp = false

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    /// Allocates an isolated test resource, creates a typed container, and loads it through the factory.
    ///
    /// - Parameter storage: The physical store needed by the test.
    public init(storage: Storage = .memory) async throws {
        let resource = try Resource(storage: storage)
        self.resource = resource
        profile = resource.profile
        storeURL = resource.storeURL

        do {
            container = try Factory.makeContainer(for: resource.profile)
        } catch {
            try? resource.cleanup()
            throw error
        }

        do {
            try await Factory.load(container)
            try resource.profile.applyQueryGenerationPolicy(to: container.viewContext)
        } catch {
            try? cleanup()
            throw error
        }
    }

    isolated deinit {
        try? cleanup()
    }

    // MARK: Public Methods
    // ====================================
    // Public Methods
    // ====================================

    /// Removes loaded stores and deletes only the temporary directory this instance created.
    ///
    /// The owned directory is always released, even when a store fails to unload, so a failure
    /// leaves nothing behind on disk. Calling this method again after a failure retries the
    /// release; once it succeeds, further calls have no effect.
    public func cleanup() throws {
        guard !isCleanedUp else {
            return
        }

        let storeError = releaseOwnedStores()

        let resourceError: (any Error)?
        do {
            try resource.cleanup()
            resourceError = nil
        } catch {
            resourceError = error
        }

        if let storeError, let resourceError {
            throw StoreAndResourceCleanupError(storeError: storeError, resourceError: resourceError)
        }

        if let error = storeError ?? resourceError {
            throw error
        }

        isCleanedUp = true
    }

    /// Runs an operation against a typed test container and always attempts explicit cleanup.
    ///
    /// If both the operation and cleanup fail, the thrown error preserves both failures.
    public static func withStore<Output: Sendable>(
        storage: Storage = .memory,
        operation: @MainActor @Sendable (Container) async throws -> Output
    ) async throws -> Output {
        let store = try await CoreDataTestStore(storage: storage)

        let operationResult: Result<Output, any Error>
        do {
            operationResult = .success(try await operation(store.container))
        } catch {
            operationResult = .failure(error)
        }

        do {
            try store.cleanup()
        } catch {
            if case let .failure(operationError) = operationResult {
                throw OperationAndCleanupError(
                    operationError: operationError,
                    cleanupError: error
                )
            }

            throw error
        }

        return try operationResult.get()
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    /// Removes and destroys every store this resource owns.
    ///
    /// Every store is attempted, so one unremovable store cannot strand the others.
    ///
    /// - Returns: The first failure encountered, or `nil` when every store was released.
    private func releaseOwnedStores() -> (any Error)? {
        var firstError: (any Error)?

        for persistentStore in container.persistentStoreCoordinator.persistentStores {
            do {
                try validate(persistentStore)
                try container.persistentStoreCoordinator.remove(persistentStore)

                guard let storeURL else {
                    continue
                }

                try container.persistentStoreCoordinator.destroyPersistentStore(
                    at: storeURL,
                    ofType: NSSQLiteStoreType,
                    options: persistentStore.options
                )
            } catch {
                firstError = firstError ?? error
            }
        }

        return firstError
    }

    private func validate(_ persistentStore: NSPersistentStore) throws {
        switch resource.storage {
        case .memory:
            // Core Data reports `/dev/null` for a loaded in-memory store, so the store type is the
            // only reliable signal that it holds no file the resource would need to delete.
            guard persistentStore.type == NSInMemoryStoreType else {
                throw CleanupError.unexpectedPersistentStore
            }

        case .sqlite:
            guard persistentStore.type == NSSQLiteStoreType,
                  persistentStore.url == storeURL else {
                throw CleanupError.unexpectedPersistentStore
            }
        }
    }
}

// MARK: Test Resource
// ====================================
// Test Resource
// ====================================
private extension CoreDataTestStore {
    struct Resource {
        let storage: Storage
        let profile: PersistentStoreProfile
        let storeURL: URL?
        let directoryURL: URL?
        let rootDirectoryURL: URL?

        init(storage: Storage) throws {
            self.storage = storage

            switch storage {
            case .memory:
                profile = try PersistentStoreProfile(
                    storage: .inMemory,
                    queryGenerationPolicy: .disabled
                )
                storeURL = nil
                directoryURL = nil
                rootDirectoryURL = nil

            case .sqlite:
                let rootDirectoryURL = FileManager.default.temporaryDirectory
                    .resolvingSymlinksInPath()
                    .appendingPathComponent("JWWCoreDataTestSupport", isDirectory: true)
                let directoryURL = rootDirectoryURL
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let storeURL = directoryURL.appendingPathComponent("Store.sqlite")

                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )

                self.profile = try PersistentStoreProfile(
                    storage: .sqlite(storeURL),
                    queryGenerationPolicy: .required
                )
                self.storeURL = storeURL
                self.directoryURL = directoryURL
                self.rootDirectoryURL = rootDirectoryURL
            }
        }

        func cleanup() throws {
            guard let directoryURL else {
                return
            }

            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: directoryURL.path) else {
                return
            }

            guard isValidOwnedDirectory(directoryURL) else {
                throw CleanupError.invalidOwnedDirectory
            }

            try fileManager.removeItem(at: directoryURL)
        }

        private func isValidOwnedDirectory(_ directoryURL: URL) -> Bool {
            guard let rootDirectoryURL,
                  directoryURL.deletingLastPathComponent() == rootDirectoryURL,
                  UUID(uuidString: directoryURL.lastPathComponent) != nil,
                  directoryURL.resolvingSymlinksInPath() == directoryURL,
                  rootDirectoryURL.resolvingSymlinksInPath() == rootDirectoryURL,
                  let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                return false
            }

            return true
        }
    }
}
