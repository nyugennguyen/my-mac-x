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

final class LayoutKitTests: XCTestCase {
    func testBuiltInRegionsProduceExactKnownVisibleFrames() throws {
        let display = display(
            frame: CGRect(x: -2_000, y: 0, width: 2_000, height: 1_200),
            visibleFrame: CGRect(x: -1_920, y: 25, width: 1_920, height: 1_055)
        )
        let calculator = LayoutCalculator()

        let frames = Dictionary(uniqueKeysWithValues: Layout.builtIn.regions.map { region in
            (region.id, calculator.frame(for: region, in: display))
        })

        XCTAssertEqual(frames[.maximize], CGRect(x: -1_920, y: 25, width: 1_920, height: 1_055))
        XCTAssertEqual(frames[.leftHalf], CGRect(x: -1_920, y: 25, width: 960, height: 1_055))
        XCTAssertEqual(frames[.rightHalf], CGRect(x: -960, y: 25, width: 960, height: 1_055))
        XCTAssertEqual(frames[.topHalf], CGRect(x: -1_920, y: 552.5, width: 1_920, height: 527.5))
        XCTAssertEqual(frames[.bottomHalf], CGRect(x: -1_920, y: 25, width: 1_920, height: 527.5))
        XCTAssertEqual(frames[.topLeftQuarter], CGRect(x: -1_920, y: 552.5, width: 960, height: 527.5))
        XCTAssertEqual(frames[.topRightQuarter], CGRect(x: -960, y: 552.5, width: 960, height: 527.5))
        XCTAssertEqual(frames[.bottomLeftQuarter], CGRect(x: -1_920, y: 25, width: 960, height: 527.5))
        XCTAssertEqual(frames[.bottomRightQuarter], CGRect(x: -960, y: 25, width: 960, height: 527.5))
    }

    func testRejectsNonFiniteEmptyAndOutOfBoundsNormalizedRegions() {
        let cases: [(CGRect, LayoutValidationError)] = [
            (
                CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
                .nonFiniteNormalizedFrame(.leftHalf)
            ),
            (
                CGRect(x: 0, y: 0, width: 0, height: 1),
                .emptyNormalizedFrame(.leftHalf)
            ),
            (
                CGRect(x: -0.01, y: 0, width: 1, height: 1),
                .normalizedFrameOutsideUnitBounds(.leftHalf)
            ),
            (
                CGRect(x: 0.5, y: 0.5, width: 0.51, height: 0.5),
                .normalizedFrameOutsideUnitBounds(.leftHalf)
            ),
        ]

        for (frame, expectedError) in cases {
            XCTAssertThrowsError(
                try LayoutRegion(id: .leftHalf, normalizedFrame: frame)
            ) { error in
                XCTAssertEqual(error as? LayoutValidationError, expectedError)
            }
        }
    }

    func testRejectsDuplicateRegionIdentifiersWithinALayout() throws {
        let first = try LayoutRegion(id: .leftHalf, normalizedFrame: CGRect(x: 0, y: 0, width: 0.5, height: 1))
        let duplicate = try LayoutRegion(id: .leftHalf, normalizedFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))

