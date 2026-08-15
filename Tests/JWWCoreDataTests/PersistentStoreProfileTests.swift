import CoreData
import Foundation
import Testing
@testable import JWWCoreData

@Suite("Persistent store profiles")
@MainActor
struct PersistentStoreProfileTests {
    @Test("An in-memory profile creates and saves to a true in-memory store")
    func inMemoryProfileCreatesAndSavesToInMemoryStore() async throws {
        let profile = try PersistentStoreProfile(
            storage: .inMemory,
            queryGenerationPolicy: .disabled
        )
        let container = makeContainer()
        let description = try profile.persistentStoreDescription()
        container.persistentStoreDescriptions = [description]
        defer { removePersistentStores(from: container) }

        try await loadPersistentStores(in: container)
        try profile.applyQueryGenerationPolicy(to: container.viewContext)
        _ = NSManagedObject(entity: container.managedObjectModel.entities[0], insertInto: container.viewContext)
        try container.viewContext.save()

        let store = try #require(container.persistentStoreCoordinator.persistentStores.first)
        #expect(store.type == NSInMemoryStoreType)
        #expect(profile.storeURL == nil)
    }

    @Test("A SQLite profile pins the query generation and saves")
    func sqliteProfilePinsQueryGenerationAndSaves() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let profile = try PersistentStoreProfile(
            storage: .sqlite(directoryURL.appendingPathComponent("Store.sqlite")),
            queryGenerationPolicy: .required
        )
        let container = makeContainer()
        container.persistentStoreDescriptions = [try profile.persistentStoreDescription()]
        defer { removePersistentStores(from: container) }

        try await loadPersistentStores(in: container)
        try profile.applyQueryGenerationPolicy(to: container.viewContext)
        _ = NSManagedObject(entity: container.managedObjectModel.entities[0], insertInto: container.viewContext)
        try container.viewContext.save()

        let store = try #require(container.persistentStoreCoordinator.persistentStores.first)
        #expect(store.type == NSSQLiteStoreType)
        #expect(store.url == directoryURL.appendingPathComponent("Store.sqlite"))
    }

    @Test("An in-memory profile rejects a required query generation before loading")
    func inMemoryProfileRejectsRequiredQueryGeneration() {
        #expect(throws: PersistentStoreProfile.ConfigurationError.requiredQueryGenerationNeedsSQLite) {
            try PersistentStoreProfile(
                storage: .inMemory,
                queryGenerationPolicy: .required
            )
        }
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    private func makeContainer() -> NSPersistentContainer {
        let entity = NSEntityDescription()
        entity.name = "Item"
        entity.managedObjectClassName = "NSManagedObject"

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return NSPersistentContainer(name: "PersistentStoreProfileTests", managedObjectModel: model)
    }

    private func loadPersistentStores(in container: NSPersistentContainer) async throws {
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

    private func removePersistentStores(from container: NSPersistentContainer) {
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }
}
