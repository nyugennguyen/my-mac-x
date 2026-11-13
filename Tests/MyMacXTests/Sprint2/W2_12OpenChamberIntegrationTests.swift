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

#if canImport(MyMacX)
import XCTest
@testable import MyMacX

final class W2_12OpenChamberIntegrationTests: XCTestCase {
    func testG2PhysicalMultiDisplayMoveUndoAndRestore() async throws {
        guard OpenChamberWindowActionHarness.isG2ExplicitlyArmed else {
            throw XCTSkip(
                "Set MYMACX_G2_MULTI_DISPLAY_CONFIRMATION=RUN_OPENCHAMBER_G2_MULTI_DISPLAY for a human-run test."
            )
        }

        let report = try await OpenChamberWindowActionHarness().runG2PhysicalMultiDisplay()
        XCTAssertGreaterThanOrEqual(report.displayCount, 2)
        XCTAssertNotEqual(report.sourceDisplayID, report.destinationDisplayID)
        XCTAssertTrue(report.undoReturnedToSource)
        XCTAssertTrue(report.previousReturnedToSource)
        XCTAssertTrue(report.originalFrameRestored)
    }

    /// Opt-in only: the normal suite must never move a real application's window.
    func testOpenChamberCompletesOneHundredVerifiedSnapActionsAndRestoresFrame() async throws {
        guard OpenChamberWindowActionHarness.isExplicitlyArmed else {
            throw XCTSkip(
                "Set MYMACX_W2_12_OPENCHAMBER_CONFIRMATION=RUN_OPENCHAMBER_W2_12 for a human-run test."
            )
        }

        let report = try await OpenChamberWindowActionHarness().run()
        XCTAssertEqual(report.bundleIdentifier, "dev.openchamber.desktop")
        XCTAssertEqual(report.actionCount, 100)
        XCTAssertEqual(report.verifiedReadBackCount, 100)
        XCTAssertTrue(report.originalFrameRestored)
    }
}
#endif