        XCTAssertThrowsError(
            try Layout(id: "duplicate", regions: [first, duplicate])
        ) { error in
            XCTAssertEqual(error as? LayoutValidationError, .duplicateRegionID(.leftHalf))
        }
    }

    func testPlanAppliesOuterPaddingAndInteriorGapToNegativeOriginAtTwoXScale() throws {
        let display = display(
            frame: CGRect(x: -2_000, y: 0, width: 2_000, height: 1_200),
            visibleFrame: CGRect(x: -301, y: -99, width: 301, height: 199),
            backingScaleFactor: 2
        )

        let plan = try LayoutCalculator().plan(
            for: Layout.builtIn.regions.first(where: { $0.id == .topRightQuarter })!,
            in: display,
            constraints: LayoutConstraints(
                outerPadding: LayoutEdgeInsets(top: 2, left: 2, bottom: 2, right: 2),
                gap: 3
            )
        )

        XCTAssertEqual(plan.frame, CGRect(x: -149, y: 2, width: 147, height: 96))
        XCTAssertFalse(plan.isConstrained)
        XCTAssertEqual(plan.warnings, [])
    }

    func testPlanRoundsBothEdgesAtEachBackingScaleInLogicalPoints() throws {
        let region = Layout.builtIn.regions.first(where: { $0.id == .rightHalf })!
        let visibleFrame = CGRect(x: -100.2, y: 20.2, width: 101, height: 99)
        let calculator = LayoutCalculator()

        let oneX = try calculator.plan(
            for: region,
            in: display(frame: visibleFrame, visibleFrame: visibleFrame, backingScaleFactor: 1),
            constraints: .default
        )
        let onePointTwoFiveX = try calculator.plan(
            for: region,
            in: display(frame: visibleFrame, visibleFrame: visibleFrame, backingScaleFactor: 1.25),
            constraints: .default
        )
        let twoX = try calculator.plan(
            for: region,
            in: display(frame: visibleFrame, visibleFrame: visibleFrame, backingScaleFactor: 2),
            constraints: .default
        )

        assertFrame(oneX.frame, equals: CGRect(x: -49.2, y: 20.2, width: 50, height: 99))
        assertFrame(onePointTwoFiveX.frame, equals: CGRect(x: -49.8, y: 20.2, width: 50.4, height: 99))
        assertFrame(twoX.frame, equals: CGRect(x: -49.7, y: 20.2, width: 50.5, height: 99))
        XCTAssertEqual(oneX.warnings, [])
        XCTAssertEqual(onePointTwoFiveX.warnings, [.visibleFrameClamped])
        XCTAssertEqual(twoX.warnings, [])
        XCTAssertTrue(contains(oneX.frame, inside: visibleFrame))
        XCTAssertTrue(contains(onePointTwoFiveX.frame, inside: visibleFrame))
        XCTAssertTrue(contains(twoX.frame, inside: visibleFrame))
    }

    func testPlanClampsRoundingDriftToVisibleFrameAndReportsWarning() throws {
        let visibleFrame = CGRect(x: 0.2, y: 0.2, width: 100, height: 100)
        let plan = try LayoutCalculator().plan(
            for: Layout.builtIn.regions.first(where: { $0.id == .maximize })!,
            in: display(
                frame: CGRect(x: 0, y: 0, width: 120, height: 120),
                visibleFrame: visibleFrame,
                backingScaleFactor: 1
            ),
            constraints: .default
        )

        assertFrame(plan.frame, equals: visibleFrame)
        XCTAssertTrue(plan.isConstrained)
        XCTAssertEqual(plan.warnings, [.visibleFrameClamped])
        XCTAssertTrue(contains(plan.frame, inside: visibleFrame))
    }

    func testPlanAccommodatesMinimumSizeInsideVisibleFrameAndReportsConstraint() throws {
        let display = display(
            visibleFrame: CGRect(x: -400, y: -100, width: 300, height: 180),
            backingScaleFactor: 1
        )
        let region = Layout.builtIn.regions.first(where: { $0.id == .leftHalf })!

        let plan = try LayoutCalculator().plan(
            for: region,
            in: display,
            constraints: LayoutConstraints(minimumSize: CGSize(width: 230, height: 150))
        )

        XCTAssertEqual(plan.frame, CGRect(x: -400, y: -100, width: 230, height: 180))
        XCTAssertTrue(plan.isConstrained)
        XCTAssertEqual(plan.warnings, [.minimumSizeAccommodated])
        XCTAssertTrue(contains(plan.frame, inside: display.visibleFrame))
    }

    func testPlanFailsWithTypedFailuresForImpossiblePaddingGapAndMinimumSize() throws {
        let display = display(
            visibleFrame: CGRect(x: -400, y: -100, width: 300, height: 180),
            backingScaleFactor: 1
        )
        let leftHalf = Layout.builtIn.regions.first(where: { $0.id == .leftHalf })!

        XCTAssertThrowsError(
            try LayoutCalculator().plan(
                for: leftHalf,
                in: display,
                constraints: LayoutConstraints(
                    outerPadding: LayoutEdgeInsets(top: 0, left: 151, bottom: 0, right: 151)
                )
            )
        ) { error in
            XCTAssertEqual(error as? LayoutConstraintFailure, .outerPaddingEliminatesVisibleFrame)
        }
        XCTAssertThrowsError(
            try LayoutCalculator().plan(
                for: leftHalf,
                in: display,
                constraints: LayoutConstraints(gap: 301)
            )
        ) { error in
            XCTAssertEqual(error as? LayoutConstraintFailure, .gapEliminatesLayoutRegion)
        }
        XCTAssertThrowsError(
            try LayoutCalculator().plan(
                for: leftHalf,
                in: display,
                constraints: LayoutConstraints(minimumSize: CGSize(width: 301, height: 100))
            )
        ) { error in
            XCTAssertEqual(error as? LayoutConstraintFailure, .minimumSizeExceedsVisibleFrame)
        }
    }

    func testCenteredRegionIgnoresOuterPaddingForEdgesItDoesNotTouch() throws {
        let display = display(
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            backingScaleFactor: 2
        )
        let centered = try LayoutRegion(
            id: LayoutRegionID(rawValue: "centered"),
            normalizedFrame: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        )

        let plan = try LayoutCalculator().plan(
            for: centered,
            in: display,
            constraints: LayoutConstraints(
                outerPadding: LayoutEdgeInsets(
                    top: 10_000,
                    left: 10_000,
                    bottom: 10_000,
                    right: 10_000
                ),
                gap: 8
            )
        )

        XCTAssertEqual(plan.frame, CGRect(x: 254, y: 204, width: 492, height: 392))
        XCTAssertEqual(plan.warnings, [])
    }

    private func contains(_ frame: CGRect, inside visibleFrame: CGRect) -> Bool {
        frame.minX >= visibleFrame.minX - 1
            && frame.minY >= visibleFrame.minY - 1
            && frame.maxX <= visibleFrame.maxX + 1
            && frame.maxY <= visibleFrame.maxY + 1
    }

    func testLayoutRegionThumbnailGeometryCalculatesPixelRectsWithInteriorGaps() {
        let canvas = CGRect(x: 10, y: 20, width: 80, height: 50)
        let gap: CGFloat = 2.0

        // 1. Maximize fills the canvas without gap
        let maxRect = LayoutRegionThumbnailGeometry.pixelRect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            in: canvas,
            gap: gap
        )
        XCTAssertEqual(maxRect, canvas)

        // 2. Halves (columns)
        let leftHalf = LayoutRegionThumbnailGeometry.pixelRect(
            for: CGRect(x: 0, y: 0, width: 0.5, height: 1),
            in: canvas,
            gap: gap
        )
        let rightHalf = LayoutRegionThumbnailGeometry.pixelRect(
            for: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            in: canvas,
            gap: gap
        )

        XCTAssertEqual(leftHalf.minX, canvas.minX)
        XCTAssertEqual(leftHalf.width, (canvas.width - gap) / 2.0)
        XCTAssertEqual(rightHalf.maxX, canvas.maxX)
        XCTAssertEqual(rightHalf.width, (canvas.width - gap) / 2.0)
        XCTAssertEqual(rightHalf.minX - leftHalf.maxX, gap)

        // 3. Quarters (2x2 grid)
        let bottomLeft = LayoutRegionThumbnailGeometry.pixelRect(
            for: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            in: canvas,
            gap: gap
        )
        let topLeft = LayoutRegionThumbnailGeometry.pixelRect(
            for: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
            in: canvas,
            gap: gap
        )
        let bottomRight = LayoutRegionThumbnailGeometry.pixelRect(
            for: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            in: canvas,
            gap: gap
        )
        let topRight = LayoutRegionThumbnailGeometry.pixelRect(
            for: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            in: canvas,
            gap: gap
        )

        XCTAssertEqual(bottomRight.minX - bottomLeft.maxX, gap)
        XCTAssertEqual(topRight.minX - topLeft.maxX, gap)
        XCTAssertEqual(topLeft.minY - bottomLeft.maxY, gap)
        XCTAssertEqual(topRight.minY - bottomRight.maxY, gap)

        // 4. Custom Coding layout (left 60%, right top/bottom)
        let codingRegions = [
            CGRect(x: 0, y: 0, width: 0.6, height: 1),
            CGRect(x: 0.6, y: 0, width: 0.4, height: 0.5),
            CGRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5)
        ]
        let codingPixelRects = LayoutRegionThumbnailGeometry.pixelRects(
            for: codingRegions,
            in: canvas,
            gap: gap
        )
        XCTAssertEqual(codingPixelRects.count, 3)
        XCTAssertEqual(codingPixelRects[1].minX - codingPixelRects[0].maxX, gap)
        XCTAssertEqual(codingPixelRects[2].minY - codingPixelRects[1].maxY, gap)
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

    private func display(
        frame: CGRect = CGRect(x: -2_000, y: 0, width: 2_000, height: 1_200),
        visibleFrame: CGRect,
        backingScaleFactor: CGFloat = 2
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: 1),
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
                region: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
        )
    }
}
