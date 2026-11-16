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

/// Deterministic property/invariant coverage for the pure Sprint 2 geometry seams.
///
/// The generator is deliberately tiny and local: changing the seed or its arithmetic is a
/// reviewable test change, and a failing case can be reproduced by its integer case index.
final class W2_11LayoutPropertyTests: XCTestCase {
    private let seed: UInt64 = 0x57211

    func testSeededDisplayLayoutWindowConfigurationsPreserveGeometryInvariants() throws {
        var generator = Generator(seed: seed)
        var testedConfigurations = 0

        for caseIndex in 0..<240 {
            let topology = makeTopology(caseIndex: caseIndex, generator: &generator)
            let display = topology.displays[caseIndex % topology.displays.count]
            let region = Layout.builtIn.regions[caseIndex % Layout.builtIn.regions.count]
            let constraints = makeConstraints(for: display, caseIndex: caseIndex, generator: &generator)
            let plan = try LayoutCalculator().plan(
                for: region,
                in: display,
                constraints: constraints
            )

            XCTAssertTrue(isFiniteNonEmpty(plan.frame), "case \(caseIndex)")
            XCTAssertTrue(contains(plan.frame, inside: display.visibleFrame), "case \(caseIndex)")

            let window = makeWindow(in: display, caseIndex: caseIndex, generator: &generator)
            let converter = try CoordinateConverter(
                topology: CoordinateSpaceTopology(topology)
            )
            let roundTripped = try converter.convert(
                try converter.convert(AppKitGlobalLogicalFrame(window))
            ).cgRect
            assertFrame(roundTripped, equals: window, caseIndex: caseIndex)

            let direction: DisplayMoveDirection = caseIndex.isMultiple(of: 2) ? .right : .left
            let planner = DisplayMovePlanner()
            let first = planner.plan(
                window: AppKitGlobalLogicalFrame(window),
                direction: direction,
                topology: topology,
                wrapPolicy: .wrap
            )
            let second = planner.plan(
                window: AppKitGlobalLogicalFrame(window),
                direction: direction,
                topology: topology,
                wrapPolicy: .wrap
            )
            XCTAssertEqual(first, second, "planning must be deterministic for case \(caseIndex)")
            let moved: DisplayMovePlan
            switch first {
            case .success(let plan):
                moved = plan
            case .failure(let failure):
                XCTFail("unexpected move failure \(failure), case \(caseIndex)")
                continue
            }
            XCTAssertTrue(isFiniteNonEmpty(moved.targetFrame.cgRect), "case \(caseIndex)")
            let destination = try XCTUnwrap(
                topology.displays.first(where: { $0.id == moved.destinationDisplayID })
            )
            XCTAssertTrue(
                contains(moved.targetFrame.cgRect, inside: destination.visibleFrame),
                "case \(caseIndex)"
            )
            testedConfigurations += 1
        }

        XCTAssertEqual(testedConfigurations, 240)
    }

    private func makeTopology(
        caseIndex: Int,
        generator: inout Generator
    ) -> DisplayTopologySnapshot {
        let verticalShift = CGFloat(generator.nextInt(in: -240...240))
        let primary = makeDisplay(
            id: 1,
            frame: CGRect(x: -1_600, y: -200 + verticalShift, width: 1_600, height: 1_000),
            visibleInsets: (left: 0, bottom: 24, right: 0, top: 32),
            scale: 1
        )
        let center = makeDisplay(
            id: 2,
            frame: CGRect(x: 0, y: verticalShift, width: 1_440, height: 900),
            visibleInsets: (left: 0, bottom: 20, right: 0, top: 28),
            scale: 2
        )
        let right = makeDisplay(
            id: 3,
            frame: CGRect(x: 1_440, y: 150 + verticalShift, width: 1_920, height: 1_080),
            visibleInsets: (left: 0, bottom: 18, right: 0, top: 30),
            scale: 1.25
        )
        // Reordering the input makes the topology's explicit identity, not array order, part of
        // every generated case while preserving the same mixed physical topology.
        let displays: [DisplaySnapshot] = caseIndex.isMultiple(of: 3)
            ? [right, primary, center]
            : (caseIndex.isMultiple(of: 2) ? [center, right, primary] : [primary, right, center])
        return DisplayTopologySnapshot(displays: displays, primaryDisplayID: center.id)
    }

    private func makeDisplay(
        id: UInt32,
        frame: CGRect,
        visibleInsets: (left: CGFloat, bottom: CGFloat, right: CGFloat, top: CGFloat),
        scale: CGFloat
    ) -> DisplaySnapshot {
        let visibleFrame = CGRect(
            x: frame.minX + visibleInsets.left,
            y: frame.minY + visibleInsets.bottom,
            width: frame.width - visibleInsets.left - visibleInsets.right,
            height: frame.height - visibleInsets.bottom - visibleInsets.top
        )
        return DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: visibleFrame,
            backingScaleFactor: scale,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: visibleInsets.top, left: visibleInsets.left, bottom: visibleInsets.bottom, right: visibleInsets.right),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            ),
            notchTrigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: frame.midX - 90, y: frame.maxY - 16, width: 180, height: 16)
            )
        )
    }

    private func makeWindow(
        in display: DisplaySnapshot,
        caseIndex: Int,
        generator: inout Generator
    ) -> CGRect {
        let widthFraction = CGFloat(12 + generator.nextInt(in: 0...20)) / 100
        let heightFraction = CGFloat(14 + generator.nextInt(in: 0...22)) / 100
        let width = display.visibleFrame.width * widthFraction
        let height = display.visibleFrame.height * heightFraction
        let xFraction = CGFloat((caseIndex * 37 + generator.nextInt(in: 0...100)) % 101) / 100
        let yFraction = CGFloat((caseIndex * 53 + generator.nextInt(in: 0...100)) % 101) / 100
        return CGRect(
            x: display.visibleFrame.minX + (display.visibleFrame.width - width) * xFraction,
            y: display.visibleFrame.minY + (display.visibleFrame.height - height) * yFraction,
            width: width,
            height: height
        )
    }

    private func makeConstraints(
        for display: DisplaySnapshot,
        caseIndex: Int,
        generator: inout Generator
    ) -> LayoutConstraints {
        let padding = CGFloat(generator.nextInt(in: 0...4))
        let gap = CGFloat(generator.nextInt(in: 0...8))
        let minimumSize: CGSize? = caseIndex.isMultiple(of: 5)
            ? CGSize(width: CGFloat(60 + generator.nextInt(in: 0...50)), height: CGFloat(60 + generator.nextInt(in: 0...50)))
            : nil
        _ = display
        return LayoutConstraints(
            outerPadding: LayoutEdgeInsets(top: padding, left: padding, bottom: padding, right: padding),
            gap: gap,
            minimumSize: minimumSize
        )
    }

    private func contains(_ frame: CGRect, inside visible: CGRect) -> Bool {
        frame.minX >= visible.minX - 0.000_001
            && frame.minY >= visible.minY - 0.000_001
            && frame.maxX <= visible.maxX + 0.000_001
            && frame.maxY <= visible.maxY + 0.000_001
    }

    private func isFiniteNonEmpty(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.maxX.isFinite && frame.maxY.isFinite && frame.width > 0 && frame.height > 0
    }

    private func assertFrame(
        _ actual: CGRect,
        equals expected: CGRect,
        caseIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.000_000_001, "case \(caseIndex)", file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.000_000_001, "case \(caseIndex)", file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.000_000_001, "case \(caseIndex)", file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.000_000_001, "case \(caseIndex)", file: file, line: line)
    }
}

private struct Generator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int((state >> 32) % span)
    }
}
