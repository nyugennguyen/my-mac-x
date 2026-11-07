import CoreGraphics
import Foundation

/// Pure geometric acceptance policy implementing A-01 through A-05 semantics.
///
/// Many macOS applications (such as Terminal, Finder, Settings, Calculator) enforce minimum size limits
/// or grid-stepped dimensions. Demanding exact frame equality causes clamped-but-placed windows to be
/// erroneously rolled back. This policy confirms placement intent based on edge anchoring, span ratios,
/// and minimum overlap floors.
public struct EdgeSnapAcceptancePolicy: Sendable {
    public static let minimumWindowSize: CGFloat = 80.0
    public static let anchorTolerance: CGFloat = 36.0
    public static let precisionTolerance: CGFloat = 8.0
    public static let defaultSpanRatio: CGFloat = 0.82
    public static let halfAndThirdOverlapFloor: CGFloat = 0.45
    public static let cornerAndSixthOverlapFloor: CGFloat = 0.35
    public static let maximizeOverlapFloor: CGFloat = 0.90
    public static let marginMaximizeOverlapFloor: CGFloat = 0.82
    public static let displayTransferOverlapFloor: CGFloat = 0.72

    public init() {}

    /// Determines whether the read-back `actualRect` satisfies the requested `targetRect` for `action`.
    public func accepts(
        actualRect: CGRect,
        targetRect: CGRect,
        action: ActionID,
        anchorTolerance: CGFloat = EdgeSnapAcceptancePolicy.anchorTolerance
    ) -> Bool {
        // A-01: Minimum window dimension guard (80x80 pt floor)
        guard actualRect.width > Self.minimumWindowSize, actualRect.height > Self.minimumWindowSize else {
            return false
        }

        // A-04: Strict frame tolerance for precision actions (8 pt threshold)
        if isClose(actual: actualRect, target: targetRect, tolerance: Self.precisionTolerance) {
            return true
        }

        // Disallowed / non-geometric actions (A-03)
        if action == .restore || action == .nativeFullScreen {
            return false
        }

        let intersection = actualRect.intersection(targetRect)
        let targetArea = targetRect.width * targetRect.height
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let overlap = targetArea > 0 ? (intersectionArea / targetArea) : 0

        // A-03: Maximize family
        if action == .maximize {
            return overlap >= Self.maximizeOverlapFloor
        }

        if action.rawValue == "window.margin-maximize" {
            let midXClose = abs(actualRect.midX - targetRect.midX) <= anchorTolerance
            let midYClose = abs(actualRect.midY - targetRect.midY) <= anchorTolerance
            return midXClose && midYClose && overlap >= Self.marginMaximizeOverlapFloor
        }

        if action.rawValue == "window.center" {
            let midXClose = abs(actualRect.midX - targetRect.midX) <= anchorTolerance
            let midYClose = abs(actualRect.midY - targetRect.midY) <= anchorTolerance
            return midXClose && midYClose
        }

        if action == .moveDisplayPrevious || action == .moveDisplayNext {
            return overlap >= Self.displayTransferOverlapFloor
        }

        // A-02: Corner quadrants & sixths (35% overlap floor + both corner edges anchored)
        if isCornerOrSixth(action) {
            guard overlap >= Self.cornerAndSixthOverlapFloor else { return false }
            return cornerEdgesAnchored(
                actual: actualRect,
                target: targetRect,
                action: action,
                tolerance: anchorTolerance
            )
        }

        // A-01: Side halves, thirds, and quarter partitions (45% overlap floor + outer edge anchored + full cross span)
        guard overlap >= Self.halfAndThirdOverlapFloor else { return false }
        return edgeAndSpanAnchored(
            actual: actualRect,
            target: targetRect,
            action: action,
            tolerance: anchorTolerance
        )
    }

    // MARK: - Private Helpers

    private func isClose(actual: CGRect, target: CGRect, tolerance: CGFloat) -> Bool {
        abs(actual.origin.x - target.origin.x) <= tolerance &&
        abs(actual.origin.y - target.origin.y) <= tolerance &&
        abs(actual.width - target.width) <= tolerance &&
        abs(actual.height - target.height) <= tolerance
    }

