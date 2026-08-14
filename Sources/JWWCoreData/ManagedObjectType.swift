import CoreData

/// Simple subclass of `NSManagedObject` that allows the use of generics, without catching other `NSManagedObject` instances.
open class JWWManagedObject: NSManagedObject {
    public required override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }
}

/// Convenience protocol applied to `JWWManagedObject` class instances.
public protocol ManagedObjectType: AnyObject {
    /// The type of entity we are using.
    associatedtype Entity: NSFetchRequestResult

    /// The name of the Managed Object entity.
    static var entityName: String { get }

    /// Returned a `NSFetchRequest` object that uses the default sort descriptors.
    static var sortedFetchRequest: NSFetchRequest<Entity> { get }

    /// `Array` of default `SortDescriptor` instances. See `sortedFetchRequest` for more details.
    static var defaultSortDescriptors: [NSSortDescriptor] { get }
}

// MARK: ManagedObjectType Defaults
// ====================================
// ManagedObjectType Defaults
// ====================================
extension ManagedObjectType where Self: JWWManagedObject {
    /// The sort descriptors to use in a default `sortedFetchRequest`
    public static var defaultSortDescriptors: [NSSortDescriptor] {
        return []
    }

    /// Returned a `NSFetchRequest` object that uses the default sort descriptors.
    public static var sortedFetchRequest: NSFetchRequest<Entity> {
        let request = NSFetchRequest<Entity>(entityName: entityName)
        request.sortDescriptors = defaultSortDescriptors
        return request
    }

    /// Generate a fetch request for the `Entity`.
    ///
    /// - Parameters:
    ///   - predicate: An optional `NSPredicate` to filter the fetch request.
    ///   - sortDescriptors: Optional `NSSortDescriptor` array to sort the fetched objects.
    /// - Returns: An `NSFetchRequest` object.
    public static func fetchRequest<Entity>(withPredicate predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor]?) -> NSFetchRequest<Entity> {
        let request = NSFetchRequest<Entity>(entityName: entityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return request
    }
}
