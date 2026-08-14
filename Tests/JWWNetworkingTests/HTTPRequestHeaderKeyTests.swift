import Foundation
import Testing
@testable import JWWNetworking

/// Tests to exercise our `HTTPRequestHeaderKey` type.
struct HTTPRequestHeaderKeyTests {
    @Test("Create a new request key")
    func testInit() {
        let key = HTTPRequestHeaderKey("test-value")

        #expect(key.value == "test-value")
    }
}
