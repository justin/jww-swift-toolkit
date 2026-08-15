import CoreData
import Foundation
import JWWCoreData
import Testing
@testable import JWWCoreDataTestSupport

@Suite("Core Data test stores")
@MainActor
struct CoreDataTestStoreTests {
    @Test("An in-memory store uses a true Core Data in-memory profile")
    func inMemoryStoreUsesTrueInMemoryProfile() async throws {
        let store = try await makeStore(storage: .memory)
        defer { try? store.cleanup() }

        let persistentStore = try #require(store.container.persistentStoreCoordinator.persistentStores.first)
        #expect(persistentStore.type == NSInMemoryStoreType)
        #expect(store.storeURL == nil)
        #expect(store.profile.queryGenerationPolicy == .disabled)

        try store.cleanup()
    }

    @Test("Temporary SQLite stores are unique and clean up their owned files")
    func temporarySQLiteStoresAreUniqueAndCleanUpFiles() async throws {
        let firstStore = try await makeStore(storage: .sqlite)
        let secondStore = try await makeStore(storage: .sqlite)
        let firstURL = try #require(firstStore.storeURL)
        let secondURL = try #require(secondStore.storeURL)

        #expect(firstURL != secondURL)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))

        try firstStore.cleanup()
        try secondStore.cleanup()

        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(!FileManager.default.fileExists(atPath: secondURL.path))
    }

