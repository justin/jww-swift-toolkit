import Foundation
import SwiftData
import CoreData
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import JWWCore
import os
import _JWWDataInternal

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
public enum JWWFetchedResultsControllerError: Error {
    case indexPathOutOfBounds
    case objectNotFound
    case sectionIndexOutOfBounds
    case sectionNotFound
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
public enum JWWFetchedResultsChangeType: String, CaseIterable, Hashable {
    case inserted
    case updated
    case deleted
}

public protocol JWWFetchedResultsSectionInfo {
    var name: String { get }
    var numberOfObjects: Int { get }
    var objects: [Any] { get }
}

private struct Section: JWWFetchedResultsSectionInfo {
    let name: String
    let numberOfObjects: Int
    let objects: [Any]
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
@MainActor
public protocol JWWFetchedResultsControllerDelegate: AnyObject {
    func controllerWillChangeContent(_ controller: JWWFetchedResultsController<some Hashable, some PersistentModel>)

//    func controller(_ controller: JWWFetchedResultsController<some PersistentModel>, didChange sectionInfo: any JWWFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: JWWFetchedResultsChangeType)
//
//    func controller(_ controller: JWWFetchedResultsController<some PersistentModel>, didChange anObject: some PersistentModel, at indexPath: IndexPath?, for type: JWWFetchedResultsChangeType, newIndexPath: IndexPath?)
//
    func controller(_ controller: JWWFetchedResultsController<some Hashable, some PersistentModel>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference)
//
    func controllerDidChangeContent(_ controller: JWWFetchedResultsController<some Hashable, some PersistentModel>)
}

public extension JWWFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: JWWFetchedResultsController<some Hashable, some PersistentModel>) { }

//    func controller(_ controller: JWWFetchedResultsController<some PersistentModel>, didChange sectionInfo: any JWWFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: JWWFetchedResultsChangeType) { }
//
//    func controller(_ controller: JWWFetchedResultsController<some PersistentModel>, didChange anObject: some PersistentModel, at indexPath: IndexPath?, for type: JWWFetchedResultsChangeType, newIndexPath: IndexPath?) { }
//
    func controller(_ controller: JWWFetchedResultsController<some Hashable, some PersistentModel>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) { }

    func controllerDidChangeContent(_ controller: JWWFetchedResultsController<some Hashable, some PersistentModel>) { }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
@MainActor
public final class JWWFetchedResultsController<SectionIdentifierType: Hashable, PersistentModelType: PersistentModel> {
    public typealias SectionKeyPath = KeyPath<PersistentModelType, SectionIdentifierType>

    public nonisolated(unsafe) unowned(unsafe) var delegate: (any JWWFetchedResultsControllerDelegate)?
    public private(set) var fetchedModels: [PersistentModelType]?
    public nonisolated let modelContainer: ModelContainer

    public let updates: AsyncStream<JWWFetchedResultsChangeType>

    public private(set) var sections: [any JWWFetchedResultsSectionInfo]

    public var sectionIndexTitles: [String] {
        return sections.map(\.name)
    }

    private let modelContext: ModelContext
    private let fetchDescriptor: FetchDescriptor<PersistentModelType>
    internal let notificationCenter: NotificationCenter = .default
    private let sectionKeyPath: SectionKeyPath?

    /// The continuation for the events stream.
    private var continuation: AsyncStream<JWWFetchedResultsChangeType>.Continuation

    /// The task that is used to monitor the database for changes.
    private var notificationsTask: Task<Void, Never>?

    private var currentSnapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, PersistentIdentifier> = .init()

    // MARK: Initialization
    // ====================================
    // Initialization
    // ====================================

    public init(fetchDescriptor: FetchDescriptor<PersistentModelType>, modelContainer: ModelContainer, sectionKeyPath: SectionKeyPath? = nil, delegate: JWWFetchedResultsControllerDelegate? = nil) {
        self.fetchDescriptor = fetchDescriptor
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
        self.delegate = delegate
        self.sectionKeyPath = sectionKeyPath
        self.sections = []

        let (stream, continuation) = AsyncStream.makeStream(of: JWWFetchedResultsChangeType.self)
        self.updates = stream
        self.continuation = continuation
    }

    deinit {
        Task { [notificationsTask] in
            notificationsTask?.cancel()
        }
    }

    // MARK: Public API
    // ====================================
    // Public API
    // ====================================

    public func fetch() async throws {
        let results  = try modelContext.fetch(fetchDescriptor)

        fetchedModels = results

        let grouped: Dictionary<SectionIdentifierType, [PersistentModelType]>
        if let sectionKeyPath {
            grouped = Dictionary(grouping: results, by: { $0[keyPath: sectionKeyPath] })

            sections = grouped.map { (key, value) in
                Section(name: "\(key)", numberOfObjects: value.count, objects: value.sorted(using: fetchDescriptor.sortBy))
            }
            .sorted { $0.name < $1.name }

        } else {
            sections = [Section(name: "All", numberOfObjects: results.count, objects: results)]
        }

        notificationsTask = Task { [notificationCenter] in
            await subscribeToModelChanges(notificationCenter: notificationCenter)
        }
    }

    public func object(at indexPath: IndexPath) throws (JWWFetchedResultsControllerError) -> PersistentModelType {
        guard indexPath.section < sections.endIndex else {
            throw JWWFetchedResultsControllerError.sectionIndexOutOfBounds
        }

        guard let section = sections[indexPath.section] as? Section else {
            throw JWWFetchedResultsControllerError.sectionNotFound
        }

        let objects = section.objects
        if objects.isEmpty {
            throw JWWFetchedResultsControllerError.objectNotFound
        }

        guard indexPath.item < objects.endIndex else {
            throw JWWFetchedResultsControllerError.indexPathOutOfBounds
        }

        guard let result = objects[indexPath.item] as? PersistentModelType else {
            throw JWWFetchedResultsControllerError.objectNotFound
        }

        return result
    }

