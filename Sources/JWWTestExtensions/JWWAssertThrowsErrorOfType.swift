import Foundation
import XCTest

/// Wrapper around `XCTAssertThrowsError` that allows you to easily assert that the error thrown by an expression is of
/// the expected type.
public func JWWAssertThrowsErrorOfType<T, E: Error>(_ expression: @autoclosure () throws -> T,
                                                    type: E.Type,
                                                    _ message: @autoclosure () -> String = "",
                                                    file: StaticString = #filePath,
                                                    line: UInt = #line) {
    XCTAssertThrowsError(try expression(), message(), file: file, line: line) { (error) in
        XCTAssertNotNil(error as? E, file: file, line: line)
    }
}

//  written with the assistance of the honorable Jamie Pinkham: https://twitter.com/jamiepinkham
