import CoreGraphics

/// The resolved edge snap target returned when a pointer activates a perimeter zone.
public struct EdgeSnapTarget: Equatable, Sendable {
    public let displayID: DisplayID
    public let zone: EdgeSnapZone
    public let partitionIndex: Int
    public let action: ActionID
    public let activationRegion: CGRect

    public init(
        displayID: DisplayID,
        zone: EdgeSnapZone,
        partitionIndex: Int = 0,
        action: ActionID,
        activationRegion: CGRect
    ) {
        self.displayID = displayID
        self.zone = zone
        self.partitionIndex = partitionIndex
        self.action = action
        self.activationRegion = activationRegion
    }
}

/// Resolves pointer locations against the canonical 8-zone perimeter topology (Z-01).
///
/// Corner bands scale dynamically with screen dimensions:
/// - Corner width: `min(max(screenFrame.width * 0.18, 96), 180)` points.
/// - Corner height: `min(max(screenFrame.height * 0.18, 80), 160)` points.
/// - Activation distance: 12 points from the screen perimeter.
public struct EdgeSnapGeometryResolver: Sendable {
    public static let activationDistance: CGFloat = 12

    public static func cornerWidth(for screenWidth: CGFloat) -> CGFloat {
        min(min(max(screenWidth * 0.18, 96), 180), max(0, screenWidth * 0.5))
    }

    public static func cornerHeight(for screenHeight: CGFloat) -> CGFloat {
        min(min(max(screenHeight * 0.18, 80), 160), max(0, screenHeight * 0.5))
    }

    public init() {}

    /// Resolves pointer location against validated display topology.
    public func resolve(
        pointerLocation: CGPoint,
        topology: DisplayTopologySnapshot,
        configuration: EdgeSnapZoneConfiguration = EdgeSnapZoneConfiguration()
    ) -> EdgeSnapTarget? {
        guard pointerLocation.x.isFinite, pointerLocation.y.isFinite else {
            return nil
        }

        guard let display = selectDisplay(at: pointerLocation, in: topology.displays) else {
            return nil
        }

        guard let (zone, region) = resolveZone(at: pointerLocation, in: display.frame) else {
            return nil
        }

        // Z-08: Check disabled zones
        guard configuration.isEnabled(zone) else {
            return nil
        }

        let zoneActions = configuration.actions(for: zone)
        let partitionCount = zoneActions.count
        let (partitionIndex, activationRegion) = resolvePartition(
            at: pointerLocation,
            in: display.frame,
            zone: zone,
            partitionCount: partitionCount,
            baseRegion: region
        )

        let action = configuration.action(for: zone, partitionIndex: partitionIndex)
        return EdgeSnapTarget(
            displayID: display.id,
            zone: zone,
            partitionIndex: partitionIndex,
            action: action,
            activationRegion: activationRegion
        )
    }

    // MARK: - Z-03 & Z-04 Partition Resolution

    public func resolvePartition(
        at point: CGPoint,
        in frame: CGRect,
        zone: EdgeSnapZone,
        partitionCount: Int,
        baseRegion: CGRect
    ) -> (partitionIndex: Int, activationRegion: CGRect) {
        guard zone.isStraightEdge, partitionCount > 1 else {
            return (0, baseRegion)
        }

        let cWidth = Self.cornerWidth(for: frame.width)
        let cHeight = Self.cornerHeight(for: frame.height)

        if zone.isHorizontalEdge {
            let straightWidth = max(frame.width - 2 * cWidth, 1)
            let f = (point.x - frame.minX - cWidth) / straightWidth
            let clampedF = min(max(f, 0.0), 1.0)
            let index = min(max(Int(floor(clampedF * Double(partitionCount))), 0), partitionCount - 1)
            let partWidth = (frame.width - 2 * cWidth) / CGFloat(partitionCount)
            let partX = frame.minX + cWidth + CGFloat(index) * partWidth
            let partRegion = CGRect(x: partX, y: baseRegion.minY, width: partWidth, height: baseRegion.height)
            return (index, partRegion)
        } else {
            let straightHeight = max(frame.height - 2 * cHeight, 1)
            let f = (frame.maxY - cHeight - point.y) / straightHeight
            let clampedF = min(max(f, 0.0), 1.0)
            let index = min(max(Int(floor(clampedF * Double(partitionCount))), 0), partitionCount - 1)
            let partHeight = (frame.height - 2 * cHeight) / CGFloat(partitionCount)
            let partY = frame.maxY - cHeight - CGFloat(index + 1) * partHeight
            let partRegion = CGRect(x: baseRegion.minX, y: partY, width: baseRegion.width, height: partHeight)
            return (index, partRegion)
        }
    }

