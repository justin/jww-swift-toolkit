import CoreData
import Testing
@testable import JWWCoreData

/// Tests to validate the default implementations of methods provided by `JWWPersistentContainerProviding`.
@MainActor
final class JWWPersistentContainerProvidingTests {
    private let sut: TestPersistentContainer

    init() throws {
        sut = try TestPersistentContainer(name: "Test Database", bundle: .module)
    }

    isolated deinit {
        try? sut.reset()
    }

    /// Validate we can load all registered persistent stores using Swift concurrency.
    @Test
    func `all persistent stores load asynchronously`() async throws {
        try await sut.loadPersistentStores()
        #expect(sut.state == .loaded)
    }

    /// Validate we can perform a background task using Swift concurrency.
    @Test
    func `background task saves changes`() async throws {
        try await sut.loadPersistentStores()

        try await sut.performBackgroundTask(andSave: true, contextName: "Unit Test", block: { moc in
            let entity = try #require(NSEntityDescription.entity(forEntityName: CDPerson.entityName, in: moc))

            for index in 0..<100 {
                let person = CDPerson(entity: entity, insertInto: moc)
                person.id = UUID()
                person.firstName = "FN \(index)"
                person.lastName = "LN \(index)"
                person.birthDate = Date()
            }
        })

        let count = try sut.viewContext.count(for: CDPerson.sortedFetchRequest)
        #expect(count == 100)
    }
}
