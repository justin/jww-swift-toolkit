import Foundation
import Combine
import CoreData
import JWWCore
import os

/// A container that encapsulates the Core Data stack in your app.
open class JWWCloudKitContainer: NSPersistentCloudKitContainer, JWWPersistentContainerProviding, @unchecked Sendable {
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
    public required init(name: String, bundle: Bundle) {
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

    // MARK: Public Methods
    // ====================================
    // Public Methods
    // ====================================

    /// Returns a publisher that wraps the `loadPersistentStores(completionHandler:)` function.
    ///
    /// - Returns: An `AnyPublisher` wrapping this publisher.
    public func loadPersistentStores() -> AnyPublisher<[NSPersistentStoreDescription], Error> {
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
