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

/// A stable identifier for one selectable region inside a Layout.
struct LayoutRegionID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension LayoutRegionID {
    static let maximize = Self(rawValue: "maximize")
    static let leftHalf = Self(rawValue: "left-half")
    static let rightHalf = Self(rawValue: "right-half")
    static let topHalf = Self(rawValue: "top-half")
    static let bottomHalf = Self(rawValue: "bottom-half")
    static let topLeftQuarter = Self(rawValue: "top-left-quarter")
    static let topRightQuarter = Self(rawValue: "top-right-quarter")
    static let bottomLeftQuarter = Self(rawValue: "bottom-left-quarter")
    static let bottomRightQuarter = Self(rawValue: "bottom-right-quarter")
}

/// A selectable normalized area of a Layout.
///
/// The normalized frame uses AppKit's bottom-left coordinate convention. Every component is
/// finite, the region is non-empty, and it lies wholly inside the unit rectangle.
struct LayoutRegion: Equatable, Sendable {
    let id: LayoutRegionID
    let normalizedFrame: CGRect

    init(id: LayoutRegionID, normalizedFrame: CGRect) throws {
        guard normalizedFrame.origin.x.isFinite,
              normalizedFrame.origin.y.isFinite,
              normalizedFrame.width.isFinite,
              normalizedFrame.height.isFinite
        else {
            throw LayoutValidationError.nonFiniteNormalizedFrame(id)
        }
        guard normalizedFrame.width > 0, normalizedFrame.height > 0 else {
            throw LayoutValidationError.emptyNormalizedFrame(id)
        }
        guard normalizedFrame.minX >= 0,
              normalizedFrame.minY >= 0,
              normalizedFrame.maxX <= 1,
              normalizedFrame.maxY <= 1
        else {
            throw LayoutValidationError.normalizedFrameOutsideUnitBounds(id)
        }

        self.id = id
        self.normalizedFrame = normalizedFrame
    }
}

/// A named arrangement of selectable Layout Regions.
struct Layout: Equatable, Sendable {
    let id: String
    let regions: [LayoutRegion]

    init(id: String, regions: [LayoutRegion]) throws {
        guard !id.isEmpty else {
            throw LayoutValidationError.emptyLayoutID
        }
        guard !regions.isEmpty else {
            throw LayoutValidationError.emptyLayout
        }

        var seenIDs = Set<LayoutRegionID>()
        for region in regions {
            guard seenIDs.insert(region.id).inserted else {
                throw LayoutValidationError.duplicateRegionID(region.id)
            }
        }

        self.id = id
        self.regions = regions
    }
}

extension Layout {
    /// The standard nine selectable regions used by the built-in window-placement actions.
    static let builtIn: Self = try! Self(
        id: "built-in",
        regions: [
            try! LayoutRegion(
                id: .maximize,
                normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 1)
            ),
            try! LayoutRegion(
                id: .leftHalf,
                normalizedFrame: CGRect(x: 0, y: 0, width: 0.5, height: 1)
            ),
            try! LayoutRegion(
                id: .rightHalf,
                normalizedFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
            ),
            try! LayoutRegion(
                id: .topHalf,
                normalizedFrame: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
            ),
            try! LayoutRegion(
                id: .bottomHalf,
                normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 0.5)
            ),
            try! LayoutRegion(
                id: .topLeftQuarter,
                normalizedFrame: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
            ),
            try! LayoutRegion(
                id: .topRightQuarter,
                normalizedFrame: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            ),
            try! LayoutRegion(
                id: .bottomLeftQuarter,
                normalizedFrame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
            ),
            try! LayoutRegion(
                id: .bottomRightQuarter,
                normalizedFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
            ),
        ]
    )
}

enum LayoutValidationError: Error, Equatable, Sendable {
    case emptyLayoutID
    case emptyLayout
    case duplicateRegionID(LayoutRegionID)
    case nonFiniteNormalizedFrame(LayoutRegionID)
    case emptyNormalizedFrame(LayoutRegionID)
    case normalizedFrameOutsideUnitBounds(LayoutRegionID)
}
