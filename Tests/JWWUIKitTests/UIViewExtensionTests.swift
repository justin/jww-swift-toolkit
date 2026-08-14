#if canImport(UIKit) && !os(watchOS)
import UIKit
import XCTest

@testable import JWWUIKit

final class UIViewExtensionTests: XCTestCase {
  /// Validate we can set `usesAutoLayout` to true and it sets the underlying propery to the expected value.
  func testEnablingAutoLayoutOnView() {
    let view = UIView()
    view.usesAutoLayout = true

    XCTAssertFalse(view.translatesAutoresizingMaskIntoConstraints)
  }

  /// Validate we can set `usesAutoLayout` to false and it sets the underlying propery to the expected value.
  func testDisablingAutoLayoutOnView() {
    let view = UIView()
    view.usesAutoLayout = false

    XCTAssertTrue(view.translatesAutoresizingMaskIntoConstraints)
  }
}
#endif
