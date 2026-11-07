import CoreGraphics
import XCTest

@testable import MyMacX

final class EdgeSnapAcceptancePolicyTests: XCTestCase {
    private let policy = EdgeSnapAcceptancePolicy()

    // MARK: - Minimum Bounds Guard (A-01)

    func testRejectsWindowBelowMinimumSizeFloor() {
        let target = CGRect(x: 0, y: 0, width: 700, height: 900)
        let tooNarrow = CGRect(x: 0, y: 0, width: 79, height: 900)
        let tooShort = CGRect(x: 0, y: 0, width: 700, height: 79)

        XCTAssertFalse(policy.accepts(actualRect: tooNarrow, targetRect: target, action: .leftHalf))
        XCTAssertFalse(policy.accepts(actualRect: tooShort, targetRect: target, action: .leftHalf))
    }

    // MARK: - Exact / Precision Match (A-04)

    func testAcceptsExactAndWithinPrecisionTolerance() {
        let target = CGRect(x: 100, y: 100, width: 500, height: 500)
        let exact = target
        let withinTol = CGRect(x: 105, y: 95, width: 504, height: 496)
        let outsideTol = CGRect(x: 150, y: 100, width: 500, height: 500)

        XCTAssertTrue(policy.accepts(actualRect: exact, targetRect: target, action: .leftHalf))
        XCTAssertTrue(policy.accepts(actualRect: withinTol, targetRect: target, action: .leftHalf))
        // Outside 8 pt precision tolerance, must rely on placement-specific rules:
        // Here, x=110 exceeds 36 pt anchor tolerance from 100 -> rejected
        XCTAssertFalse(policy.accepts(actualRect: outsideTol, targetRect: target, action: .leftHalf))
    }

    // MARK: - Side Halves (A-01)

    func testLeftHalfAcceptsClampedMinimumWidthWhenSpanningFullHeight() {
        let target = CGRect(x: 0, y: 0, width: 700, height: 900)
        // Clamped window has larger width (850 pt instead of 700 pt) but spans full height and left edge aligns
        let clamped = CGRect(x: 0, y: 0, width: 850, height: 900)

        XCTAssertTrue(policy.accepts(actualRect: clamped, targetRect: target, action: .leftHalf))
    }

    func testRightHalfAcceptsClampedMinimumWidthWhenRightEdgeAligns() {
        let target = CGRect(x: 700, y: 0, width: 700, height: 900)
        // Clamped window has larger width (850 pt) so its minX is 550, maxX is 1400 (aligns with target maxX 1400)
        let clamped = CGRect(x: 550, y: 0, width: 850, height: 900)

        XCTAssertTrue(policy.accepts(actualRect: clamped, targetRect: target, action: .rightHalf))
    }

    func testLeftHalfRejectsWhenLeftEdgeNotAnchored() {
        let target = CGRect(x: 0, y: 0, width: 700, height: 900)
        let misaligned = CGRect(x: 40, y: 0, width: 700, height: 900)

        XCTAssertFalse(policy.accepts(actualRect: misaligned, targetRect: target, action: .leftHalf))
    }

    func testLeftHalfRejectsWhenHeightDoesNotSpanTarget() {
        let target = CGRect(x: 0, y: 0, width: 700, height: 900)
        // Height 600 is < 82% of 900 (738 pt) and does not align top & bottom
        let shortWindow = CGRect(x: 0, y: 0, width: 700, height: 600)

        XCTAssertFalse(policy.accepts(actualRect: shortWindow, targetRect: target, action: .leftHalf))
    }

    func testHorizontalHalfAcceptsClampedHeightWhenSpanningFullWidth() {
        let target = CGRect(x: 0, y: 450, width: 1400, height: 450)
        // Top half: clamped window has taller height (600 pt) but spans full width and top edge aligns
        let clamped = CGRect(x: 0, y: 300, width: 1400, height: 600) // maxY = 900 matches target maxY = 900

        XCTAssertTrue(policy.accepts(actualRect: clamped, targetRect: target, action: .topHalf))
    }

    // MARK: - Corners (A-02)

    func testTopLeftQuarterAcceptsClampedWindowWithAnchoredCornerEdges() {
        let target = CGRect(x: 0, y: 450, width: 700, height: 450)
        // Clamped app needs 800x600; anchored at left (x=0) and top (maxY=900)
        let clamped = CGRect(x: 0, y: 300, width: 800, height: 600)

        XCTAssertTrue(policy.accepts(actualRect: clamped, targetRect: target, action: .topLeftQuarter))
    }

