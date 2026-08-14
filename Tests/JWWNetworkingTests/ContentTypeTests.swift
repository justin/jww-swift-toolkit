import Foundation
import Testing
@testable import JWWNetworking

/// Tests to exercise our `ContentType` type.
struct ContentTypeTests {
    @Test("Create a new content type object.")
    func initialization() {
        let key = ContentType("application/gzip")

        #expect(key.value == "application/gzip")
    }

    @Test("Return key value when describing a content type object.")
    func customDescription() throws {
        let expectedValue = "application/json"

        let result = String(describing: ContentType.json)

        #expect(result == expectedValue)
    }
}
