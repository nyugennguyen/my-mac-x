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

/// Coordinate context derived from ScreenKit's atomic Display topology.
///
/// The only initializer accepts `DisplayTopologySnapshot`; free-form display arrays and sorted
/// order cannot establish primary status at this seam.
struct CoordinateSpaceTopology: Equatable, Sendable {
    let displays: [DisplaySnapshot]
    let primaryDisplayID: DisplayID

    init(_ topology: DisplayTopologySnapshot) {
        displays = topology.displays
        primaryDisplayID = topology.primaryDisplayID
    }
}

/// A rectangle in AppKit's global, unflipped screen coordinate space, expressed in points.
struct AppKitGlobalLogicalFrame: Equatable, Sendable {
    let cgRect: CGRect

    init(_ cgRect: CGRect) {
        self.cgRect = cgRect
    }
}

/// A rectangle in Accessibility's global, top-left-origin coordinate space, expressed in points.
struct AXGlobalTopLeftFrame: Equatable, Sendable {
    let cgRect: CGRect

    init(_ cgRect: CGRect) {
        self.cgRect = cgRect
    }
}

enum CoordinateConversionFailure: Error, Equatable, Sendable {
    case emptyTopology
    case duplicateDisplayIdentity(DisplayID)
    case invalidDisplayFrame(DisplayID)
    case invalidBackingScale(DisplayID)
    case primaryDisplayUnavailable(DisplayID)
    case invalidAppKitFrame
    case invalidAXFrame
    case conversionOverflow
}

/// Pure conversion between AppKit and Accessibility global logical frames.
///
/// For primary Display frame `P`, AppKit frame `A`, and AX frame `X`:
///
/// - AppKit to AX: `X.x = A.minX - P.minX`, `X.y = P.maxY - A.maxY`
/// - AX to AppKit: `A.x = X.minX + P.minX`, `A.y = P.maxY - X.maxY`
/// - Width and height are unchanged in both directions.
///
/// Both coordinate systems use logical points. Backing scales are validated as part of the
/// atomic topology but are deliberately absent from the formula.
struct CoordinateConverter: Sendable {
    private let primaryFrame: CGRect

    init(
        topology: CoordinateSpaceTopology
    ) throws(CoordinateConversionFailure) {
        guard !topology.displays.isEmpty else {
            throw CoordinateConversionFailure.emptyTopology
        }
        var displayIDs: Set<DisplayID> = []
        for display in topology.displays where !displayIDs.insert(display.id).inserted {
            throw CoordinateConversionFailure.duplicateDisplayIdentity(display.id)
        }
        for display in topology.displays where !Self.isValidFrame(display.frame) {
            throw CoordinateConversionFailure.invalidDisplayFrame(display.id)
        }
        for display in topology.displays
        where !display.backingScaleFactor.isFinite || display.backingScaleFactor <= 0 {
            throw CoordinateConversionFailure.invalidBackingScale(display.id)
        }
        guard let primaryDisplay = topology.displays.first(where: {
            $0.id == topology.primaryDisplayID
        }) else {
            throw CoordinateConversionFailure.primaryDisplayUnavailable(
                topology.primaryDisplayID
            )
        }
        primaryFrame = primaryDisplay.frame
    }

    func convert(
        _ frame: AppKitGlobalLogicalFrame
    ) throws(CoordinateConversionFailure) -> AXGlobalTopLeftFrame {
        let source = frame.cgRect
        guard Self.isValidFrame(source) else {
            throw CoordinateConversionFailure.invalidAppKitFrame
        }
        let converted = CGRect(
            x: source.minX - primaryFrame.minX,
            y: primaryFrame.maxY - source.maxY,
            width: source.width,
            height: source.height
        )
        guard Self.isValidFrame(converted) else {
            throw CoordinateConversionFailure.conversionOverflow
        }
        return AXGlobalTopLeftFrame(converted)
    }

    func convert(
        _ frame: AXGlobalTopLeftFrame
    ) throws(CoordinateConversionFailure) -> AppKitGlobalLogicalFrame {
        let source = frame.cgRect
        guard Self.isValidFrame(source) else {
            throw CoordinateConversionFailure.invalidAXFrame
        }
        let converted = CGRect(
            x: source.minX + primaryFrame.minX,
            y: primaryFrame.maxY - source.maxY,
            width: source.width,
            height: source.height
        )
        guard Self.isValidFrame(converted) else {
            throw CoordinateConversionFailure.conversionOverflow
        }
        return AppKitGlobalLogicalFrame(converted)
    }

    private static func isValidFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.size.width > 0
            && frame.size.height > 0
            && frame.maxX.isFinite
            && frame.maxY.isFinite
    }
}
