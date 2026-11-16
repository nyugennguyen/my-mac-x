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

/// Insets applied only where a Layout Region meets an outer edge of the visible frame.
struct LayoutEdgeInsets: Equatable, Sendable {
    let top: CGFloat
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat

    init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    static let zero = Self(top: 0, left: 0, bottom: 0, right: 0)
}

/// The configurable pure constraints applied to a normalized Layout Region.
struct LayoutConstraints: Equatable, Sendable {
    let outerPadding: LayoutEdgeInsets
    let gap: CGFloat
    let minimumSize: CGSize?

    init(
        outerPadding: LayoutEdgeInsets = .zero,
        gap: CGFloat = 0,
        minimumSize: CGSize? = nil
    ) {
        self.outerPadding = outerPadding
        self.gap = gap
        self.minimumSize = minimumSize
    }

    static let `default` = Self()
}

/// Observable adjustments made while fitting a Layout Region into a Display's usable area.
enum LayoutConstraintWarning: Equatable, Sendable {
    case minimumSizeAccommodated
    case visibleFrameClamped
}

/// The completed pure plan for placing one Layout Region.
struct LayoutFramePlan: Equatable, Sendable {
    let frame: CGRect
    let warnings: [LayoutConstraintWarning]

    var isConstrained: Bool {
        !warnings.isEmpty
    }
}

/// Failures that cannot produce a non-empty target wholly inside the visible frame.
enum LayoutConstraintFailure: Error, Equatable, Sendable {
    case invalidVisibleFrame
    case invalidBackingScale
    case nonFiniteOuterPadding
    case negativeOuterPadding
    case nonFiniteGap
    case negativeGap
    case invalidMinimumSize
    case outerPaddingEliminatesVisibleFrame
    case gapEliminatesLayoutRegion
    case roundingEliminatesLayoutRegion
    case minimumSizeExceedsVisibleFrame
}

/// Pure deterministic mapping from a normalized Layout Region into one Display's usable area.
struct LayoutCalculator: Sendable {
    init() {}

    /// Returns a canonical global AppKit logical frame inside `display.visibleFrame`.
    ///
    /// Configuration-free mapping used by `plan` before constraints are applied.
    func frame(for region: LayoutRegion, in display: DisplaySnapshot) -> CGRect {
        let visibleFrame = display.visibleFrame
        let normalizedFrame = region.normalizedFrame

        return CGRect(
            x: visibleFrame.minX + visibleFrame.width * normalizedFrame.minX,
            y: visibleFrame.minY + visibleFrame.height * normalizedFrame.minY,
            width: visibleFrame.width * normalizedFrame.width,
            height: visibleFrame.height * normalizedFrame.height
        )
    }

    /// Produces the final target frame for a Layout Region without mutating a window.
    ///
    /// The calculation order is fixed: normalized frame, outer-edge padding and interior
    /// half-gaps, backing-scale edge rounding, minimum-size accommodation, then a final
    /// visible-frame clamp. A warning records only accommodation or the final safety clamp;
    /// configured padding and gaps are intentional layout choices rather than warnings.
    func plan(
        for region: LayoutRegion,
        in display: DisplaySnapshot,
        constraints: LayoutConstraints = .default
    ) throws(LayoutConstraintFailure) -> LayoutFramePlan {
        let visibleFrame = display.visibleFrame
        guard Self.isValidNonEmptyFrame(visibleFrame) else {
            throw .invalidVisibleFrame
        }
        guard display.backingScaleFactor.isFinite, display.backingScaleFactor > 0 else {
            throw .invalidBackingScale
        }
        try validate(constraints)

        let normalizedFrame = frame(for: region, in: display)
        let leadingInset = horizontalLeadingInset(for: region, constraints: constraints)
        let trailingInset = horizontalTrailingInset(for: region, constraints: constraints)
        let bottomInset = verticalLeadingInset(for: region, constraints: constraints)
        let topInset = verticalTrailingInset(for: region, constraints: constraints)
        let width = normalizedFrame.width - leadingInset - trailingInset
        let height = normalizedFrame.height - bottomInset - topInset
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            let outerPaddingWasApplied = (region.normalizedFrame.minX == 0
                && constraints.outerPadding.left > 0)
                || (region.normalizedFrame.maxX == 1 && constraints.outerPadding.right > 0)
                || (region.normalizedFrame.minY == 0 && constraints.outerPadding.bottom > 0)
                || (region.normalizedFrame.maxY == 1 && constraints.outerPadding.top > 0)
            throw outerPaddingWasApplied
                ? .outerPaddingEliminatesVisibleFrame
                : .gapEliminatesLayoutRegion
        }
        let insetFrame = CGRect(
            x: normalizedFrame.minX + leadingInset,
            y: normalizedFrame.minY + bottomInset,
            width: width,
            height: height
        )
        guard Self.isValidNonEmptyFrame(insetFrame) else {
            throw .gapEliminatesLayoutRegion
        }

