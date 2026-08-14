import Foundation
import Testing
@testable import JWWNetworking

/// Tests to exercise our `HTTPMethod` type.
struct HTTPMethodTests {
    @Test("Validate if we attempt to generate a string from a method it returns the expected value in uppercase")
    func testStringValuesReturnUppercase() {
        let expectedValues = ["GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "OPTIONS", "TRACE", "PATCH"]

        for method in HTTPMethod.allCases {
            let result = String(describing: method)
            #expect(expectedValues.contains(result))
        }
    }
}
