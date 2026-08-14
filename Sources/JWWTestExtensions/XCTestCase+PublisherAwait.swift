import Foundation
import Combine
import XCTest

public extension XCTestCase {
    /// Wrapper around waiting for a test expectation for a Publisher type.
    ///
    /// - Parameters:
    ///   - publisher: The publisher you want to wait the result of.
    ///   - timeout: The number of seconds until the expectation should timeout.
    ///
    /// - Returns: The output of the publisher upon success.
    @discardableResult
    func await<T: Publisher>(_ publisher: T,
                             timeout: TimeInterval = UITestTimeout.unitTestExpectation,
                             file: StaticString = #filePath,
                             line: UInt = #line) async throws -> T.Output {
        var result: Result<T.Output, Error>?
        let expectation = self.expectation(description: "Awaiting response from publisher under test.")

        let cancellable = publisher.sink(
            receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    result = .failure(error)
                case .finished:
                    break
                }

                expectation.fulfill()
            },
            receiveValue: { value in
                result = .success(value)
            }
        )

        await fulfillment(of: [expectation], timeout: timeout)
        cancellable.cancel()

        let unwrappedResult = try XCTUnwrap(result, "Awaited publisher did not generate any expected output", file: file, line: line)

        return try unwrappedResult.get()
    }
}
