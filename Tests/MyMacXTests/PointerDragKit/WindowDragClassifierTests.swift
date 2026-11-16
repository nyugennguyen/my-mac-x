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

import CoreGraphics
import XCTest

@testable import MyMacX

final class WindowDragClassifierTests: XCTestCase {
    private let classifier = WindowDragClassifier()
    private let standardFrame = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let titleBarPress = CGPoint(x: 300, y: 385) // 15 pt below top, centered, safe from edges

    // MARK: - D-01: Window vs. Pointer Motion Thresholding (2 pt Floor)

    func testD01_MotionFloorThreshold2pt() {
        // Window moved <= 2 pt -> .waiting
        let stillWindow = standardFrame.offsetBy(dx: 1.0, dy: 1.0) // dw = 1.41 <= 2
        let resultWaiting = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: stillWindow,
            pointerDelta: CGVector(dx: 10, dy: 10)
        )
        XCTAssertEqual(resultWaiting, .waiting)

        // Window moved > 2 pt but pointer moved <= 2 pt -> .unrelated
        let movedWindow = standardFrame.offsetBy(dx: 5.0, dy: 0)
        let resultUnrelated = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: movedWindow,
            pointerDelta: CGVector(dx: 1.0, dy: 0)
        )
        XCTAssertEqual(resultUnrelated, .unrelated)
    }

    // MARK: - D-02: Directional Vector Cosine Alignment (>= 0.6)

    func testD02_CosineAlignmentThreshold() {
        // Same direction (cosine = 1.0 >= 0.6) -> .moving
        let alignedFrame = standardFrame.offsetBy(dx: 20, dy: 0)
        let alignedResult = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: alignedFrame,
            pointerDelta: CGVector(dx: 20, dy: 0)
        )
        XCTAssertEqual(alignedResult, .moving)

        // Angled direction: ~45 deg (cosine = 0.707 >= 0.6) -> .moving
        let angledResult = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 20, dy: 0),
            pointerDelta: CGVector(dx: 20, dy: 20)
        )
        XCTAssertEqual(angledResult, .moving)

        // Perpendicular: 90 deg (cosine = 0.0 < 0.6) -> .unrelated
        let perpResult = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 20, dy: 0),
            pointerDelta: CGVector(dx: 0, dy: 20)
        )
        XCTAssertEqual(perpResult, .unrelated)

        // Opposite direction: 180 deg (cosine = -1.0 < 0.6) -> .unrelated
        let oppositeResult = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 20, dy: 0),
            pointerDelta: CGVector(dx: -20, dy: 0)
        )
        XCTAssertEqual(oppositeResult, .unrelated)
    }

    // MARK: - D-03: Distance Travel Ratio Bounds (0.2 to 1.8)

    func testD03_DistanceTravelRatioBounds() {
        // Ratio = 1.0 in [0.2, 1.8] -> .moving
        let normalRatio = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 10, dy: 0),
            pointerDelta: CGVector(dx: 10, dy: 0)
        )
        XCTAssertEqual(normalRatio, .moving)

        // Lagging ratio: dw = 4, dp = 10 -> R = 0.4 in [0.2, 1.8] -> .moving
        let lagRatio = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 4, dy: 0),
            pointerDelta: CGVector(dx: 10, dy: 0)
        )
        XCTAssertEqual(lagRatio, .moving)

        // Catching-up ratio: dw = 15, dp = 10 -> R = 1.5 in [0.2, 1.8] -> .moving
        let catchUpRatio = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 15, dy: 0),
            pointerDelta: CGVector(dx: 10, dy: 0)
        )
        XCTAssertEqual(catchUpRatio, .moving)

        // Excessive speed / jump: dw = 25, dp = 10 -> R = 2.5 > 1.8 -> .unrelated
        let excessRatio = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 25, dy: 0),
            pointerDelta: CGVector(dx: 10, dy: 0)
        )
        XCTAssertEqual(excessRatio, .unrelated)
    }

    // MARK: - D-04: Complete Immunity for Content Drags

    func testD04_ContentDragImmunity() {
        // User drags pointer by 100 pt inside the app, but window does not move
        let result = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: standardFrame, // stationary window dw = 0
            pointerDelta: CGVector(dx: 100, dy: 100)
        )
        // Content drag always returns .waiting, never .moving
        XCTAssertEqual(result, .waiting)
    }

    // MARK: - D-05: Press-Time Native Resize Handle Rejection

    func testD05_PressTimeResizeHandleRejection() {
        // Corner checks (within 12 pt):
        // Bottom-Left corner: (102, 102)
        XCTAssertTrue(WindowDragClassifier.startsAtResizeHandle(CGPoint(x: 102, y: 102), in: standardFrame))
        // Top-Right corner: (498, 398)
        XCTAssertTrue(WindowDragClassifier.startsAtResizeHandle(CGPoint(x: 498, y: 398), in: standardFrame))

        // Edge checks (within 5 pt):
        // Left border: (103, 200)
        XCTAssertTrue(WindowDragClassifier.startsAtResizeHandle(CGPoint(x: 103, y: 200), in: standardFrame))
        // Top border: (250, 398)
        XCTAssertTrue(WindowDragClassifier.startsAtResizeHandle(CGPoint(x: 250, y: 398), in: standardFrame))

        // Title-bar grab away from corners and borders: (300, 385)
        XCTAssertFalse(WindowDragClassifier.startsAtResizeHandle(titleBarPress, in: standardFrame))

        // When pressing at a resize handle, classification immediately returns .resizing
        let cornerResult = classifier.classify(
            pressPoint: CGPoint(x: 102, y: 102),
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 10, dy: 10),
            pointerDelta: CGVector(dx: 10, dy: 10)
        )
        XCTAssertEqual(cornerResult, .resizing)
    }

    // MARK: - D-06: Mid-Drag Native Resize Detection via Perpendicular Edge Anchoring

    func testD06_MidDragPerpendicularEdgeAnchoredResizeRejection() {
        // User resizes window from bottom-right corner: minX and maxY stay anchored (delta <= 2)
        // Dimensions expand from 400x300 to 450x350
        let resizedFrame = CGRect(x: 100, y: 50, width: 450, height: 350)
        // minX is 100 (anchored to 100)
        // maxY is 400 (anchored to 100 + 300 = 400)
        XCTAssertTrue(WindowDragClassifier.sharesPerpendicularEdges(resizedFrame, with: standardFrame))

        let result = classifier.classify(
            pressPoint: titleBarPress,
            initialFrame: standardFrame,
            currentFrame: resizedFrame,
            pointerDelta: CGVector(dx: 50, dy: -50)
        )
        XCTAssertEqual(result, .resizing)
    }

    // MARK: - D-07: Restoration Resize Exception for Un-Snapping Drags

    func testD07_RestorationResizeException() {
        // A snapped half-screen window (0, 0, 960, 1080) dragged away to (200, 300, 600, 500)
        let snappedFrame = CGRect(x: 0, y: 0, width: 960, height: 1080)
        let restoredDragFrame = CGRect(x: 200, y: 300, width: 600, height: 500)

        // Neither vertical nor horizontal edges remain anchored
        XCTAssertFalse(WindowDragClassifier.sharesPerpendicularEdges(restoredDragFrame, with: snappedFrame))

        let result = classifier.classify(
            pressPoint: CGPoint(x: 480, y: 1060),
            initialFrame: snappedFrame,
            currentFrame: restoredDragFrame,
            pointerDelta: CGVector(dx: 200, dy: 300)
        )
        // Successfully classified as a valid moving window drag!
        XCTAssertEqual(result, .moving)
    }

    // MARK: - D-08: Consecutive Mismatch Tolerance (3-Strike Filter)

    func testD08_ThreeStrikeMismatchTolerance() {
        var filter = WindowDragFilter()

        // 1. Initial unrelated does not cancel (mismatchCount = 1)
        let state1 = filter.update(with: .unrelated)
        XCTAssertEqual(filter.mismatchCount, 1)
        XCTAssertEqual(state1, .waiting)
        XCTAssertFalse(filter.isCancelled)

        // 2. Second unrelated does not cancel (mismatchCount = 2)
        let state2 = filter.update(with: .unrelated)
        XCTAssertEqual(filter.mismatchCount, 2)
        XCTAssertEqual(state2, .waiting)
        XCTAssertFalse(filter.isCancelled)

        // 3. A single .moving resets mismatch counter to 0 and confirms moving
        let state3 = filter.update(with: .moving)
        XCTAssertEqual(filter.mismatchCount, 0)
        XCTAssertEqual(state3, .moving)
        XCTAssertTrue(filter.isConfirmedMoving)

        // 4. Temporary hitch while moving: 2 unrelated evaluations are tolerated
        _ = filter.update(with: .unrelated)
        XCTAssertEqual(filter.mismatchCount, 1)
        let stateDuringHitch = filter.update(with: .unrelated)
        XCTAssertEqual(filter.mismatchCount, 2)
        XCTAssertEqual(stateDuringHitch, .moving) // Still moving!
        XCTAssertFalse(filter.isCancelled)

        // 5. Third consecutive strike cancels the drag
        let stateCancelled = filter.update(with: .unrelated)
        XCTAssertEqual(filter.mismatchCount, 3)
        XCTAssertEqual(stateCancelled, .cancelled)
        XCTAssertTrue(filter.isCancelled)
    }

    // MARK: - Finding 1 Regression: Orthogonal Bounding on Resize Handle Edge Checks

    func testFinding1_OrthogonalBoundingOnResizeHandleEdgeChecks() {
        // Standard window frame: (100, 100, 400, 300), so x in [100, 500], y in [100, 400]

        // 1. Point at (102, 900): x is within 5 pt of frame.minX (100), but y is 500 pt outside the window!
        let farYPoint = CGPoint(x: 102, y: 900)
        XCTAssertFalse(
            WindowDragClassifier.startsAtResizeHandle(farYPoint, in: standardFrame),
            "Press far along Y outside the window frame must not classify as a resize handle"
        )

        // 2. Point at (900, 102): y is within 5 pt of frame.minY (100), but x is 400 pt outside the window!
        let farXPoint = CGPoint(x: 900, y: 102)
        XCTAssertFalse(
            WindowDragClassifier.startsAtResizeHandle(farXPoint, in: standardFrame),
            "Press far along X outside the window frame must not classify as a resize handle"
        )

        // 3. Point at (102, 250): x is within 5 pt of frame.minX (100), and y is within [100, 400]
        let validLeftEdge = CGPoint(x: 102, y: 250)
        XCTAssertTrue(
            WindowDragClassifier.startsAtResizeHandle(validLeftEdge, in: standardFrame),
            "Press along left edge within window bounds must classify as a resize handle"
        )

        // 4. Verify classify() does not report .resizing for farYPoint
        let classification = classifier.classify(
            pressPoint: farYPoint,
            initialFrame: standardFrame,
            currentFrame: standardFrame.offsetBy(dx: 10, dy: 10),
            pointerDelta: CGVector(dx: 10, dy: 10)
        )
        XCTAssertNotEqual(classification, .resizing)
    }
}
