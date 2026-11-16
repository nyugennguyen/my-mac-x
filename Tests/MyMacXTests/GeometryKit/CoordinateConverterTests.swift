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

final class CoordinateConverterTests: XCTestCase {
    func testConvertsCanonicalAppKitFrameToAXTopLeftFrameUsingPrimaryDisplay() throws {
        let converter = try CoordinateConverter(
            topology: CoordinateSpaceTopology(DisplayTopologySnapshot(
                displays: [display(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))],
                primaryDisplayID: DisplayID(rawValue: 1)
            ))
        )

        let converted = try converter.convert(
            AppKitGlobalLogicalFrame(CGRect(x: 100, y: 100, width: 400, height: 300))
        )

        XCTAssertEqual(
            converted,
            AXGlobalTopLeftFrame(CGRect(x: 100, y: 500, width: 400, height: 300))
        )
    }

    func testConvertsAXTopLeftFrameBackToCanonicalAppKitFrame() throws {
        let converter = try CoordinateConverter(
            topology: CoordinateSpaceTopology(DisplayTopologySnapshot(
                displays: [display(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))],
                primaryDisplayID: DisplayID(rawValue: 1)
            ))
        )

        let converted = try converter.convert(
            AXGlobalTopLeftFrame(CGRect(x: 100, y: 500, width: 400, height: 300))
        )

        XCTAssertEqual(
            converted,
            AppKitGlobalLogicalFrame(CGRect(x: 100, y: 100, width: 400, height: 300))
        )
    }

    func testRejectsInvalidAppKitInputFrames() throws {
        let converter = try validConverter()
        let invalidFrames = [
            CGRect(x: CGFloat.infinity, y: 0, width: 400, height: 300),
            CGRect(x: 0, y: CGFloat.nan, width: 400, height: 300),
            CGRect(x: 0, y: 0, width: 0, height: 300),
            CGRect(x: 0, y: 0, width: 400, height: -1),
        ]

        for frame in invalidFrames {
            XCTAssertThrowsError(
                try converter.convert(AppKitGlobalLogicalFrame(frame))
            ) { error in
                XCTAssertEqual(
                    error as? CoordinateConversionFailure,
                    .invalidAppKitFrame
                )
            }
        }
    }

    func testRejectsInvalidAXInputFrames() throws {
        let converter = try validConverter()
        let invalidFrames = [
            CGRect(x: CGFloat.nan, y: 0, width: 400, height: 300),
            CGRect(x: 0, y: CGFloat.infinity, width: 400, height: 300),
            CGRect(x: 0, y: 0, width: -1, height: 300),
            CGRect(x: 0, y: 0, width: 400, height: 0),
        ]

        for frame in invalidFrames {
            XCTAssertThrowsError(
                try converter.convert(AXGlobalTopLeftFrame(frame))
            ) { error in
                XCTAssertEqual(
                    error as? CoordinateConversionFailure,
                    .invalidAXFrame
                )
            }
        }
    }

    func testRejectsFiniteInputsWhoseConversionWouldOverflow() throws {
        let negativePrimary = try CoordinateConverter(
            topology: CoordinateSpaceTopology(DisplayTopologySnapshot(
                displays: [
                    display(
                        id: 10,
                        frame: CGRect(
                            x: -CGFloat.greatestFiniteMagnitude,
                            y: 0,
                            width: 1,
                            height: 900
                        )
                    ),
                ],
                primaryDisplayID: DisplayID(rawValue: 10)
            ))
        )

        XCTAssertThrowsError(
            try negativePrimary.convert(
                AppKitGlobalLogicalFrame(CGRect(
                    x: CGFloat.greatestFiniteMagnitude,
                    y: 0,
                    width: 1,
                    height: 1
                ))
            )
        ) { error in
            XCTAssertEqual(error as? CoordinateConversionFailure, .conversionOverflow)
        }
    }

    func testUsesOneLogicalPointSpaceAcrossMixedScaleDisplaysInEveryDirection() throws {
        let converter = try CoordinateConverter(topology: mixedScaleTopology())
        let examples: [(appKit: CGRect, ax: CGRect)] = [
            (
                CGRect(x: -1800, y: 200, width: 640, height: 480),
                CGRect(x: -1800, y: 220, width: 640, height: 480)
            ),
            (
                CGRect(x: 1700, y: 250, width: 800, height: 600),
                CGRect(x: 1700, y: 50, width: 800, height: 600)
            ),
            (
                CGRect(x: 300, y: 1050, width: 500, height: 300),
                CGRect(x: 300, y: -450, width: 500, height: 300)
            ),
            (
                CGRect(x: 300, y: -950, width: 500, height: 400),
                CGRect(x: 300, y: 1450, width: 500, height: 400)
            ),
        ]

        for example in examples {
            XCTAssertEqual(
                try converter.convert(AppKitGlobalLogicalFrame(example.appKit)),
                AXGlobalTopLeftFrame(example.ax)
            )
            XCTAssertEqual(
                try converter.convert(AXGlobalTopLeftFrame(example.ax)),
                AppKitGlobalLogicalFrame(example.appKit)
            )
        }
    }

    func testRoundTripsMoreThanTwoHundredDeterministicFramesAcrossMixedScaleTopology() throws {
        let topology = mixedScaleTopology()
        let converter = try CoordinateConverter(topology: topology)

        for index in 0..<320 {
            let display = topology.displays[index % topology.displays.count]
            let widthFraction = CGFloat((index % 7) + 1) / 10
            let heightFraction = CGFloat((index % 5) + 1) / 8
            let width = display.frame.width * widthFraction
            let height = display.frame.height * heightFraction
            let horizontalPosition = CGFloat((index * 37) % 101) / 100
            let verticalPosition = CGFloat((index * 53) % 101) / 100
            let original = CGRect(
                x: display.frame.minX + (display.frame.width - width) * horizontalPosition,
                y: display.frame.minY + (display.frame.height - height) * verticalPosition,
                width: width,
                height: height
            )

            let axFrame = try converter.convert(AppKitGlobalLogicalFrame(original))
            let roundTripped = try converter.convert(axFrame).cgRect

            assertFrame(roundTripped, equals: original, accuracy: 0.000_000_001)
        }
    }

    private func display(
        id: UInt32,
        frame: CGRect,
        backingScaleFactor: CGFloat = 1
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: frame,
            backingScaleFactor: backingScaleFactor,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
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

    private func validConverter() throws -> CoordinateConverter {
        try CoordinateConverter(
            topology: CoordinateSpaceTopology(DisplayTopologySnapshot(
                displays: [display(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))],
                primaryDisplayID: DisplayID(rawValue: 1)
            ))
        )
    }

    private func mixedScaleTopology() -> CoordinateSpaceTopology {
        CoordinateSpaceTopology(DisplayTopologySnapshot(
            displays: [
                display(
                    id: 2,
                    frame: CGRect(x: -1920, y: -120, width: 1920, height: 1080),
                    backingScaleFactor: 1
                ),
                display(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                    backingScaleFactor: 2
                ),
                display(
                    id: 3,
                    frame: CGRect(x: 1440, y: 180, width: 2560, height: 1440),
                    backingScaleFactor: 1.25
                ),
                display(
                    id: 4,
                    frame: CGRect(x: 100, y: 900, width: 1200, height: 800),
                    backingScaleFactor: 1.5
                ),
                display(
                    id: 5,
                    frame: CGRect(x: -200, y: -1200, width: 1920, height: 1200),
                    backingScaleFactor: 2.5
                ),
            ],
            primaryDisplayID: DisplayID(rawValue: 1)
        ))
    }

    private func assertFrame(
        _ actual: CGRect,
        equals expected: CGRect,
        accuracy: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.origin.x,
            expected.origin.x,
            accuracy: accuracy,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.origin.y,
            expected.origin.y,
            accuracy: accuracy,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.width,
            expected.width,
            accuracy: accuracy,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.height,
            expected.height,
            accuracy: accuracy,
            file: file,
            line: line
        )
    }
}