    // MARK: - Internal Zone Resolution

    public func resolveZone(
        at point: CGPoint,
        in frame: CGRect
    ) -> (zone: EdgeSnapZone, region: CGRect)? {
        let actDist = Self.activationDistance
        let cWidth = Self.cornerWidth(for: frame.width)
        let cHeight = Self.cornerHeight(for: frame.height)

        // Near edge boundaries (AppKit global coordinates: minY is bottom, maxY is top)
        let nearLeft = point.x >= frame.minX - actDist && point.x <= frame.minX + actDist && point.y >= frame.minY - actDist && point.y <= frame.maxY + actDist
        let nearRight = point.x >= frame.maxX - actDist && point.x <= frame.maxX + actDist && point.y >= frame.minY - actDist && point.y <= frame.maxY + actDist
        let nearBottom = point.y >= frame.minY - actDist && point.y <= frame.minY + actDist && point.x >= frame.minX - actDist && point.x <= frame.maxX + actDist
        let nearTop = point.y >= frame.maxY - actDist && point.y <= frame.maxY + actDist && point.x >= frame.minX - actDist && point.x <= frame.maxX + actDist

        guard nearLeft || nearRight || nearBottom || nearTop else {
            return nil
        }

        let isLeftBand = point.x <= frame.minX + cWidth
        let isRightBand = point.x >= frame.maxX - cWidth
        let isBottomBand = point.y <= frame.minY + cHeight
        let isTopBand = point.y >= frame.maxY - cHeight

        // Corner priority (Z-01)
        if (nearTop && isLeftBand) || (nearLeft && isTopBand) {
            let region = CGRect(x: frame.minX, y: frame.maxY - cHeight, width: cWidth, height: cHeight)
            return (.topLeft, region)
        }
        if (nearTop && isRightBand) || (nearRight && isTopBand) {
            let region = CGRect(x: frame.maxX - cWidth, y: frame.maxY - cHeight, width: cWidth, height: cHeight)
            return (.topRight, region)
        }
        if (nearBottom && isLeftBand) || (nearLeft && isBottomBand) {
            let region = CGRect(x: frame.minX, y: frame.minY, width: cWidth, height: cHeight)
            return (.bottomLeft, region)
        }
        if (nearBottom && isRightBand) || (nearRight && isBottomBand) {
            let region = CGRect(x: frame.maxX - cWidth, y: frame.minY, width: cWidth, height: cHeight)
            return (.bottomRight, region)
        }

        // Straight edges
        if nearTop && !isLeftBand && !isRightBand {
            let region = CGRect(x: frame.minX + cWidth, y: frame.maxY - actDist, width: max(frame.width - 2 * cWidth, 0), height: actDist)
            return (.top, region)
        }
        if nearBottom && !isLeftBand && !isRightBand {
            let region = CGRect(x: frame.minX + cWidth, y: frame.minY, width: max(frame.width - 2 * cWidth, 0), height: actDist)
            return (.bottom, region)
        }
        if nearLeft && !isTopBand && !isBottomBand {
            let region = CGRect(x: frame.minX, y: frame.minY + cHeight, width: actDist, height: max(frame.height - 2 * cHeight, 0))
            return (.left, region)
        }
        if nearRight && !isTopBand && !isBottomBand {
            let region = CGRect(x: frame.maxX - actDist, y: frame.minY + cHeight, width: actDist, height: max(frame.height - 2 * cHeight, 0))
            return (.right, region)
        }

        return nil
    }

    // MARK: - Display Selection & Tie-Breaking (S-10)

    private func selectDisplay(
        at point: CGPoint,
        in displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        guard !displays.isEmpty else { return nil }

        let actDist = Self.activationDistance
        let candidates = displays.filter { display in
            let expanded = display.frame.insetBy(dx: -actDist, dy: -actDist)
            return expanded.contains(point)
        }

        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 {
            return candidates[0]
        }

        // Rank by distance to display frame; break ties using AppKit/Quartz ownership (S-10)
        return candidates.min { a, b in
            let distA = distanceSquared(from: point, to: a.frame)
            let distB = distanceSquared(from: point, to: b.frame)
            if abs(distA - distB) > 0.0001 {
                return distA < distB
            }
            let holdsA = holds(point, in: a.frame)
            let holdsB = holds(point, in: b.frame)
            if holdsA != holdsB {
                return holdsA && !holdsB
            }
            return false
        }
    }

    private func holds(_ point: CGPoint, in frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX && point.y > frame.minY && point.y <= frame.maxY
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