        var warnings: [LayoutConstraintWarning] = []
        var target = DisplayFrameFitter.roundedToBackingEdges(
            insetFrame,
            relativeTo: display.frame.origin,
            scale: display.backingScaleFactor
        )
        guard Self.isValidNonEmptyFrame(target) else {
            throw .roundingEliminatesLayoutRegion
        }

        if let minimumSize = constraints.minimumSize,
           target.width < minimumSize.width || target.height < minimumSize.height {
            guard minimumSize.width <= visibleFrame.width,
                  minimumSize.height <= visibleFrame.height
            else {
                throw .minimumSizeExceedsVisibleFrame
            }
            target = accommodated(target, minimumSize: minimumSize, inside: visibleFrame)
            warnings.append(.minimumSizeAccommodated)
        }

        let clamped = DisplayFrameFitter.clamp(target, inside: visibleFrame)
        if !DisplayFrameFitter.framesApproximatelyEqual(clamped, target) {
            warnings.append(.visibleFrameClamped)
        }
        guard Self.isValidNonEmptyFrame(clamped) else {
            throw .roundingEliminatesLayoutRegion
        }

        return LayoutFramePlan(frame: clamped, warnings: warnings)
    }

    private func validate(_ constraints: LayoutConstraints) throws(LayoutConstraintFailure) {
        let padding = constraints.outerPadding
        let paddingValues = [padding.top, padding.left, padding.bottom, padding.right]
        guard paddingValues.allSatisfy(\.isFinite) else {
            throw .nonFiniteOuterPadding
        }
        guard paddingValues.allSatisfy({ $0 >= 0 }) else {
            throw .negativeOuterPadding
        }
        guard constraints.gap.isFinite else {
            throw .nonFiniteGap
        }
        guard constraints.gap >= 0 else {
            throw .negativeGap
        }
        if let minimumSize = constraints.minimumSize {
            guard minimumSize.width.isFinite,
                  minimumSize.height.isFinite,
                  minimumSize.width > 0,
                  minimumSize.height > 0
            else {
                throw .invalidMinimumSize
            }
        }
    }

    private func horizontalLeadingInset(
        for region: LayoutRegion,
        constraints: LayoutConstraints
    ) -> CGFloat {
        region.normalizedFrame.minX == 0 ? constraints.outerPadding.left : constraints.gap / 2
    }

    private func horizontalTrailingInset(
        for region: LayoutRegion,
        constraints: LayoutConstraints
    ) -> CGFloat {
        region.normalizedFrame.maxX == 1 ? constraints.outerPadding.right : constraints.gap / 2
    }

    private func verticalLeadingInset(
        for region: LayoutRegion,
        constraints: LayoutConstraints
    ) -> CGFloat {
        region.normalizedFrame.minY == 0 ? constraints.outerPadding.bottom : constraints.gap / 2
    }

    private func verticalTrailingInset(
        for region: LayoutRegion,
        constraints: LayoutConstraints
    ) -> CGFloat {
        region.normalizedFrame.maxY == 1 ? constraints.outerPadding.top : constraints.gap / 2
    }

    private func accommodated(_ frame: CGRect, minimumSize: CGSize, inside visibleFrame: CGRect) -> CGRect {
        let width = max(frame.width, minimumSize.width)
        let height = max(frame.height, minimumSize.height)
        let centered = CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
        return CGRect(
            x: min(max(centered.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(centered.minY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }

    private static func isValidNonEmptyFrame(_ frame: CGRect) -> Bool {
        frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
            && frame.maxX.isFinite
            && frame.maxY.isFinite
    }

}

/// Shared pixel-edge fitting policy for every pure placement planner.
enum DisplayFrameFitter {
    static func roundedToBackingEdges(
        _ frame: CGRect,
        relativeTo displayOrigin: CGPoint,
        scale: CGFloat
    ) -> CGRect {
        let minX = displayOrigin.x + ((frame.minX - displayOrigin.x) * scale).rounded() / scale
        let minY = displayOrigin.y + ((frame.minY - displayOrigin.y) * scale).rounded() / scale
        let maxX = displayOrigin.x + ((frame.maxX - displayOrigin.x) * scale).rounded() / scale
        let maxY = displayOrigin.y + ((frame.maxY - displayOrigin.y) * scale).rounded() / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func clamp(_ frame: CGRect, inside visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }

    static func framesApproximatelyEqual(_ left: CGRect, _ right: CGRect) -> Bool {
        abs(left.minX - right.minX) <= 0.000_001
            && abs(left.minY - right.minY) <= 0.000_001
            && abs(left.width - right.width) <= 0.000_001
            && abs(left.height - right.height) <= 0.000_001
    }
}
