import CoreData

public extension NSManagedObjectContext {
    /// Return a managed object of type T with the given objectID.
    func existingObject<T: NSManagedObject>(with objectID: NSManagedObjectID) throws -> T {
        // JWW: 11/20/21
        // This force cast is ok because if the objectID doesn't exist it will throw. And if the object IS found but not the
        // type we expected, someone messed up somewhere.

        // swiftlint:disable:next force_cast
        return try existingObject(with: objectID) as! T
    }
}