    func testBottomRightQuarterAcceptsClampedWindowWithAnchoredCornerEdges() {
        let target = CGRect(x: 700, y: 0, width: 700, height: 450)
        // Anchored at right (maxX=1400) and bottom (minY=0)
        let clamped = CGRect(x: 600, y: 0, width: 800, height: 500)

        XCTAssertTrue(policy.accepts(actualRect: clamped, targetRect: target, action: .bottomRightQuarter))
    }

    func testCornerRejectsWhenEitherCornerEdgeIsMisaligned() {
        let target = CGRect(x: 0, y: 450, width: 700, height: 450)
        // Left is 50 pt off (> 36 pt)
        let misalignedX = CGRect(x: 50, y: 450, width: 700, height: 450)
        // Top is 50 pt off (> 36 pt)
        let misalignedY = CGRect(x: 0, y: 400, width: 700, height: 450)

        XCTAssertFalse(policy.accepts(actualRect: misalignedX, targetRect: target, action: .topLeftQuarter))
        XCTAssertFalse(policy.accepts(actualRect: misalignedY, targetRect: target, action: .topLeftQuarter))
    }

    func testCornerRejectsWhenOverlapBelow35Percent() {
        let target = CGRect(x: 0, y: 0, width: 400, height: 400) // area 160000
        // Window is positioned such that intersection with target is tiny (< 35%)
        let clamped = CGRect(x: 0, y: 0, width: 120, height: 120) // area 14400 / 160000 = 0.09 < 0.35
        XCTAssertFalse(policy.accepts(actualRect: clamped, targetRect: target, action: .bottomLeftQuarter))
    }

    // MARK: - Maximize and Centering (A-03)

    func testMaximizeRequiresNinetyPercentOverlap() {
        let target = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let passing = CGRect(x: 0, y: 0, width: 1350, height: 900) // overlap 96.4%
        let failing = CGRect(x: 0, y: 0, width: 1100, height: 900) // overlap 78.5%

        XCTAssertTrue(policy.accepts(actualRect: passing, targetRect: target, action: .maximize))
        XCTAssertFalse(policy.accepts(actualRect: failing, targetRect: target, action: .maximize))
    }

    func testMarginMaximizeRequiresMidpointAlignmentAndEightyTwoPercentOverlap() {
        let action = ActionID(rawValue: "window.margin-maximize")
        let target = CGRect(x: 50, y: 50, width: 1300, height: 800)
        // Centered with high overlap
        let passing = CGRect(x: 50, y: 50, width: 1300, height: 800)
        // Uncentered (midX shifted by 50 pt > 36 pt)
        let offCenter = CGRect(x: 100, y: 50, width: 1300, height: 800)

        XCTAssertTrue(policy.accepts(actualRect: passing, targetRect: target, action: action))
        XCTAssertFalse(policy.accepts(actualRect: offCenter, targetRect: target, action: action))
    }

    // MARK: - Disallowed Non-Geometric Actions (A-03)

    func testDisallowedNonGeometricActionsAreAlwaysRejected() {
        let target = CGRect(x: 0, y: 0, width: 1400, height: 900)
        // A rect with high overlap and centered dimensions that would otherwise pass fallthrough
        let rect = CGRect(x: 0, y: 0, width: 1400, height: 800)

        XCTAssertFalse(policy.accepts(actualRect: rect, targetRect: target, action: .nativeFullScreen),
                       "Native full screen must be rejected by geometric acceptance policy")
        XCTAssertFalse(policy.accepts(actualRect: rect, targetRect: target, action: .restore),
                       "Restore must be rejected by geometric acceptance policy")
    }

    // MARK: - Display Transfer Actions (A-03 / 72% Overlap Floor)

    func testDisplayTransferActionsRequireSeventyTwoPercentOverlap() {
        let target = CGRect(x: 100, y: 100, width: 1000, height: 800) // area 800,000
        // 80% overlap (640,000 / 800,000), but off-center by 50 pt (> 36 pt anchor tolerance)
        let passing = CGRect(x: 150, y: 100, width: 800, height: 800)
        // 60% overlap (480,000 / 800,000 < 72% floor)
        let failing = CGRect(x: 100, y: 100, width: 600, height: 800)

        XCTAssertTrue(policy.accepts(actualRect: passing, targetRect: target, action: .moveDisplayPrevious),
                      "Move display previous should accept when overlap >= 72%")
        XCTAssertFalse(policy.accepts(actualRect: failing, targetRect: target, action: .moveDisplayPrevious),
                       "Move display previous should reject when overlap < 72%")

        XCTAssertTrue(policy.accepts(actualRect: passing, targetRect: target, action: .moveDisplayNext),
                      "Move display next should accept when overlap >= 72%")
        XCTAssertFalse(policy.accepts(actualRect: failing, targetRect: target, action: .moveDisplayNext),
                       "Move display next should reject when overlap < 72%")
    }
}