    public func indexPath(forObject object: PersistentModelType) -> IndexPath? {
        for (sectionIndex, section) in sections.enumerated() {
            if let rowIndex = section.objects.firstIndex(where: { $0 as? PersistentModelType == object }) {
                return IndexPath(item: rowIndex, section: sectionIndex)
            }
        }
        return nil
    }

    // MARK: Private / Convenience
    // ====================================
    // Private / Convenience
    // ====================================

    private func subscribeToModelChanges(notificationCenter: NotificationCenter) async {
        for await userInfo in notificationCenter.notifications(named: ModelContext.didSave)
            .compactMap(\.userInfo)
            .map({ userInfo in
                let categories = [JWWFetchedResultsChangeType.inserted, JWWFetchedResultsChangeType.deleted, JWWFetchedResultsChangeType.updated]
                let result: [JWWFetchedResultsChangeType: [PersistentIdentifier]] = [:]
                return categories.reduce(into: result) { result, category in
                    // Only insert the category into the result if it has values.
                    if let ids = userInfo[category.rawValue] as? [PersistentIdentifier], !ids.isEmpty {
                        result[category] = ids
                    }
                }
            })
            .filter({ !$0.isEmpty }) { // Skip any empty dictionaries since there's nothing worth doing.
            Logger.package.debug("Reloading widget timelines because of \(userInfo)")
            await processHistory()
        }
    }


    private func processHistory() async {
        var historyDescriptor = HistoryDescriptor<DefaultHistoryTransaction>()

        if let token = mostRecentHistoryToken {
            historyDescriptor.predicate = #Predicate { transaction in
                (transaction.token > token)
            }
        }

        let context = ModelContext(modelContainer)
        var results: Set<PersistentModelType> = []
        var transactions: [DefaultHistoryTransaction] = []
        do {
            transactions = try modelContext.fetchHistory(historyDescriptor)

            if !transactions.isEmpty {
                Logger.package.info("Processing \(transactions.count) history transactions.")
            }

            var newSnapshot = currentSnapshot

            for transaction in transactions {
                for change in transaction.changes {
                    let modelID = change.changedPersistentIdentifier

                    switch change {
                    case .insert(_ as DefaultHistoryInsert<PersistentModelType>):
                        // Find the section for the inserted object
                        if let sectionKeyPath = sectionKeyPath {
                            let fetchDescriptor = FetchDescriptor<PersistentModelType>(predicate: #Predicate { object in
                                object.persistentModelID == modelID
                            })
                            if let object = try? context.fetch(fetchDescriptor).first {
                                let sectionIdentifier = object[keyPath: sectionKeyPath]
                                if !newSnapshot.sectionIdentifiers.contains(sectionIdentifier) {
                                    newSnapshot.appendSections([sectionIdentifier])
                                }
                                newSnapshot.appendItems([modelID], toSection: sectionIdentifier)
                            }
                        } else {
                            if newSnapshot.sectionIdentifiers.isEmpty {
                                newSnapshot.appendSections(["All" as! SectionIdentifierType])
                            }
                            newSnapshot.appendItems([modelID], toSection: newSnapshot.sectionIdentifiers.first!)
                        }
                    case .update(_ as DefaultHistoryUpdate<PersistentModelType>):
                        // For update, you may want to reload the item
                        newSnapshot.reloadItems([modelID])
                    case .delete(_ as DefaultHistoryDelete<PersistentModelType>):
                        newSnapshot.deleteItems([modelID])
                    default:
                        break
                    }
                }
            }

            // Update the current snapshot
            currentSnapshot = newSnapshot
            if let delegate {
                let snapshotRef = newSnapshot as NSDiffableDataSourceSnapshotReference
                delegate.controller(self, didChangeContentWith: snapshotRef)
            }

            Logger.package.debug("Processed results are: \(String(describing: results))")

            // Update the history token using the last transaction. The last transaction has the latest token.
            if let newLastPersistentHistoryToken = transactions.last?.token {
                Logger.package.debug("History returned new token: \(String(describing: newLastPersistentHistoryToken), privacy: .public)")

                mostRecentHistoryToken = newLastPersistentHistoryToken
            }
        } catch {
            Logger.package.error("Error while fetching history \(error, privacy: .public)")
        }
    }

    // Track the last history token processed for a store, and write its value to file.
    // The historyQueue reads the token when executing operations, and updates it after processing is complete.
    private var mostRecentHistoryToken: DefaultHistoryToken? {
        get {
            guard let data = try? Data(contentsOf: historyTokenURL) else {
                return nil
            }

            return try? JSONDecoder().decode(DefaultHistoryToken.self, from: data)
        }

        set {
            guard let token = newValue, let data = try? JSONEncoder().encode(token) else {
                return
            }

            do {
                try data.write(to: historyTokenURL)
            } catch {
                let message = "Could not write token data"
                Logger.package.error("\(message): \(error, privacy: .public)")
            }
        }
    }

    private lazy var historyTokenURL: URL = {
        guard let configuration = modelContainer.configurations.first(where: { $0.schema == modelContainer.schema })
        else {
            fatalError("Could not find configuration for the persistent store")
        }

        let url = configuration.url
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                let message = "Could not create persistent container URL"
                Logger.package.error("\(message): \(error, privacy: .public)")
            }
        }

        let tokenName = "\(configuration.name).json"
        return url.deletingLastPathComponent().appendingPathComponent(tokenName, isDirectory: false)
    }()
}
