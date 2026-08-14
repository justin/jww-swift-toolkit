import Foundation
import SwiftData

final class JWWSwiftDataTestingStack: Sendable {
    let testingModelContainer: ModelContainer = {
        let schema = Schema([
            Person.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create SwiftDataTestingStack.testingModelContainer: \(error)")
        }
    }()

    init() {}
}
