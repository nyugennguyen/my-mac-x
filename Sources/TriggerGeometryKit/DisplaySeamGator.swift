import CoreGraphics
import Foundation

/// Classification of a display border against neighboring screens in the topology.
public enum EdgeBoundaryClassification: Equatable, Sendable {
    /// An outer physical display wall with empty space beyond it (S-01).
    case outerWall
    /// A shared display boundary with an adjacent display directly across it (S-02).
    case sharedSeam(neighborDisplayID: DisplayID)
}

/// Classifies display boundaries using geometric probe points 0.5 pt beyond the edge (S-01, S-02).
public struct DisplaySeamClassifier: Sendable {
    public static let probeOffset: CGFloat = 0.5

    public init() {}

    /// Classifies an edge of a display against all other displays in the topology.
    public func classify(
        edge: EdgeSnapZone,
        on display: DisplaySnapshot,
        in topology: DisplayTopologySnapshot
    ) -> EdgeBoundaryClassification {
        guard edge.isStraightEdge else {
            return .outerWall
        }

        let frame = display.frame
        let probePoint: CGPoint

        switch edge {
        case .left:
            probePoint = CGPoint(x: frame.minX - Self.probeOffset, y: frame.midY)
        case .right:
            probePoint = CGPoint(x: frame.maxX + Self.probeOffset, y: frame.midY)
        case .bottom:
            probePoint = CGPoint(x: frame.midX, y: frame.minY - Self.probeOffset)
        case .top:
            probePoint = CGPoint(x: frame.midX, y: frame.maxY + Self.probeOffset)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .outerWall
        }

        for other in topology.displays where other.id != display.id {
            if other.frame.contains(probePoint) {
                return .sharedSeam(neighborDisplayID: other.id)
            }
        }

        return .outerWall
    }
}

/// Result of evaluating Seam Gating rules for a proposed snap interaction.
public struct SeamGatingResult: Equatable, Sendable {
    public let isAllowed: Bool
    public let boundary: EdgeBoundaryClassification
    public let normalVelocity: CGFloat
    public let tangentialVelocity: CGFloat

    public init(
        isAllowed: Bool,
        boundary: EdgeBoundaryClassification,
        normalVelocity: CGFloat,
        tangentialVelocity: CGFloat
    ) {
        self.isAllowed = isAllowed
        self.boundary = boundary
        self.normalVelocity = normalVelocity
        self.tangentialVelocity = tangentialVelocity
    }
}

/// Evaluates Seam Gating velocity rules on display borders (S-01, S-02, S-03).
///
/// - Outer walls pass snap triggers at any flick speed (S-01).
/// - Shared display seams require normal velocity <= 400 pt/s (S-02).
/// - Parallel velocity along the edge is completely ignored (S-03).
public struct DisplaySeamGator: Sendable {
    public static let crossingSpeedThreshold: CGFloat = 400.0 // 400 pt/s

    private let classifier: DisplaySeamClassifier

    public init(classifier: DisplaySeamClassifier = DisplaySeamClassifier()) {
        self.classifier = classifier
    }

    /// Evaluates whether an edge snap trigger is allowed to activate given the pointer velocity trail.
    public func evaluate(
        zone: EdgeSnapZone,
        on display: DisplaySnapshot,
        in topology: DisplayTopologySnapshot,
        trail: PointerTrail,
        evaluationTime: TimeInterval? = nil
    ) -> SeamGatingResult {
        let boundary = classifyBoundary(for: zone, on: display, in: topology)
        let v = trail.velocity(at: evaluationTime)
        let vn = normalVelocity(for: zone, velocity: v)
        let vt = tangentialVelocity(for: zone, velocity: v)

        switch boundary {
        case .outerWall:
            // S-01: Outer walls pass at any speed
            return SeamGatingResult(
                isAllowed: true,
                boundary: .outerWall,
                normalVelocity: vn,
                tangentialVelocity: vt
            )

        case .sharedSeam:
            // S-02: Shared seams require normal velocity <= 400 pt/s
            // S-03: Tangential velocity is ignored
            let isAllowed = vn <= Self.crossingSpeedThreshold
            return SeamGatingResult(
                isAllowed: isAllowed,
                boundary: boundary,
                normalVelocity: vn,
                tangentialVelocity: vt
            )
        }
    }

    private func classifyBoundary(
        for zone: EdgeSnapZone,
        on display: DisplaySnapshot,
        in topology: DisplayTopologySnapshot
    ) -> EdgeBoundaryClassification {
        switch zone {
        case .left:
            return classifier.classify(edge: .left, on: display, in: topology)
        case .right:
            return classifier.classify(edge: .right, on: display, in: topology)
        case .top:
            return classifier.classify(edge: .top, on: display, in: topology)
        case .bottom:
            return classifier.classify(edge: .bottom, on: display, in: topology)
        case .topLeft:
            let leftClass = classifier.classify(edge: .left, on: display, in: topology)
            if case .sharedSeam = leftClass { return leftClass }
            let topClass = classifier.classify(edge: .top, on: display, in: topology)
            if case .sharedSeam = topClass { return topClass }
            return .outerWall
        case .topRight:
            let rightClass = classifier.classify(edge: .right, on: display, in: topology)
            if case .sharedSeam = rightClass { return rightClass }
            let topClass = classifier.classify(edge: .top, on: display, in: topology)
            if case .sharedSeam = topClass { return topClass }
            return .outerWall
        case .bottomLeft:
            let leftClass = classifier.classify(edge: .left, on: display, in: topology)
            if case .sharedSeam = leftClass { return leftClass }
            let bottomClass = classifier.classify(edge: .bottom, on: display, in: topology)
            if case .sharedSeam = bottomClass { return bottomClass }
            return .outerWall
        case .bottomRight:
            let rightClass = classifier.classify(edge: .right, on: display, in: topology)
            if case .sharedSeam = rightClass { return rightClass }
            let bottomClass = classifier.classify(edge: .bottom, on: display, in: topology)
            if case .sharedSeam = bottomClass { return bottomClass }
            return .outerWall
        }
    }

    public func normalVelocity(for zone: EdgeSnapZone, velocity: CGVector) -> CGFloat {
        if zone.isVerticalEdge || zone == .topLeft || zone == .bottomLeft || zone == .topRight || zone == .bottomRight {
            return abs(velocity.dx)
        } else {
            return abs(velocity.dy)
        }
    }

    public func tangentialVelocity(for zone: EdgeSnapZone, velocity: CGVector) -> CGFloat {
        if zone.isVerticalEdge || zone == .topLeft || zone == .bottomLeft || zone == .topRight || zone == .bottomRight {
            return abs(velocity.dy)
        } else {
            return abs(velocity.dx)
        }
    }
}

/// Generational invalidation token for seam still-check timers (S-09).
public struct SeamStillCheckSession: Equatable, Sendable {
    public private(set) var generation: UInt64 = 0

    public init() {}

    public mutating func invalidate() {
        generation &+= 1
    }

    public func isValid(generation checkGeneration: UInt64) -> Bool {
        generation == checkGeneration
    }
}
