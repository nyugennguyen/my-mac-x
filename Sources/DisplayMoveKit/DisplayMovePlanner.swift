import CoreGraphics

/// Horizontal physical-Display direction requested by a Window Action.
enum DisplayMoveDirection: Equatable, Sendable {
    case left
    case right
}

/// Behavior when no Display lies farther in the requested direction.
enum DisplayMoveWrapPolicy: Equatable, Sendable {
    case stopAtEdge
    case wrap
}

/// Observable safety adjustment made while fitting a moved window on its destination Display.
enum DisplayMoveWarning: Equatable, Sendable {
    case destinationVisibleFrameClamped
}

/// One immutable pure plan for moving a Captured Window to another physical Display.
struct DisplayMovePlan: Equatable, Sendable {
    let targetFrame: AppKitGlobalLogicalFrame
    /// Identity from the supplied topology capture; callers must not retain it across reconnects.
    let destinationDisplayID: DisplayID
    let warnings: [DisplayMoveWarning]

    var isConstrained: Bool {
        !warnings.isEmpty
    }
}

enum DisplayMoveFailure: Error, Equatable, Sendable {
    case invalidWindowFrame
    case noDestination
}

/// Pure mapping from one Captured Window and fresh topology to its destination Display target.
struct DisplayMovePlanner: Sendable {
    init() {}

    func plan(
        window: AppKitGlobalLogicalFrame,
        direction: DisplayMoveDirection,
        topology: DisplayTopologySnapshot,
        wrapPolicy: DisplayMoveWrapPolicy = .wrap
    ) -> Result<DisplayMovePlan, DisplayMoveFailure> {
        let frame = window.cgRect
        guard Self.isValidNonEmptyFrame(frame) else {
            return .failure(.invalidWindowFrame)
        }
        guard let source = sourceDisplay(for: frame, among: topology.displays),
              let destination = destinationDisplay(
                  from: source,
                  direction: direction,
                  among: topology.displays,
                  wrapPolicy: wrapPolicy
              )
        else {
            return .failure(.noDestination)
        }

        let sourceVisibleFrame = source.visibleFrame
        let destinationVisibleFrame = destination.visibleFrame
        let normalizedCenter = CGPoint(
            x: (frame.midX - sourceVisibleFrame.minX) / sourceVisibleFrame.width,
            y: (frame.midY - sourceVisibleFrame.minY) / sourceVisibleFrame.height
        )
        let normalizedSize = CGSize(
            width: frame.width / sourceVisibleFrame.width,
            height: frame.height / sourceVisibleFrame.height
        )
        let targetSize = CGSize(
            width: destinationVisibleFrame.width * normalizedSize.width,
            height: destinationVisibleFrame.height * normalizedSize.height
        )
        let targetCenter = CGPoint(
            x: destinationVisibleFrame.minX + destinationVisibleFrame.width * normalizedCenter.x,
            y: destinationVisibleFrame.minY + destinationVisibleFrame.height * normalizedCenter.y
        )
        let mappedTarget = CGRect(
            x: targetCenter.x - targetSize.width / 2,
            y: targetCenter.y - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        let roundedTarget = DisplayFrameFitter.roundedToBackingEdges(
            mappedTarget,
            relativeTo: destination.frame.origin,
            scale: destination.backingScaleFactor
        )
        let target = DisplayFrameFitter.clamp(roundedTarget, inside: destinationVisibleFrame)
        let warnings: [DisplayMoveWarning] = DisplayFrameFitter.framesApproximatelyEqual(
            target,
            roundedTarget
        ) ? [] : [.destinationVisibleFrameClamped]

        return .success(DisplayMovePlan(
            targetFrame: AppKitGlobalLogicalFrame(target),
            destinationDisplayID: destination.id,
            warnings: warnings
        ))
    }

    private func sourceDisplay(
        for window: CGRect,
        among displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        displays.min { left, right in
            let leftIntersection = window.intersection(left.frame)
            let rightIntersection = window.intersection(right.frame)
            let leftArea = Self.area(of: leftIntersection)
            let rightArea = Self.area(of: rightIntersection)
            if leftArea != rightArea {
                return leftArea > rightArea
            }

            let leftDistance = Self.squaredDistance(from: window.center, to: left.frame.center)
            let rightDistance = Self.squaredDistance(from: window.center, to: right.frame.center)
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return Self.spatialOrder(left, right)
        }
    }

    private func destinationDisplay(
        from source: DisplaySnapshot,
        direction: DisplayMoveDirection,
        among displays: [DisplaySnapshot],
        wrapPolicy: DisplayMoveWrapPolicy
    ) -> DisplaySnapshot? {
        let candidates = displays.filter { display in
            guard display.id != source.id else { return false }
            switch direction {
            case .left:
                return display.frame.midX < source.frame.midX
            case .right:
                return display.frame.midX > source.frame.midX
            }
        }
        if let nearest = candidates.min(by: { destinationOrder($0, $1, from: source) }) {
            return nearest
        }
        guard wrapPolicy == .wrap else { return nil }

        let others = displays.filter { $0.id != source.id }
        switch direction {
        case .left:
            return others.max(by: Self.spatialOrder)
        case .right:
            return others.min(by: Self.spatialOrder)
        }
    }

    private func destinationOrder(
        _ left: DisplaySnapshot,
        _ right: DisplaySnapshot,
        from source: DisplaySnapshot
    ) -> Bool {
        let leftDistance = Self.squaredDistance(from: source.frame.center, to: left.frame.center)
        let rightDistance = Self.squaredDistance(from: source.frame.center, to: right.frame.center)
        if leftDistance != rightDistance {
            return leftDistance < rightDistance
        }
        return Self.spatialOrder(left, right)
    }

    private static func spatialOrder(_ left: DisplaySnapshot, _ right: DisplaySnapshot) -> Bool {
        if left.frame.minX != right.frame.minX {
            return left.frame.minX < right.frame.minX
        }
        if left.frame.minY != right.frame.minY {
            return left.frame.minY < right.frame.minY
        }
        return left.id.rawValue < right.id.rawValue
    }

    private static func area(of frame: CGRect) -> CGFloat {
        frame.isNull || frame.isEmpty ? 0 : frame.width * frame.height
    }

    private static func squaredDistance(from left: CGPoint, to right: CGPoint) -> CGFloat {
        let deltaX = left.x - right.x
        let deltaY = left.y - right.y
        return deltaX * deltaX + deltaY * deltaY
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

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
