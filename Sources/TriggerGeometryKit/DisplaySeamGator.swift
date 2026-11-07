import CoreGraphics
import Foundation

/// Orientation of a shared display boundary.
public enum SeamOrientation: String, Equatable, Sendable {
    case vertical
    case horizontal
}

/// Classification of a display border against neighboring screens in the topology.
public enum EdgeBoundaryClassification: Equatable, Sendable {
    /// An outer physical display wall with empty space beyond it (S-01).
    case outerWall
    /// A shared display boundary with an adjacent display directly across it (S-02).
    case sharedSeam(neighborDisplayID: DisplayID, orientation: SeamOrientation)

    public var neighborDisplayID: DisplayID? {
        switch self {
        case .outerWall: return nil
        case .sharedSeam(let id, _): return id
        }
    }

    public var orientation: SeamOrientation? {
        switch self {
        case .outerWall: return nil
        case .sharedSeam(_, let orientation): return orientation
        }
    }
}

/// Classifies display boundaries using geometric probe points 0.5 pt beyond the edge (S-01, S-02).
public struct DisplaySeamClassifier: Sendable {
    public static let probeOffset: CGFloat = 0.5

    public init() {}

    /// Classifies an edge of a display against all other displays in the topology.
    ///
    /// - Parameters:
    ///   - edge: The straight edge zone to classify.
    ///   - display: The display whose edge is being evaluated.
    ///   - topology: The multi-display topology snapshot.
    ///   - contactPoint: Optional pointer coordinate along the edge. If provided, probes at that exact contact location (clamped to edge bounds). If nil, tests geometric intersection along the entire edge segment.
    public func classify(
        edge: EdgeSnapZone,
        on display: DisplaySnapshot,
        in topology: DisplayTopologySnapshot,
        contactPoint: CGPoint? = nil
    ) -> EdgeBoundaryClassification {
        guard edge.isStraightEdge else {
            return .outerWall
        }

        let frame = display.frame
        let orientation: SeamOrientation = edge.isVerticalEdge ? .vertical : .horizontal

        if let contact = contactPoint {
            let probePoint: CGPoint
            switch edge {
            case .left:
                let y = min(max(contact.y, frame.minY), frame.maxY)
                probePoint = CGPoint(x: frame.minX - Self.probeOffset, y: y)
            case .right:
                let y = min(max(contact.y, frame.minY), frame.maxY)
                probePoint = CGPoint(x: frame.maxX + Self.probeOffset, y: y)
            case .bottom:
                let x = min(max(contact.x, frame.minX), frame.maxX)
                probePoint = CGPoint(x: x, y: frame.minY - Self.probeOffset)
            case .top:
                let x = min(max(contact.x, frame.minX), frame.maxX)
                probePoint = CGPoint(x: x, y: frame.maxY + Self.probeOffset)
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                return .outerWall
            }

            for other in topology.displays where other.id != display.id {
                if other.frame.contains(probePoint) {
                    return .sharedSeam(neighborDisplayID: other.id, orientation: orientation)
                }
            }
            return .outerWall
        } else {
            // Rectangle edge intersection between display frames
            let probeRect: CGRect
            switch edge {
            case .left:
                probeRect = CGRect(x: frame.minX - Self.probeOffset, y: frame.minY, width: Self.probeOffset, height: frame.height)
            case .right:
                probeRect = CGRect(x: frame.maxX, y: frame.minY, width: Self.probeOffset, height: frame.height)
            case .bottom:
                probeRect = CGRect(x: frame.minX, y: frame.minY - Self.probeOffset, width: frame.width, height: Self.probeOffset)
            case .top:
                probeRect = CGRect(x: frame.minX, y: frame.maxY, width: frame.width, height: Self.probeOffset)
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                return .outerWall
            }

            for other in topology.displays where other.id != display.id {
                if other.frame.intersects(probeRect) {
                    return .sharedSeam(neighborDisplayID: other.id, orientation: orientation)
                }
            }
            return .outerWall
        }
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
        let v = trail.velocity(at: evaluationTime)
        let contactPoint = trail.samples.last?.point
        let boundary = classifyBoundary(for: zone, on: display, in: topology, contactPoint: contactPoint, velocity: v)
        let vn = normalVelocity(for: zone, boundary: boundary, velocity: v)
        let vt = tangentialVelocity(for: zone, boundary: boundary, velocity: v)

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
        in topology: DisplayTopologySnapshot,
        contactPoint: CGPoint?,
        velocity: CGVector
    ) -> EdgeBoundaryClassification {
        switch zone {
        case .left:
            return classifier.classify(edge: .left, on: display, in: topology, contactPoint: contactPoint)
        case .right:
            return classifier.classify(edge: .right, on: display, in: topology, contactPoint: contactPoint)
        case .top:
            return classifier.classify(edge: .top, on: display, in: topology, contactPoint: contactPoint)
        case .bottom:
            return classifier.classify(edge: .bottom, on: display, in: topology, contactPoint: contactPoint)
        case .topLeft:
            let leftClass = classifier.classify(edge: .left, on: display, in: topology, contactPoint: contactPoint)
            let topClass = classifier.classify(edge: .top, on: display, in: topology, contactPoint: contactPoint)
            return resolveCornerBoundary(verticalEdge: leftClass, horizontalEdge: topClass, velocity: velocity)
        case .topRight:
            let rightClass = classifier.classify(edge: .right, on: display, in: topology, contactPoint: contactPoint)
            let topClass = classifier.classify(edge: .top, on: display, in: topology, contactPoint: contactPoint)
            return resolveCornerBoundary(verticalEdge: rightClass, horizontalEdge: topClass, velocity: velocity)
        case .bottomLeft:
            let leftClass = classifier.classify(edge: .left, on: display, in: topology, contactPoint: contactPoint)
            let bottomClass = classifier.classify(edge: .bottom, on: display, in: topology, contactPoint: contactPoint)
            return resolveCornerBoundary(verticalEdge: leftClass, horizontalEdge: bottomClass, velocity: velocity)
        case .bottomRight:
            let rightClass = classifier.classify(edge: .right, on: display, in: topology, contactPoint: contactPoint)
            let bottomClass = classifier.classify(edge: .bottom, on: display, in: topology, contactPoint: contactPoint)
            return resolveCornerBoundary(verticalEdge: rightClass, horizontalEdge: bottomClass, velocity: velocity)
        }
    }

