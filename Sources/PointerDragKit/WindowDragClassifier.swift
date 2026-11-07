import CoreGraphics

/// Classification result for one window drag sample (D-01 to D-07).
public enum WindowDragClassification: Equatable, Sendable {
    /// Window motion is below the 2 pt floor or content drag inside the app (D-01, D-04).
    case waiting
    /// Confirmed authentic window move with aligned cosine and valid distance ratio (D-02, D-03, D-07).
    case moving
    /// Native window resize detected at press time or via perpendicular edge anchoring (D-05, D-06).
    case resizing
    /// Motion vector does not match pointer direction or distance ratio (D-01, D-02, D-03).
    case unrelated
}

/// State of an active window drag evaluated across consecutive samples (D-08).
public enum WindowDragState: Equatable, Sendable {
    case waiting
    case moving
    case cancelled
}

/// Pure rule engine for authentic window drag classification (D-01 to D-07).
///
/// Features:
/// - 2 pt motion floor for window and pointer (D-01, D-04).
/// - Cosine directional vector alignment >= 0.6 (~53 deg) (D-02).
/// - Distance travel ratio bounds [0.2, 1.8] (D-03).
/// - Native resize handle rejection at press-time (12 pt corners, 5 pt edges) (D-05).
/// - Mid-drag perpendicular edge-anchoring resize rejection (D-06).
/// - Restoration resize exception for un-snapping drags (D-07).
public struct WindowDragClassifier: Sendable {
    public static let movementThreshold: CGFloat = 2.0
    public static let cosineThreshold: CGFloat = 0.6
    public static let minTravelRatio: CGFloat = 0.2
    public static let maxTravelRatio: CGFloat = 1.8
    public static let resizeCornerDistance: CGFloat = 12.0
    public static let resizeEdgeDistance: CGFloat = 5.0

    public init() {}

    /// Pure classification function over press point, initial window frame, current window frame, and pointer delta vector.
    public func classify(
        pressPoint: CGPoint,
        initialFrame: CGRect,
        currentFrame: CGRect,
        pointerDelta: CGVector
    ) -> WindowDragClassification {
        // D-05: Press-time resize handle rejection
        if Self.startsAtResizeHandle(pressPoint, in: initialFrame) {
            return .resizing
        }

        // D-06: Mid-drag perpendicular edge-anchoring resize rejection
        let sizeChanged = abs(currentFrame.width - initialFrame.width) > Self.movementThreshold ||
                          abs(currentFrame.height - initialFrame.height) > Self.movementThreshold

        if sizeChanged && Self.sharesPerpendicularEdges(currentFrame, with: initialFrame) {
            return .resizing
        }

        let dwX = currentFrame.minX - initialFrame.minX
        let dwY = currentFrame.minY - initialFrame.minY
        let dw = hypot(dwX, dwY)
        let dp = hypot(pointerDelta.dx, pointerDelta.dy)

        // D-01 & D-04: Motion floor (2 pt)
        if dw <= Self.movementThreshold {
            return .waiting
        }
        if dp <= Self.movementThreshold {
            return .unrelated
        }

        // D-02: Cosine directional alignment >= 0.6
        let dotProduct = dwX * pointerDelta.dx + dwY * pointerDelta.dy
        let cosTheta = dotProduct / (dw * dp)
        if cosTheta < Self.cosineThreshold {
            return .unrelated
        }

        // D-03: Travel distance ratio bounds [0.2, 1.8]
        let ratio = dw / dp
        if ratio < Self.minTravelRatio || ratio > Self.maxTravelRatio {
            return .unrelated
        }

        return .moving
    }

    /// Tests if press point falls within native resize bands (D-05).
    public static func startsAtResizeHandle(_ point: CGPoint, in frame: CGRect) -> Bool {
        // Corner check: within 12 pt of any window corner
        let nearLeftCorner = abs(point.x - frame.minX) <= resizeCornerDistance
        let nearRightCorner = abs(point.x - frame.maxX) <= resizeCornerDistance
        let nearBottomCorner = abs(point.y - frame.minY) <= resizeCornerDistance
        let nearTopCorner = abs(point.y - frame.maxY) <= resizeCornerDistance

        if (nearLeftCorner || nearRightCorner) && (nearBottomCorner || nearTopCorner) {
            return true
        }

        // Edge check: within 5 pt of any window edge, constrained to the window span on the orthogonal axis
        let withinY = point.y >= frame.minY && point.y <= frame.maxY
        let withinX = point.x >= frame.minX && point.x <= frame.maxX

        let nearLeftEdge = abs(point.x - frame.minX) <= resizeEdgeDistance && withinY
        let nearRightEdge = abs(point.x - frame.maxX) <= resizeEdgeDistance && withinY
        let nearBottomEdge = abs(point.y - frame.minY) <= resizeEdgeDistance && withinX
        let nearTopEdge = abs(point.y - frame.maxY) <= resizeEdgeDistance && withinX

        if nearLeftEdge || nearRightEdge || nearBottomEdge || nearTopEdge {
            return true
        }

        return false
    }

    /// Tests if current frame shares perpendicular anchored edges with initial frame (D-06).
    public static func sharesPerpendicularEdges(_ current: CGRect, with initial: CGRect) -> Bool {
        let sharesVerticalEdge = abs(current.minX - initial.minX) <= movementThreshold ||
                                 abs(current.maxX - initial.maxX) <= movementThreshold
        let sharesHorizontalEdge = abs(current.minY - initial.minY) <= movementThreshold ||
                                   abs(current.maxY - initial.maxY) <= movementThreshold
        return sharesVerticalEdge && sharesHorizontalEdge
    }
}

/// Multi-strike filter providing tolerance for temporary window-server mismatches (D-08).
///
/// Cancels tracking only after 3 consecutive .unrelated evaluations.
/// A single .moving resets the counter to 0.
public struct WindowDragFilter: Equatable, Sendable {
    public static let maxConsecutiveMismatches = 3

    public private(set) var mismatchCount: Int = 0
    public private(set) var isConfirmedMoving: Bool = false
    public private(set) var isCancelled: Bool = false

    public init() {}

    public mutating func update(with classification: WindowDragClassification) -> WindowDragState {
        switch classification {
        case .moving:
            mismatchCount = 0
            isConfirmedMoving = true
            return .moving

        case .waiting:
            return isConfirmedMoving ? .moving : .waiting

        case .resizing:
            isCancelled = true
            return .cancelled

        case .unrelated:
            mismatchCount += 1
            if mismatchCount >= Self.maxConsecutiveMismatches {
                isCancelled = true
                return .cancelled
            }
            return isConfirmedMoving ? .moving : .waiting
        }
    }

    public mutating func reset() {
        mismatchCount = 0
        isConfirmedMoving = false
        isCancelled = false
    }
}