    @Test("Scoped composition loads a supplied container and saves through it")
    func scopedCompositionLoadsAndSavesThroughSuppliedContainer() async throws {
        let count = try await CoreDataTestStore<TestContainerFactory>.withStore(
            storage: .sqlite,
            operation: { container in
                let entity = try #require(container.managedObjectModel.entities.first)
                _ = NSManagedObject(entity: entity, insertInto: container.viewContext)
                try container.viewContext.save()

                return try container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "Item"))
            }
        )

        #expect(count == 1)
    }

    @Test("Explicit cleanup is idempotent")
    func explicitCleanupIsIdempotent() async throws {
        let store = try await makeStore(storage: .sqlite)

        try store.cleanup()
        try store.cleanup()
    }

    @Test("A failed store release still deletes the owned directory")
    func failedStoreReleaseStillDeletesOwnedDirectory() async throws {
        let store = try await makeStore(storage: .sqlite)
        let directoryURL = try #require(store.storeURL).deletingLastPathComponent()

        // A store the resource does not own fails validation partway through cleanup.
        _ = try store.container.persistentStoreCoordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil,
            options: nil
        )

        #expect(throws: CoreDataTestStoreError.Cleanup.unexpectedPersistentStore) {
            try store.cleanup()
        }
        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
    }

    @Test("A scoped operation failure and a cleanup failure are both preserved")
    func scopedOperationAndCleanupFailuresArePreserved() async throws {
        nonisolated(unsafe) var storeURL: URL?

        let error = await #expect(throws: CoreDataTestStoreError.OperationAndCleanup.self) {
            try await CoreDataTestStore<TestContainerFactory>.withStore(
                storage: .sqlite,
                operation: { container in
                    storeURL = container.persistentStoreCoordinator.persistentStores.first?.url

                    // A store the resource does not own fails validation during cleanup.
                    _ = try container.persistentStoreCoordinator.addPersistentStore(
                        ofType: NSInMemoryStoreType,
                        configurationName: nil,
                        at: nil,
                        options: nil
                    )

                    throw TestError.expected
                }
            )
        }

        let combined = try #require(error)
        #expect(combined.operationError as? TestError == .expected)
        #expect(combined.cleanupError as? CoreDataTestStoreError.Cleanup == .unexpectedPersistentStore)

        let directoryURL = try #require(storeURL).deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
    }

    @Test("A store failure and a resource failure are both preserved")
    func storeAndResourceFailuresArePreserved() async throws {
        let store = try await makeStore(storage: .sqlite)
        let directoryURL = try #require(store.storeURL).deletingLastPathComponent()
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.removeItem(at: outsideURL)
        }

        for persistentStore in store.container.persistentStoreCoordinator.persistentStores {
            try store.container.persistentStoreCoordinator.remove(persistentStore)
        }
        try FileManager.default.removeItem(at: directoryURL)
        try FileManager.default.createSymbolicLink(at: directoryURL, withDestinationURL: outsideURL)

        // A store the resource does not own fails while the owned directory is also unusable.
        _ = try store.container.persistentStoreCoordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil,
            options: nil
        )

        let error = #expect(throws: CoreDataTestStoreError.StoreAndResource.self) {
            try store.cleanup()
        }

        let combined = try #require(error)
        #expect(combined.storeError as? CoreDataTestStoreError.Cleanup == .unexpectedPersistentStore)
        #expect(combined.resourceError as? CoreDataTestStoreError.Cleanup == .invalidOwnedDirectory)
    }

    @Test("A failed container factory removes the temporary resource it received")
    func failedContainerFactoryRemovesTemporaryResource() async {
        var storeURL: URL?
        FailingContainerFactory.storeURL = nil

        await #expect(throws: TestError.self) {
            _ = try await CoreDataTestStore<FailingContainerFactory>(storage: .sqlite)
        }
        storeURL = FailingContainerFactory.storeURL

        guard let storeURL else {
            Issue.record("The failed factory did not receive its temporary SQLite profile.")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: storeURL.deletingLastPathComponent().path))
    }

    @Test("A failed container load removes its temporary SQLite resource")
    func failedContainerLoadRemovesTemporaryResource() async {
        FailingLoadContainerFactory.storeURL = nil

        await #expect(throws: TestError.self) {
            _ = try await CoreDataTestStore<FailingLoadContainerFactory>(storage: .sqlite)
        }

        guard let storeURL = FailingLoadContainerFactory.storeURL else {
            Issue.record("The failed load did not create its temporary SQLite store.")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
    }

    @Test("A failed scoped operation still removes its temporary SQLite resource")
    func failedScopedOperationRemovesTemporaryResource() async {
        var storeURL: URL?

        await #expect(throws: TestError.self) {
            _ = try await CoreDataTestStore<TestContainerFactory>.withStore(
                storage: .sqlite,
                operation: { container in
                    storeURL = container.persistentStoreCoordinator.persistentStores.first?.url
                    throw TestError.expected
                }
            )
        }

        guard let storeURL else {
            Issue.record("The scoped operation did not receive a loaded SQLite store.")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: storeURL.path))
    }

    @Test("Cleanup refuses a symbolic-link replacement of its owned directory")
    func cleanupRefusesSymbolicLinkReplacement() async throws {
        let store = try await makeStore(storage: .sqlite)
        let storeURL = try #require(store.storeURL)
        let directoryURL = storeURL.deletingLastPathComponent()
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.removeItem(at: outsideURL)
        }

        for persistentStore in store.container.persistentStoreCoordinator.persistentStores {
            try store.container.persistentStoreCoordinator.remove(persistentStore)
        }
        try FileManager.default.removeItem(at: directoryURL)
        try FileManager.default.createSymbolicLink(at: directoryURL, withDestinationURL: outsideURL)

        #expect(throws: CoreDataTestStoreError.Cleanup.invalidOwnedDirectory) {
            try store.cleanup()
        }
        #expect(FileManager.default.fileExists(atPath: outsideURL.path))
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    private func makeStore(storage: CoreDataTestStoreStorage) async throws -> CoreDataTestStore<TestContainerFactory> {
        try await CoreDataTestStore(storage: storage)
    }
}

private enum TestContainerFactory: CoreDataTestContainerFactory {
    static func makeContainer(for profile: PersistentStoreProfile) throws -> NSPersistentContainer {
        let entity = NSEntityDescription()
        entity.name = "Item"
        entity.managedObjectClassName = "NSManagedObject"

        let model = NSManagedObjectModel()
        model.entities = [entity]

        let container = NSPersistentContainer(
            name: "CoreDataTestStoreTests",
            managedObjectModel: model
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

@MainActor
private enum FailingContainerFactory: CoreDataTestContainerFactory {
    static var storeURL: URL?

    static func makeContainer(for profile: PersistentStoreProfile) throws -> NSPersistentContainer {
        storeURL = profile.storeURL
        throw TestError.expected
    }

    static func load(_ container: NSPersistentContainer) async throws {}
}

@MainActor
private enum FailingLoadContainerFactory: CoreDataTestContainerFactory {
    static var storeURL: URL?

    static func makeContainer(for profile: PersistentStoreProfile) throws -> NSPersistentContainer {
        storeURL = profile.storeURL
        return try TestContainerFactory.makeContainer(for: profile)
    }

    static func load(_ container: NSPersistentContainer) async throws {
        try await TestContainerFactory.load(container)
        throw TestError.expected
    }
}

private enum TestError: Error, Equatable {
    case expected
}
