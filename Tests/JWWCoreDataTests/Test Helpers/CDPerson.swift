import Foundation
import CoreData
import JWWCoreData

/// A `CDPerson` object represents a person in the Core Data model.
/// This is only used for exercising the `JWWCoreData` framework.
final class CDPerson: JWWManagedObject, ManagedObjectType, Identifiable {
    typealias Entity = CDPerson

    @NSManaged public var id: UUID?
    @NSManaged public var birthDate: Date?
    @NSManaged public var firstName: String?
    @NSManaged public var lastName: String?

    /// The name of the Managed Object entity.
    static var entityName: String {
        "Person"
    }

    static var sortedFetchRequest: NSFetchRequest<CDPerson> {
        let request = NSFetchRequest<CDPerson>(entityName: entityName)
        request.sortDescriptors = Self.defaultSortDescriptors
        return request
    }
}
