import Foundation
import CoreData

public extension NSPersistentContainer {
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
    @MainActor var state: NSPersistentContainer.State { get set }

    /// The main thread / UI managed object context.
    @MainActor var mainObjectContext: NSManagedObjectContext { get }

    /// Load all persistent stores.
    func loadPersistentStores() async throws

    /// Unload any persistent stores and truncate the data inside.
    func reset() throws

    @available(iOS 15.0.0, macOS 12.0.0, tvOS 15.0.0, watchOS 8.0.0, *)
    func performBackgroundTask<T: Sendable>(
        andSave shouldSave: Bool,
        transactionAuthor: String?,
        contextName name: String?,
        block: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async rethrows -> T
}

// MARK: Default Implementations
// ====================================
// Default Implementations
// ====================================
public extension JWWPersistentContainerProviding where Self: NSPersistentContainer {
    @MainActor var mainObjectContext: NSManagedObjectContext {
        viewContext
    }

    @available(iOS 15.0.0, macOS 12.0.0, tvOS 15.0.0, watchOS 8.0.0, *)
    func performBackgroundTask<T: Sendable>(
        andSave shouldSave: Bool,
        transactionAuthor: String? = nil,
        contextName name: String? = nil,
        block: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async rethrows -> T {
        try await self.performBackgroundTask { @Sendable context in
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

    func loadPersistentStores() async throws {
        do {
            for store in persistentStoreDescriptions {
                try await load(store: store)
            }

            await completeLoading()
        } catch {
            await recordLoadingFailure(error)
            throw error
        }
    }

    private func load(store: NSPersistentStoreDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            persistentStoreCoordinator.addPersistentStore(with: store) { (_, error) in
                if let error {
                    return continuation.resume(throwing: error)
                }

                continuation.resume(returning: ())
            }
        }
    }

    @MainActor
    private func completeLoading() {
        state = .loaded
    }

    @MainActor
    private func recordLoadingFailure(_ error: Error) {
        state = .failed(error)
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
