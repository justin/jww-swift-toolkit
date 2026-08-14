import XCTest
import Combine
import CoreData
@testable import JWWCoreData

/// Tests to validate the default implementations of methods provided by `JWWPersistentContainerProviding`.
final class JWWPersistentContainerProvidingTests: XCTestCase {
    private var sut: TestPersistentContainer!
    private var subscriptions: Set<AnyCancellable> = []

    override func setUpWithError() throws {
        try super.setUpWithError()

        sut = TestPersistentContainer(name: "Test Database", bundle: .module)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        try sut.reset()
        subscriptions.removeAll()
        sut = nil
    }

    /// Validate we can load an individual persistent store.
    @MainActor
    func testLoadSingleStorePublisher() throws {
        let store = try XCTUnwrap(sut.persistentStoreDescriptions.first)

        let ex = expectation(description: "A persistent store will be loaded")
        sut.load(store: store)
            .sink { completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    XCTFail("Error initialized data store: \(error)")
                }
            } receiveValue: { _ in
                ex.fulfill()
            }
            .store(in: &subscriptions)

        waitForExpectations(timeout: 1.0, handler: nil)
    }

    /// Validate we can load all registered persistent stores using Swift concurrency.
    @available(iOS 15.0.0, macOS 12.0.0, tvOS 15.0.0, watchOS 8.0.0, *)
    func testLoadPersistentStoresAsync() async throws {
        let result = try await sut.loadPersistentStores()
        XCTAssertEqual(result, .loaded)
        XCTAssertEqual(sut.state, .loaded)
    }

    /// Validate we can perform a background task that returns a `Publisher`.
    func testPerformBackgroundTaskPublisher() throws {
        let loadingEx = expectation(description: "Waiting for store to load.")
        sut.loadPersistentStores()
            .sink { completion in
                switch completion {
                case .finished:
                    loadingEx.fulfill()
                case .failure(let error):
                    XCTFail("Error initialized data store: \(error)")
                }
            } receiveValue: { _ in }
            .store(in: &subscriptions)

        wait(for: [loadingEx], timeout: 1.0)

        let insertEx = expectation(description: "Insert 100 Person objects in the background")
        sut.performBackgroundTask(andSave: true, contextName: "Unit Test") { moc in
            guard let entity = NSEntityDescription.entity(forEntityName: "Person", in: moc) else {
                XCTFail("Cannot find entity")
                return
            }

            for index in 0..<100 {
                let person = CDPerson(entity: entity, insertInto: moc)
                person.id = UUID()
                person.firstName = "FN \(index)"
                person.lastName = "LN \(index)"
                person.birthDate = Date()
            }

            try? moc.save()
            insertEx.fulfill()
        }

        wait(for: [insertEx], timeout: 1.0)

        let count = try sut.viewContext.count(for: CDPerson.sortedFetchRequest)
        XCTAssertEqual(count, 100)
    }

    /// Validate we can perform a background task using Swift concurrency.
    @available(iOS 15.0.0, macOS 12.0.0, tvOS 15.0.0, watchOS 8.0.0, *)
    func testPerformBackgroundTaskAsync() async throws {
        try await sut.loadPersistentStores()

        await sut.performBackgroundTask(andSave: true, contextName: "Unit Test", block: { moc in
            guard let entity = NSEntityDescription.entity(forEntityName: CDPerson.entityName, in: moc) else {
                XCTFail("Cannot find entity")
                return
            }

            for index in 0..<100 {
                let person = CDPerson(entity: entity, insertInto: moc)
                person.id = UUID()
                person.firstName = "FN \(index)"
                person.lastName = "LN \(index)"
                person.birthDate = Date()
            }
        })

        let count = try sut.viewContext.count(for: CDPerson.sortedFetchRequest)
        XCTAssertEqual(count, 100)
    }
}
