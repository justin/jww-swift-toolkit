import Foundation
import Testing
import SwiftData
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import JWWSwiftData

/// Tests to verify the functionality of `JWWFetchedResultsController`.
@Suite("Sectionless Fetched Results Controller")
@MainActor
final class JWWFetchedResultsControllerTests {
    private let sut: JWWFetchedResultsController<Int, Person>
    private let container: ModelContainer
    private var delegate: JWWFetchedResultsControllerTestsDelegate?

    init() throws {
        container = JWWSwiftDataTestingStack().testingModelContainer

        var fetchDescriptor = FetchDescriptor<Person>()
        fetchDescriptor.sortBy = [
            SortDescriptor(\.firstName, order: .forward)
        ]

        sut = JWWFetchedResultsController(fetchDescriptor: fetchDescriptor, modelContainer: container)
    }

    deinit {
        try? container.erase()
    }

    @Test("init")
    func initController() async {
        #expect(sut.fetchedModels == nil)
        #expect(sut.sections.isEmpty)
        #expect(sut.sectionIndexTitles.isEmpty)
        #expect(sut.delegate == nil)
    }

    @Test("Fetching initial data")
    func fetchInitialData() async throws {
        try insertDefaultObjects()

        try await sut.fetch()

        let result = try #require(sut.fetchedModels)
        #expect(result.count == 3, "Expected 3 people, but got \(result.count)")
    }

    @Test("A single default section exists")
    func singleSectionedFetch() async throws {
        try insertDefaultObjects()

        try await sut.fetch()

        #expect(sut.sections.count == 1, "Expected 1 section, but got \(sut.sections.count)")
        #expect(sut.sectionIndexTitles.count == 1, "Expected 1 section index title, but got \(sut.sectionIndexTitles.count)")
    }

    @Test("Initial fetch doesn't call delegate methods")
    func initialFetchDoesntCallDelegate() async throws {
        delegate = JWWFetchedResultsControllerTestsDelegate()
        sut.delegate = delegate
        try insertDefaultObjects()

        try await sut.fetch()

        let result = try #require(delegate)
        #expect(result.controllerWillChangeContentCalled == false, "Delegate methods should not be called after the initial fetch.")
        #expect(result.controllerDidChangeContentCalled == false, "Delegate methods should not be called after the initial fetch.")
//        #expect(result.controllerDidChangeObjectCalled == false, "Delegate methods should not be called after the initial fetch.")
    }

    @Test("Updating already fetched data calls delegate methods")
    func updatingDataCallsDelegateMethods() async throws {
        delegate = JWWFetchedResultsControllerTestsDelegate()
        sut.delegate = delegate
        try insertDefaultObjects()
        try await sut.fetch()

        container.mainContext.insert(Person(id: UUID(), role: .user, firstName: "Steve"))
        try container.mainContext.save()

        let result = try #require(delegate)
//        #expect(result.controllerWillChangeContentCalled == true, "Delegate methods should be called after data change.")
//        #expect(result.controllerDidChangeContentCalled == true, "Delegate methods should be called after data change.")
        #expect(result.controllerDidChangeObjectCalled == true, "Delegate methods should be called after data change.")
    }

    @Test("object(at:) returns correct object")
    func objectAtIndexPath() async throws {
        try insertDefaultObjects()
        try await sut.fetch()

        let indexPath = IndexPath(item: 1, section: 0)
        let object = try sut.object(at: indexPath)
        #expect(object.firstName == "Jane")
    }

    @Test("indexPath(forObject:) returns correct indexPath")
    func indexPathForObject() async throws {
        try insertDefaultObjects()
        try await sut.fetch()

        let object = try #require(sut.fetchedModels?.last)
        let indexPath = sut.indexPath(forObject: object)
        #expect(indexPath == IndexPath(item: 2, section: 0))
    }

