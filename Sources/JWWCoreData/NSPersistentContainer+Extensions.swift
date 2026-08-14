import Foundation
import CoreData
import Combine
import os

public extension NSPersistentContainer {
    /// The supported storage types.
    enum Storage: String {
        /// Load the container using in-memory storage.
        case memory

        /// Load the container using a SQLite database.
        case persisted

        /// Returns the URL where the store will keep its data.
        public var url: URL {
            switch self {
            case .memory:
                return URL(fileURLWithPath: "/dev/null")
            case .persisted:
                return NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("Storage.sqlite")
            }
        }
    }

    /// The potential states the persistent container can be in.
    enum State: Equatable {
        /// The container has not loaded its stores.
        case inactive

        /// The persistent stores have been loaded.
        case loaded

        /// Loading persistent stores failed with an error.
        case failed(Error)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.inactive, .inactive),
                (.loaded, .loaded),
                (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }
}

/// Protocol that declares the extensions and custom attributes
public protocol JWWPersistentContainerProviding: AnyObject {
    /// The current loading state of the persistent stores managed by the container.
    var state: NSPersistentContainer.State { get set }

    /// Publisher that fires when the persistent container has loaded its attached stores.
    var isLoadedPublisher: AnyPublisher<Void, Never> { get }

    /// The main thread / UI managed object context.
    var mainObjectContext: NSManagedObjectContext { get }

    /// Perform a background task against the loaded persistent container.
    @discardableResult
    func performBackgroundTask(andSave shouldSave: Bool,
                               transactionAuthor: String?,
                               contextName name: String?,
                               closure: @escaping (NSManagedObjectContext) -> Void) -> Future<Void, Error>

    /// Returns a publisher that wraps the `loadPersistentStores(completionHandler:)` function.
    ///
    /// - Returns: An `AnyPublisher` wrapping this publisher.
    func loadPersistentStores() -> AnyPublisher<[NSPersistentStoreDescription], Error>

    /// Load a single persistent store.
    func load(store: NSPersistentStoreDescription) -> AnyPublisher<NSPersistentStoreDescription, Error>

    /// Load all persistent stores.
    func loadPersistentStores() async throws -> NSPersistentContainer.State

    /// Unload any persistent stores and truncate the data inside.
    func reset() throws

    /// Load an individual persistent store.
    ///
    /// - Parameter store: The persistent store to load.
    func load(store: NSPersistentStoreDescription) async throws -> NSPersistentContainer.State

    @available(iOS 15.0.0, macOS 12.0.0, tvOS 15.0.0, watchOS 8.0.0, *)
    func performBackgroundTask<T>(andSave shouldSave: Bool,
                                  transactionAuthor: String?,
                                  contextName name: String?,
                                  block: @escaping (NSManagedObjectContext) throws -> T) async rethrows -> T
}

// MARK: Default Implementations
// ====================================
// Default Implementations
// ====================================
public extension JWWPersistentContainerProviding where Self: NSPersistentContainer {
    var mainObjectContext: NSManagedObjectContext {
        viewContext
    }

    @available(iOS 15.0.0, macOS 12.0.0, tvOS 15.0.0, watchOS 8.0.0, *)
    func performBackgroundTask<T>(andSave shouldSave: Bool,
                                  transactionAuthor: String? = nil,
                                  contextName name: String? = nil,
                                  block: @escaping (NSManagedObjectContext) throws -> T) async rethrows -> T {
        try await self.performBackgroundTask { context in
            context.transactionAuthor = transactionAuthor
            context.name = name
            let result = try block(context)

            guard shouldSave, context.hasChanges else {
                return result
            }

            try context.save()
            return result
        }
    }

    @discardableResult
    func performBackgroundTask(andSave shouldSave: Bool,
                               transactionAuthor: String? = nil,
                               contextName name: String? = nil,
                               closure: @escaping (NSManagedObjectContext) -> Void) -> Future<Void, Error> {
        return Future { promise in
            self.performBackgroundTask { context in
                context.transactionAuthor = transactionAuthor
                context.name = name
                closure(context)

                guard shouldSave, context.hasChanges else {
                    promise(.success(()))
                    return
                }

                do {
                    promise(.success(try context.save()))
                } catch let error as NSError {
                    context.rollback()
                    Logger(category: .database).error("Error inserting default assets \(error.userInfo)")
                    promise(.failure(error))
                }
            }
        }
    }

    @discardableResult
    func loadPersistentStores() async throws -> NSPersistentContainer.State {
        for store in persistentStoreDescriptions {
            _ = try await load(store: store)
        }

        state = .loaded
        return state
    }

    @discardableResult
    func load(store: NSPersistentStoreDescription) async throws -> NSPersistentContainer.State {
        return try await withCheckedThrowingContinuation({ continuation in
            persistentStoreCoordinator.addPersistentStore(with: store) { (_, error) in
                if let error {
                    self.state = .failed(error)
                    continuation.resume(throwing: error)
                }

                self.state = .loaded
                continuation.resume(returning: .loaded)
            }
        })
    }

    func load(store: NSPersistentStoreDescription) -> AnyPublisher<NSPersistentStoreDescription, Error> {
        Future { [self] promise in
            persistentStoreCoordinator.addPersistentStore(with: store) { (_, error) in
                if let error = error {
                    return promise(.failure(error))
                }

                return promise(.success((store)))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: Unloading / Destorying Persistent Stores
    // ===============================================
    // Unloading / Destorying Persistent Stores
    // ===============================================

    /// Unload any persistent stores and truncate the data inside.
    func reset() throws {
        for storeURL in persistentStoreCoordinator.persistentStores.filter({
            $0.type == NSSQLiteStoreType
        }).compactMap(\.url) {
            try persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL, ofType: NSSQLiteStoreType, options: nil)
        }
    }
}
