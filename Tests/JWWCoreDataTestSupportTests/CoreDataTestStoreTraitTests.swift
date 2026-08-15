import CoreData
import Testing
@testable import JWWCoreDataTestSupport

@Suite(.coreDataStore(CoreDataTestStoreTraitTestModel.self, storage: .sqlite))
@MainActor
struct CoreDataTestStoreTraitTests {
    @Test("The trait provides a temporary SQLite database")
    func providesTemporarySQLiteStore() throws {
        let database = try CoreDataTestContext.database

        #expect(database.storeURL != nil)
    }

    @Test("The trait confines Core Data work to its private context")
    func performsWorkOnPrivateManagedObjectContext() async throws {
        let database = try CoreDataTestContext.database

        let count = try await database.perform { context in
            let entity = try #require(NSEntityDescription.entity(forEntityName: "Item", in: context))
            _ = NSManagedObject(entity: entity, insertInto: context)
            try context.save()

            return try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "Item"))
        }

        #expect(count == 1)
    }
}

@MainActor
struct CoreDataTestContextTests {
    @Test("Database access requires the Core Data trait")
    func databaseAccessRequiresTrait() {
        #expect(throws: CoreDataTestContext.AccessError.self) {
            try CoreDataTestContext.database
        }
    }
}

private enum CoreDataTestStoreTraitTestModel: CoreDataTestModelProvider {
    static let containerName = "CoreDataTestStoreTraitTests"

    @MainActor
    static func makeManagedObjectModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "Item"
        entity.managedObjectClassName = "NSManagedObject"

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
}
