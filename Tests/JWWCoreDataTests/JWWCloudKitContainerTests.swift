import CoreData
import JWWCoreDataTestSupport
import Testing
@testable import JWWCoreData

/// Tests to validate the `JWWCloudKitContainer` type.
@MainActor
final class JWWCloudKitContainerTests {
    /// Validate our main context is properly named.
    @Test
    func `main context is configured after loading`() async throws {
        let expectedName = "UI / Main thread context"

        try await CoreDataTestStore<JWWCloudKitContainerTestFactory>.withStore(storage: .sqlite) { sut in
            let result = sut.mainObjectContext.name

            #expect(result == expectedName)
        }
    }

    /// Validate a new background context is properly named.
    @Test
    func `background context is named`() async throws {
        let expectedName = "Persistent Container Background Context"

        try await CoreDataTestStore<JWWCloudKitContainerTestFactory>.withStore(storage: .sqlite) { sut in
            let result = try #require(sut.newBackgroundContext().name)

            #expect(result == expectedName)
        }
    }
}

private enum JWWCloudKitContainerTestFactory: CoreDataTestContainerFactory {
    static func makeContainer(for profile: PersistentStoreProfile) throws -> JWWCloudKitContainer {
        let container = JWWCloudKitContainer(name: "Test Database", bundle: .module)
        container.persistentStoreDescriptions = [try profile.persistentStoreDescription()]
        return container
    }

    static func load(_ container: JWWCloudKitContainer) async throws {
        try await container.loadPersistentStores()
    }
}
