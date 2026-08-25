import Foundation
import XCTest
@testable import MyMacX

final class ActionIDTests: XCTestCase {
    func testActionIDRoundTripsThroughCodable() throws {
        let original = ActionID(rawValue: "layout.left-half")

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActionID.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }
}
