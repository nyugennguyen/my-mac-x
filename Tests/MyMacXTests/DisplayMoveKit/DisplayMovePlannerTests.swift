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

final class DisplayMovePlannerTests: XCTestCase {
    func testMovesRightByPreservingNormalizedCenterAndSizeAcrossAsymmetricVisibleFrames() throws {
        let source = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 900),
            visibleFrame: CGRect(x: 0, y: 30, width: 1_200, height: 840),
            backingScaleFactor: 2
        )
        let destination = display(
            id: 20,
            frame: CGRect(x: 1_200, y: -180, width: 1_800, height: 1_080),
            visibleFrame: CGRect(x: 1_200, y: -140, width: 1_800, height: 1_000),
            backingScaleFactor: 1
        )
        let topology = DisplayTopologySnapshot(
            displays: [destination, source],
            primaryDisplayID: source.id
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: 300, y: 240, width: 600, height: 420)
            ),
            direction: .right,
            topology: topology
        )

        let plan = try XCTUnwrap(result.success)
        XCTAssertEqual(plan.destinationDisplayID, destination.id)
        assertFrame(
            plan.targetFrame.cgRect,
            equals: CGRect(x: 1_650, y: 110, width: 900, height: 500)
        )
        XCTAssertEqual(plan.warnings, [])
        XCTAssertFalse(plan.isConstrained)
    }

    func testClampsOversizedMappedWindowToDestinationVisibleFrameWithWarning() throws {
        let source = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        let destination = display(
            id: 20,
            frame: CGRect(x: 1_000, y: 100, width: 500, height: 400),
            visibleFrame: CGRect(x: 1_000, y: 100, width: 500, height: 400)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: -100, y: -100, width: 1_200, height: 1_000)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [source, destination],
                primaryDisplayID: source.id
            )
        )

        let plan = try XCTUnwrap(result.success)
        XCTAssertEqual(plan.destinationDisplayID, destination.id)
        assertFrame(plan.targetFrame.cgRect, equals: destination.visibleFrame)
        XCTAssertEqual(plan.warnings, [.destinationVisibleFrameClamped])
        XCTAssertTrue(plan.isConstrained)
    }

    func testMovesLeftIntoNegativeOriginAndRoundsOnlyAtDestinationBackingScale() throws {
        let destination = display(
            id: 10,
            frame: CGRect(x: -1_600, y: -200, width: 1_200, height: 950),
            visibleFrame: CGRect(x: -1_600, y: -150, width: 1_200, height: 900),
            backingScaleFactor: 1.25
        )
        let source = display(
            id: 20,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            backingScaleFactor: 2
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: 123, y: 157, width: 333, height: 211)
            ),
            direction: .left,
            topology: DisplayTopologySnapshot(
                displays: [source, destination],
                primaryDisplayID: source.id
            )
        )

        let plan = try XCTUnwrap(result.success)
        XCTAssertEqual(plan.destinationDisplayID, destination.id)
        assertFrame(
            plan.targetFrame.cgRect,
            equals: CGRect(x: -1_452, y: 26.4, width: 399.2, height: 237.6)
        )
        XCTAssertEqual(plan.warnings, [])
    }

    func testSelectsSourceByMaximumPhysicalDisplayIntersectionBeforeCenterDistance() throws {
        let source = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )
        let diagonal = display(
            id: 20,
            frame: CGRect(x: 1_000, y: 900, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 1_000, y: 900, width: 1_000, height: 1_000)
        )
        let fartherRight = display(
            id: 30,
            frame: CGRect(x: 2_000, y: 900, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 2_000, y: 900, width: 1_000, height: 1_000)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: 800, y: 0, width: 400, height: 1_000)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [fartherRight, diagonal, source],
                primaryDisplayID: source.id
            )
        )

        XCTAssertEqual(result.success?.destinationDisplayID, diagonal.id)
    }

    func testBreaksEqualIntersectionByNearestDisplayCenter() throws {
        let nearer = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )
        let farther = display(
            id: 20,
            frame: CGRect(x: 500, y: 0, width: 1_500, height: 1_000),
            visibleFrame: CGRect(x: 500, y: 0, width: 1_500, height: 1_000)
        )
        let rightmost = display(
            id: 30,
            frame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: 600, y: 100, width: 300, height: 300)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [farther, rightmost, nearer],
                primaryDisplayID: nearer.id
            )
        )

        XCTAssertEqual(result.success?.destinationDisplayID, farther.id)
    }

    func testBreaksCoincidentDisplayTieByTopologyScopedIdentity() throws {
        let lowerID = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )
        let higherID = display(
            id: 20,
            frame: lowerID.frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 1_000)
        )
        let destination = display(
            id: 30,
            frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: 250, y: 250, width: 500, height: 500)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [higherID, destination, lowerID],
                primaryDisplayID: lowerID.id
            )
        )

        let plan = try XCTUnwrap(result.success)
        XCTAssertEqual(plan.destinationDisplayID, destination.id)
        assertFrame(
            plan.targetFrame.cgRect,
            equals: CGRect(x: 1_250, y: 250, width: 500, height: 500)
        )
    }

    func testUsesNearestDisplayCenterWhenWindowDoesNotIntersectAnyDisplay() throws {
        let nearer = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )
        let farther = display(
            id: 20,
            frame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: -500, y: -500, width: 100, height: 100)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [farther, nearer],
                primaryDisplayID: nearer.id
            )
        )

        XCTAssertEqual(result.success?.destinationDisplayID, farther.id)
    }

    func testWrapsRightFromRightmostDisplayToSpatiallyLeftmostDisplay() throws {
        let leftmost = display(
            id: 30,
            frame: CGRect(x: -2_000, y: 200, width: 1_000, height: 900),
            visibleFrame: CGRect(x: -2_000, y: 200, width: 1_000, height: 900)
        )
        let middle = display(
            id: 20,
            frame: CGRect(x: 0, y: -200, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: -200, width: 1_000, height: 1_000)
        )
        let rightmost = display(
            id: 10,
            frame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: 2_250, y: 250, width: 500, height: 500)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [rightmost, middle, leftmost],
                primaryDisplayID: middle.id
            )
        )

        XCTAssertEqual(result.success?.destinationDisplayID, leftmost.id)
    }

    func testStopsAtDirectionalEdgeWhenWrapPolicyDisallowsWrap() {
        let left = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )
        let right = display(
            id: 20,
            frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: 1_250, y: 250, width: 500, height: 500)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [right, left],
                primaryDisplayID: left.id
            ),
            wrapPolicy: .stopAtEdge
        )

        XCTAssertEqual(result.failure, .noDestination)
    }

    func testFailsWhenTopologyHasNoOtherPhysicalDisplay() {
        let only = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: 250, y: 250, width: 500, height: 500)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [only],
                primaryDisplayID: only.id
            )
        )

        XCTAssertEqual(result.failure, .noDestination)
    }

    func testRejectsInvalidCapturedWindowFrameBeforeSelectingDisplays() {
        let first = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )
        let second = display(
            id: 20,
            frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000),
            visibleFrame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000)
        )

        let result = DisplayMovePlanner().plan(
            window: AppKitGlobalLogicalFrame(
                CGRect(x: CGFloat.nan, y: 0, width: 500, height: 500)
            ),
            direction: .right,
            topology: DisplayTopologySnapshot(
                displays: [first, second],
                primaryDisplayID: first.id
            )
        )

        XCTAssertEqual(result.failure, .invalidWindowFrame)
    }

    private func display(
        id: UInt32,
        frame: CGRect,
        visibleFrame: CGRect,
        backingScaleFactor: CGFloat = 1
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: visibleFrame,
            backingScaleFactor: backingScaleFactor,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            ),
            notchTrigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: frame.midX, y: frame.maxY - 1, width: 1, height: 1)
            )
        )
    }

    private func assertFrame(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }
}

private extension Result {
    var success: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }

    var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
