import CoreData
import JWWCoreDataTestSupport
import Testing
@testable import JWWCoreData

/// Tests to validate the `JWWPersistentContainer` type.
@MainActor
final class JWWPersistentContainerTests {
    /// Validate our main context is properly named.
    @Test
    func `main context is configured after loading`() async throws {
        let expectedName = "UI / Main thread context"

        try await CoreDataTestStore<JWWPersistentContainerTestFactory>.withStore(storage: .sqlite) { sut in
            let result = sut.mainObjectContext.name

            #expect(result == expectedName)
        }
    }

    /// Validate a new background context is properly named.
    @Test
    func `background context is named`() async throws {
        let expectedName = "Persistent Container Background Context"

        try await CoreDataTestStore<JWWPersistentContainerTestFactory>.withStore(storage: .sqlite) { sut in
            let result = try #require(sut.newBackgroundContext().name)

            #expect(result == expectedName)
        }
    }

    /// Validate a failed store load reports the same error through the lifecycle state.
    @Test
    func `failed store loading publishes the original error`() async throws {
        let container = JWWPersistentContainer(name: "Test Database", bundle: .module)
        let invalidStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: invalidStoreURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: invalidStoreURL) }

        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: invalidStoreURL)]

        let error = await #expect(throws: (any Error).self) {
            try await container.loadPersistentStores()
        }
        let loadingError = try #require(error)

        guard case let .failed(stateError) = container.state else {
            Issue.record("Expected the container to enter the failed state.")
            return
        }

        let expectedError = loadingError as NSError
        let actualError = stateError as NSError
        #expect(actualError.domain == expectedError.domain)
        #expect(actualError.code == expectedError.code)
        #expect(container.mainObjectContext.name == nil)
    }
}

private enum JWWPersistentContainerTestFactory: CoreDataTestContainerFactory {
    static func makeContainer(for profile: PersistentStoreProfile) throws -> JWWPersistentContainer {
        let container = JWWPersistentContainer(name: "Test Database", bundle: .module)
        container.persistentStoreDescriptions = [try profile.persistentStoreDescription()]
        return container
    }

    static func load(_ container: JWWPersistentContainer) async throws {
        try await container.loadPersistentStores()
    }
}
