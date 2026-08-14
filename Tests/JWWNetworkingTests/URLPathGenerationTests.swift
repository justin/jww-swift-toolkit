import Foundation
import Testing
@testable import JWWNetworking

/// Tests to validate the `URL.Path` type.
struct URLPathGenerationTests {
    @Test("Create a new Path object.")
    func initialization() throws {
        let path = Path("v1/foo/1/bar")
        let expectedValue = "/v1/foo/1/bar"

        let result = path.pathValue

        #expect(result == expectedValue)
    }

    @Test("Get the `pathValue` for a given path object.")
    func gettingPathValue() throws {
        let path = Path(["v1", "foo", 1, "bar"])
        let expectedValue = "/v1/foo/1/bar"

        let result = path.pathValue

        #expect(result == expectedValue)
    }

    @Test("Get the `stringValue` for a given path object.")
    func gettingStringValue() throws {
        let path = Path(["v1", "foo", 1, "bar"])
        let expectedValue = "v1/foo/1/bar"

        let result = path.stringValue

        #expect(result == expectedValue)
    }

    @Test("Don't add a second leading \"/\" if one was already defined during path init.")
    func omittingSeparatorIfItAlreadyExists() throws {
        let path = Path("/v1/foo/1/bar")
        let expectedValue = "/v1/foo/1/bar"

        let result = path.pathValue

        #expect(result == expectedValue)
    }

    @Test("Create a new Path object with an empty path.")
    func emptyPathValue() throws {
        let path = Path("")
        let expectedValue = ""

        let result = path.pathValue

        #expect(result == expectedValue)
    }

    @Test("Append a new path component to an existing one.")
    func appendingNewPathComponent() throws {
        let path = Path("v1")
        let expectedValue = "/v1/foo"

        let result = path.appending(Path("foo"))

        #expect(result.pathValue == expectedValue)
    }

    @Test("Join two path objects together.")
    func additionOperator() throws {
        let path = Path("v1")
        let expectedValue = "/v1/foo"

        let result = path + Path("foo")

        #expect(result.pathValue == expectedValue)
    }

    @Test("Path with a separator in each component.")
    func pathWithASeparatorInEachComponent() throws {
        let path = Path("/v1", "/foo", "biz")
        let expectedValue = "/v1/foo/biz"

        let result = path.pathValue

        #expect(result == expectedValue)
    }
}
