import Foundation
import JWWCore
import os

package extension Logger {
    /// Logger for logging related to SwiftData and CoreData.
    static let package = Logger(subsystem: .default, category: .init(rawValue: "package"))
}
