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
