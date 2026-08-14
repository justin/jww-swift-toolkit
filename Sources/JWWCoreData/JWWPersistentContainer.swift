import Foundation
import Combine
import CoreData
import JWWCore
import os

/// A container that encapsulates the Core Data stack in your app.
open class JWWPersistentContainer: NSPersistentContainer, JWWPersistentContainerProviding, @unchecked Sendable {
    /// The current loading state of the persistent stores managed by the container.
    @Published public var state: NSPersistentContainer.State = .inactive

    /// Publisher that fires when the persistent container has loaded its attached stores.
    public private(set) lazy var isLoadedPublisher: AnyPublisher<Void, Never> = {
        $state
            .drop(while: { state in
                state != .loaded
            })
            .map({ _ in () })
            .share()
            .eraseToAnyPublisher()
    }()

    private let log = Logger(category: .database)
    private var saveNotificationSubscriber: AnyCancellable?
    private var persistentStoreLoadingSubscriber: AnyCancellable?

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    /// Initializes a persistent container with the given name and model.
    /// - Parameters:
    ///   - name: The name used by the persistent container
    ///   - bundle: The bundle to search for the managed object model.
    public init(name: String, bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: "momd") else {
            fatalError("Failed to find model \(name) in bundle.")
        }

        guard let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to load momd file \(name) at url \(url).")
        }

        super.init(name: name, managedObjectModel: model)

        configureSaveNotifications()
        persistentStoreLoadingSubscriber = isLoadedPublisher
            .receive(on: ImmediateScheduler.shared)
            .sink(receiveValue: { [self] _ in
                viewContext.name = "UI / Main thread context"
                viewContext.automaticallyMergesChangesFromParent = true
                viewContext.shouldDeleteInaccessibleFaults = true
                viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            })
    }

    // MARK: Loading Persistent Stores
    // ====================================
    // Loading Persistent Stores
    // ====================================

    /// Returns a publisher that wraps the `loadPersistentStores(completionHandler:)` function.
    ///
    /// - Returns: An `AnyPublisher` wrapping this publisher.
    open func loadPersistentStores() -> AnyPublisher<[NSPersistentStoreDescription], Error> {
        Publishers.MergeMany(persistentStoreDescriptions.map(load(store:)))
            .collect()
            .handleEvents(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    self.state = .failed(error)
                case .finished:
                    self.state = .loaded
                }
            })
            .eraseToAnyPublisher()
    }

    /// Loads the persistent stores.
    open func loadPersistentStores() async throws {
        do {
            for store in persistentStoreDescriptions {
                try await load(store: store)
            }

            await updateState(.loaded)
        } catch {
            await updateState(.failed(error))

            throw error
        }
    }

    @MainActor
    private func updateState(_ newState: State) async {
        self.state = newState
    }

    /// Load an individual persistent store
    ///
    /// - Parameter store: The persistent store to load.
    /// - Returns: The persistent store description object for the loaded store.
    @discardableResult
    open func load(store: NSPersistentStoreDescription) -> AnyPublisher<NSPersistentStoreDescription, Error> {
        Future { [self] promise in
            persistentStoreCoordinator.addPersistentStore(with: store) { (_, error) in
                if let error {
                    return promise(.failure(error))
                }

                return promise(.success((store)))
            }
        }.eraseToAnyPublisher()
    }

    /// Load an individual persistent store
    ///
    /// - Parameter store: The persistent store to load.
    /// - Returns: The persistent store description object for the loaded store.
    open func load(store: NSPersistentStoreDescription) async throws {
        return try await withCheckedThrowingContinuation({ continuation in
            persistentStoreCoordinator.addPersistentStore(with: store) { (_, error) in
                if let error {
                    return continuation.resume(throwing: error)
                }

                return continuation.resume(returning: ())
            }
        })
    }

    // MARK: Subclass Methods
    // ====================================
    // Subclass Methods
    // ====================================

    open override func newBackgroundContext() -> NSManagedObjectContext {
        let context = super.newBackgroundContext()
        context.undoManager = nil
        context.name = "Persistent Container Background Context"
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyStoreTrumpMergePolicyType)
        return context
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    /// Listen for changes on background contexts and merge them into the main context.
    private func configureSaveNotifications() {
        saveNotificationSubscriber = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: RunLoop.main)
            .sink { [self] (notification) in
                guard let notificationContext = notification.object as? NSManagedObjectContext else {
                    assertionFailure("Unexpected object passed through context notification.")
                    return
                }

                guard notificationContext !== viewContext else {
                    return
                }

                viewContext.perform { [viewContext] in
                    viewContext.mergeChanges(fromContextDidSave: notification)
                }
            }
    }
}
