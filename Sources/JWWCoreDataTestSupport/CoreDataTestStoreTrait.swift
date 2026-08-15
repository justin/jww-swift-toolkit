import CoreData
import JWWCoreData
import Testing

/// Supplies a Core Data model to ``CoreDataTestStoreTrait``.
public protocol CoreDataTestModelProvider: Sendable {
    /// The persistent-container name.
    static var containerName: String { get }

    /// Creates the managed-object model for a test store.
    @MainActor
    static func makeManagedObjectModel() -> NSManagedObjectModel
}

/// Main-actor access to a Core Data test store supplied by a testing trait.
@MainActor
public final class CoreDataTestDatabase {
    private let storedStoreURL: URL?
    private let context: NSManagedObjectContext
    private let cleanupStore: @MainActor () throws -> Void

    fileprivate init<Model: CoreDataTestModelProvider>(
        model: Model.Type,
        storage: CoreDataTestStoreStorage
    ) async throws {
        let store = try await CoreDataTestStore<ModelContainerFactory<Model>>(storage: storage)
        storedStoreURL = store.storeURL

        let context = store.container.newBackgroundContext()
        let profile = store.profile
        try await context.perform {
            try profile.applyQueryGenerationPolicy(to: context)
        }

        self.context = context
        cleanupStore = {
            try store.cleanup()
        }
    }

    /// The SQLite file URL, or `nil` for an in-memory store.
    public var storeURL: URL? {
        storedStoreURL
    }

    /// Performs work on the trait's private managed-object context.
    ///
    /// The operation and result are sendable, so managed objects and contexts cannot escape their
    /// Core Data queue.
    public func perform<Value: Sendable>(
        _ operation: @escaping @Sendable (NSManagedObjectContext) throws -> Value
    ) async throws -> Value {
        let context = context
        return try await context.perform {
            try operation(context)
        }
    }

    fileprivate func cleanup() throws {
        try cleanupStore()
    }
}

/// Access to dependencies installed by ``CoreDataTestStoreTrait``.
public enum CoreDataTestContext {
    /// An error raised when a test accesses a dependency outside its trait.
    public enum AccessError: Error, Sendable {
        /// No Core Data test-store trait applies to the current test.
        case databaseTraitRequired
    }

    /// The database installed for the current test.
    @MainActor public static var database: CoreDataTestDatabase {
        get throws {
            guard let database = CoreDataTestEnvironment.database else {
                throw AccessError.databaseTraitRequired
            }

            return database
        }
    }
}

/// A Swift Testing trait that provides one isolated Core Data store to each test case.
public struct CoreDataTestStoreTrait<Model: CoreDataTestModelProvider>: SuiteTrait, TestTrait, TestScoping, Sendable {
    /// Apply the trait separately to every test in a suite, including nested suites.
    public let isRecursive = true

    private let storage: CoreDataTestStoreStorage

    /// Creates a Core Data store trait.
    ///
    /// - Parameters:
    ///   - model: The model provider used to create each store.
    ///   - storage: The physical store profile needed by each test.
    public init(
        _ model: Model.Type,
        storage: CoreDataTestStoreStorage = .memory
    ) {
        self.storage = storage
    }

    /// Creates the store, runs the test in its scope, and cleans up the store.
    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let database = try await CoreDataTestDatabase(model: Model.self, storage: storage)

        try await CoreDataTestEnvironment.$database.withValue(database) {
            let operationResult: Result<Void, any Error>
            do {
                operationResult = .success(try await function())
            } catch {
                operationResult = .failure(error)
            }

            do {
                try await database.cleanup()
            } catch {
                if case let .failure(operationError) = operationResult {
                    throw CoreDataTestStoreError.OperationAndCleanup(
                        operationError: operationError,
                        cleanupError: error
                    )
                }

                throw error
            }

            try operationResult.get()
        }
    }
}

public extension Trait {
    /// Provides an isolated Core Data store to a test or suite.
    static func coreDataStore<Model: CoreDataTestModelProvider>(
        _ model: Model.Type,
        storage: CoreDataTestStoreStorage = .memory
    ) -> CoreDataTestStoreTrait<Model> where Self == CoreDataTestStoreTrait<Model> {
        CoreDataTestStoreTrait(model, storage: storage)
    }
}

private enum CoreDataTestEnvironment {
    @TaskLocal static var database: CoreDataTestDatabase?
}

private enum ModelContainerFactory<Model: CoreDataTestModelProvider>: CoreDataTestContainerFactory {
    static func makeContainer(for profile: PersistentStoreProfile) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(
            name: Model.containerName,
            managedObjectModel: Model.makeManagedObjectModel()
        )
        container.persistentStoreDescriptions = [try profile.persistentStoreDescription()]
        return container
    }

    static func load(_ container: NSPersistentContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
        }
    }
}
