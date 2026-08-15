import Foundation
import CoreData
import JWWCoreData

/// An implementation of `JWWPersistentContainerProviding` that can be used in unit tests.
final class TestPersistentContainer: NSPersistentContainer, JWWPersistentContainerProviding, @unchecked Sendable {
    /// The current loading state of the persistent stores managed by the container.
    @MainActor var state: NSPersistentContainer.State = .inactive

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    init(name: String, bundle: Bundle) throws {
        guard let url = bundle.url(forResource: name, withExtension: "momd") else {
            fatalError("Failed to find model \(name) in bundle.")
        }

        guard let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to load momd file \(name) at url \(url).")
        }

        super.init(name: name, managedObjectModel: model)
        let profile = try PersistentStoreProfile(
            storage: .inMemory,
            queryGenerationPolicy: .disabled
        )
        persistentStoreDescriptions = [try profile.persistentStoreDescription()]
    }

    deinit {
        try? reset()
    }
}
