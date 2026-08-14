import XCTest

/// Asserts that an async expression throws an error.
///
/// - Parameters:
///   - expression: An expression that can throw an error.
///   - errorThrown: An expression that validates the error that is thrown. If the `expression` succeeds, `XCTFail` is called.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
@inlinable
public func JWWAssertThrowsError<T, R>(_ expression: @autoclosure () async throws -> T,
                                       _ errorThrown: @autoclosure () -> R,
                                       _ message: @autoclosure () -> String = "",
                                       file: StaticString = #filePath,
                                       line: UInt = #line) async where R: Comparable, R: Error {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        XCTAssertEqual(error as? R, errorThrown())
    }
}

/// Asserts that an async expression throws an error.
///
/// - Parameters:
///   - expression: An expression that can throw an error.
///   - file: The file where the failure occurs. The default is the filename of the test case where
///   you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call
///   this function.
///   - errorHandler: An optional handler for errors that expression throws.
@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
@inlinable
public func JWWAssertThrowsError<T>(_ expression: @autoclosure () async throws -> T,
                                    file: StaticString = #filePath,
                                    line: UInt = #line,
                                    errorHandler: ((Error) -> Void)?) async {
    do {
        _ = try await expression()
        XCTFail("Expression did not throw error", file: file, line: line)
    } catch {
        errorHandler?(error)
    }
}