    @Test("object(at:) throws for out-of-bounds indexPath")
    func objectAtIndexPathOutOfBounds() async throws {
        try insertDefaultObjects()
        try await sut.fetch()

        let indexPath = IndexPath(item: 10, section: 0)
        #expect(throws: JWWFetchedResultsControllerError.indexPathOutOfBounds) {
            try self.sut.object(at: indexPath)
        }
    }

    @Test("indexPath(forObject:) returns nil for missing object")
    func indexPathForNonexistentObject() async throws {
        try insertDefaultObjects()
        try await sut.fetch()

        let missing = Person(id: UUID(), role: .user, firstName: "Ghost")
        let indexPath = sut.indexPath(forObject: missing)
        #expect(indexPath == nil)
    }

    @Test("Updates passed to stream")
    func updatesPassedToStream() async throws {
        try insertDefaultObjects()
        try await sut.fetch()

        var results: [JWWFetchedResultsChangeType] = []

        // Iterate over the async stream within a Task
        try await confirmation(expectedCount: 1) { confirmation in
            Task {
                for await update in sut.updates {
                    results.append(update)
                }
            }

            let new = Person(id: UUID(), role: .user, firstName: "Steve")
            container.mainContext.insert(new)
            try container.mainContext.save()
        }


        #expect(results.isEmpty == false)
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    /// Inserts default test objects into the container.
    private func insertDefaultObjects() throws {
        let people: [Person] = [
            Person(id: UUID(), role: .user, firstName: "John"),
            Person(id: UUID(), role: .user, firstName: "Jane"),
            Person(id: UUID(), role: .user, firstName: "Doe")
        ]
        for person in people {
            container.mainContext.insert(person)
        }
        try container.mainContext.save()
    }
}

@Suite("Sectioned Fetched Results Controller")
@MainActor
final class JWWFetchedResultsControllerSectionedTests {
    private let sut: JWWFetchedResultsController<String, Person>
    private let container: ModelContainer
    private var delegate: JWWFetchedResultsControllerTestsDelegate?

    init() throws {
        container = JWWSwiftDataTestingStack().testingModelContainer

        var fetchDescriptor = FetchDescriptor<Person>()
        fetchDescriptor.sortBy = [
            SortDescriptor(\.role.rawValue, order: .forward),
            SortDescriptor(\.firstName, order: .forward)
        ]

        sut = JWWFetchedResultsController<String, Person>(fetchDescriptor: FetchDescriptor<Person>(),
                                                          modelContainer: container,
                                                          sectionKeyPath: \Person.role.rawValue
        )
    }

    deinit {
        try? container.erase()
    }

    @Test("Setting sectionNameKeyPath correctly groups fetched results into sections")
    func initWithSectionNameKeyPath() async throws {
        try insertDefaultObjects()
        try await sut.fetch()

        #expect(sut.sections.isEmpty == false, "Sections should not be empty after fetching.")
        #expect(sut.sections.count == 2, "Expected 2 sections, but got \(sut.sections.count)")
    }

    @Test("indexPath(forObject:) returns correct indexPath")
    func indexPathForObject() async throws {
        let expectedResult = IndexPath(item: 0, section: 0)
        try insertDefaultObjects()
        try await sut.fetch()

        let object = try #require(sut.fetchedModels?.first(where: { $0.role == .admin }))

        print("Object is \(object.firstName!)")
        let result = try #require(sut.indexPath(forObject: object))
        #expect(result == expectedResult, "Expected indexPath to be \(expectedResult), but got \(result)")
    }

    @Test("object(at:) throws for out-of-bounds indexPath section")
    func objectAtIndexPathOutOfBounds() async throws {
        try insertDefaultObjects()
        try await sut.fetch()

        let indexPath = IndexPath(item: 10, section: 10)
        #expect(throws: JWWFetchedResultsControllerError.sectionIndexOutOfBounds) {
            try self.sut.object(at: indexPath)
        }
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    /// Inserts default test objects into the container.
    private func insertDefaultObjects() throws {
        let people: [Person] = [
            Person(id: UUID(), role: .admin, firstName: "John"),
            Person(id: UUID(), role: .user, firstName: "Jane"),
            Person(id: UUID(), role: .user, firstName: "Doe")
        ]
        for person in people {
            container.mainContext.insert(person)
        }
        try container.mainContext.save()
    }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
private final class JWWFetchedResultsControllerTestsDelegate: JWWFetchedResultsControllerDelegate {
    private(set) var controllerWillChangeContentCalled: Bool
    private(set) var controllerDidChangeObjectCalled: Bool
    private(set) var controllerDidChangeContentCalled: Bool

    init() {
        self.controllerWillChangeContentCalled = false
        self.controllerDidChangeObjectCalled = false
        self.controllerDidChangeContentCalled = false
    }

    func controllerWillChangeContent(_ controller: JWWSwiftData.JWWFetchedResultsController<some Hashable, some PersistentModel>) {
        controllerWillChangeContentCalled = true
    }

    func controllerDidChangeContent(_ controller: JWWSwiftData.JWWFetchedResultsController<some Hashable, some PersistentModel>) {
        controllerDidChangeContentCalled = true
    }

    func controller(_ controller: JWWFetchedResultsController<some Hashable, some PersistentModel>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        controllerDidChangeContentCalled = true
    }
}