    private func isCornerOrSixth(_ action: ActionID) -> Bool {
        let corners: Set<ActionID> = [
            .topLeftQuarter,
            .topRightQuarter,
            .bottomLeftQuarter,
            .bottomRightQuarter,
            ActionID(rawValue: "window.top-left-sixth"),
            ActionID(rawValue: "window.top-center-sixth"),
            ActionID(rawValue: "window.top-right-sixth"),
            ActionID(rawValue: "window.bottom-left-sixth"),
            ActionID(rawValue: "window.bottom-center-sixth"),
            ActionID(rawValue: "window.bottom-right-sixth")
        ]
        return corners.contains(action)
    }

    private func cornerEdgesAnchored(
        actual: CGRect,
        target: CGRect,
        action: ActionID,
        tolerance: CGFloat
    ) -> Bool {
        let leftAnchored = abs(actual.minX - target.minX) <= tolerance
        let rightAnchored = abs(actual.maxX - target.maxX) <= tolerance
        let bottomAnchored = abs(actual.minY - target.minY) <= tolerance
        let topAnchored = abs(actual.maxY - target.maxY) <= tolerance

        switch action {
        case .topLeftQuarter, ActionID(rawValue: "window.top-left-sixth"):
            return leftAnchored && topAnchored
        case .topRightQuarter, ActionID(rawValue: "window.top-right-sixth"):
            return rightAnchored && topAnchored
        case .bottomLeftQuarter, ActionID(rawValue: "window.bottom-left-sixth"):
            return leftAnchored && bottomAnchored
        case .bottomRightQuarter, ActionID(rawValue: "window.bottom-right-sixth"):
            return rightAnchored && bottomAnchored
        case ActionID(rawValue: "window.top-center-sixth"):
            return topAnchored
        case ActionID(rawValue: "window.bottom-center-sixth"):
            return bottomAnchored
        default:
            return false
        }
    }

    private func edgeAndSpanAnchored(
        actual: CGRect,
        target: CGRect,
        action: ActionID,
        tolerance: CGFloat
    ) -> Bool {
        let isVertical = isVerticalAction(action)

        if isVertical {
            // Horizontal split (spans full width or both left/right align, outer vertical edge anchored)
            let spansWidth = actual.width >= target.width * Self.defaultSpanRatio ||
                (abs(actual.minX - target.minX) <= tolerance && abs(actual.maxX - target.maxX) <= tolerance)

            guard spansWidth else { return false }

            if action == .topHalf || action.rawValue.contains("top") {
                return abs(actual.maxY - target.maxY) <= tolerance
            } else {
                return abs(actual.minY - target.minY) <= tolerance
            }
        } else {
            // Vertical split (spans full height or both top/bottom align, outer horizontal edge anchored)
            let spansHeight = actual.height >= target.height * Self.defaultSpanRatio ||
                (abs(actual.minY - target.minY) <= tolerance && abs(actual.maxY - target.maxY) <= tolerance)

            guard spansHeight else { return false }

            if action == .leftHalf || action == .leftThird || action == .leftTwoThirds || action.rawValue.contains("left") {
                return abs(actual.minX - target.minX) <= tolerance
            } else if action == .rightHalf || action.rawValue.contains("right") {
                return abs(actual.maxX - target.maxX) <= tolerance
            } else {
                // Center columns
                return abs(actual.midX - target.midX) <= tolerance
            }
        }
    }

    private func isVerticalAction(_ action: ActionID) -> Bool {
        let verticalActions: Set<ActionID> = [
            .topHalf,
            .bottomHalf,
            ActionID(rawValue: "window.top-third"),
            ActionID(rawValue: "window.middle-third"),
            ActionID(rawValue: "window.bottom-third"),
            ActionID(rawValue: "window.top-two-thirds"),
            ActionID(rawValue: "window.bottom-two-thirds"),
            ActionID(rawValue: "window.top-quarter"),
            ActionID(rawValue: "window.upper-middle-quarter"),
            ActionID(rawValue: "window.lower-middle-quarter"),
            ActionID(rawValue: "window.bottom-quarter")
        ]
        return verticalActions.contains(action)
    }
}
