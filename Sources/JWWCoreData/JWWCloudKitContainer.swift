import Foundation
import CoreData
import JWWCore
import os

/// A container that encapsulates the Core Data stack in your app.
open class JWWCloudKitContainer: NSPersistentCloudKitContainer, JWWPersistentContainerProviding, @unchecked Sendable {
    /// The current loading state of the persistent stores managed by the container.
    @MainActor public var state: NSPersistentContainer.State = .inactive

    // JWW: 08/15/26 This token is written and read only on the main actor, which is what forces
    // `deinit` to be isolated as well. Isolated deinit is what sets this package's platform
    // minimums (iOS 18.4 / macOS 15.4 / tvOS 18.4 / visionOS 2.4 / watchOS 11.4); lowering any of
    // them stops this file from compiling.
    @MainActor private var saveNotificationObserver: NSObjectProtocol?

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    /// Initializes a persistent container with the given name and model.
    /// - Parameters:
    ///   - name: The name used by the persistent container
    ///   - bundle: The bundle to search for the managed object model.
    @MainActor
    public required init(name: String, bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: "momd") else {
            fatalError("Failed to find model \(name) in bundle.")
        }

        guard let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to load momd file \(name) at url \(url).")
        }

        super.init(name: name, managedObjectModel: model)

    }

    @MainActor
    deinit {
        if let saveNotificationObserver {
            NotificationCenter.default.removeObserver(saveNotificationObserver)
        }
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

    /// Loads the persistent stores.
    public func loadPersistentStores() async throws {
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

                return continuation.resume(returning: ())
            }
        }
    }

    @MainActor
    private func completeLoading() {
        configureSaveNotifications()
        configureViewContext()
        state = .loaded
    }

    @MainActor
    private func recordLoadingFailure(_ error: Error) {
        state = .failed(error)
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    /// Listen for changes on background contexts and merge them into the main context.
    @MainActor
    private func configureSaveNotifications() {
        guard saveNotificationObserver == nil else {
            return
        }

        saveNotificationObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let notificationContext = notification.object as? NSManagedObjectContext else {
                return
            }

            guard notificationContext !== self.viewContext else {
                return
            }

            self.viewContext.mergeChanges(fromContextDidSave: notification)
        }
    }

    @MainActor
    private func configureViewContext() {
        viewContext.name = "UI / Main thread context"
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.shouldDeleteInaccessibleFaults = true
        viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }
}