    private func resolveCornerBoundary(
        verticalEdge: EdgeBoundaryClassification,
        horizontalEdge: EdgeBoundaryClassification,
        velocity: CGVector
    ) -> EdgeBoundaryClassification {
        switch (verticalEdge, horizontalEdge) {
        case (.sharedSeam, .sharedSeam):
            if abs(velocity.dy) > abs(velocity.dx) {
                return horizontalEdge
            } else {
                return verticalEdge
            }
        case (.sharedSeam, _):
            return verticalEdge
        case (_, .sharedSeam):
            return horizontalEdge
        default:
            return .outerWall
        }
    }

    public func normalVelocity(
        for zone: EdgeSnapZone,
        boundary: EdgeBoundaryClassification,
        velocity: CGVector
    ) -> CGFloat {
        switch boundary {
        case .sharedSeam(_, let orientation):
            switch orientation {
            case .horizontal:
                return abs(velocity.dy)
            case .vertical:
                return abs(velocity.dx)
            }
        case .outerWall:
            if zone.isVerticalEdge || zone.isCorner {
                return abs(velocity.dx)
            } else {
                return abs(velocity.dy)
            }
        }
    }

    public func normalVelocity(for zone: EdgeSnapZone, velocity: CGVector) -> CGFloat {
        normalVelocity(for: zone, boundary: .outerWall, velocity: velocity)
    }

    public func tangentialVelocity(
        for zone: EdgeSnapZone,
        boundary: EdgeBoundaryClassification,
        velocity: CGVector
    ) -> CGFloat {
        switch boundary {
        case .sharedSeam(_, let orientation):
            switch orientation {
            case .horizontal:
                return abs(velocity.dx)
            case .vertical:
                return abs(velocity.dy)
            }
        case .outerWall:
            if zone.isVerticalEdge || zone.isCorner {
                return abs(velocity.dy)
            } else {
                return abs(velocity.dx)
            }
        }
    }

    public func tangentialVelocity(for zone: EdgeSnapZone, velocity: CGVector) -> CGFloat {
        tangentialVelocity(for: zone, boundary: .outerWall, velocity: velocity)
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
