// MyMacX
// Copyright (C) 2026 NyugenNguyen
//
// This program is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the LICENSE file for details.

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
