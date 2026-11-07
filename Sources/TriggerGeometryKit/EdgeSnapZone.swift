import Foundation

/// The eight canonical perimeter docking zones on a Display (Z-01).
public enum EdgeSnapZone: String, CaseIterable, Hashable, Codable, Sendable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight

    public var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return true
        case .top, .bottom, .left, .right:
            return false
        }
    }

    public var isStraightEdge: Bool {
        !isCorner
    }

    public var isHorizontalEdge: Bool {
        self == .top || self == .bottom
    }

    public var isVerticalEdge: Bool {
        self == .left || self == .right
    }

    /// Default action assignments per Z-02.
    public var defaultAction: ActionID {
        switch self {
        case .topLeft:
            return .topLeftQuarter
        case .top:
            return .maximize
        case .topRight:
            return .topRightQuarter
        case .left:
            return .leftHalf
        case .right:
            return .rightHalf
        case .bottomLeft:
            return .bottomLeftQuarter
        case .bottom:
            return .bottomHalf
        case .bottomRight:
            return .bottomRightQuarter
        }
    }

    /// Allowed action whitelist per Z-05.
    public static func isPermittedAction(_ actionID: ActionID) -> Bool {
        let permitted: Set<ActionID> = [
            .maximize,
            .leftHalf,
            .rightHalf,
            .topHalf,
            .bottomHalf,
            .topLeftQuarter,
            .topRightQuarter,
            .bottomLeftQuarter,
            .bottomRightQuarter,
            .leftThird,
            .leftTwoThirds,
            ActionID(rawValue: "window.right-third"),
            ActionID(rawValue: "window.right-two-thirds"),
            ActionID(rawValue: "window.center-third"),
            ActionID(rawValue: "window.center-two-thirds"),
            ActionID(rawValue: "window.top-third"),
            ActionID(rawValue: "window.middle-third"),
            ActionID(rawValue: "window.bottom-third"),
            ActionID(rawValue: "window.top-two-thirds"),
            ActionID(rawValue: "window.bottom-two-thirds"),
            ActionID(rawValue: "window.center-half"),
            ActionID(rawValue: "window.margin-maximize"),
            ActionID(rawValue: "window.top-quarter"),
            ActionID(rawValue: "window.upper-middle-quarter"),
            ActionID(rawValue: "window.lower-middle-quarter"),
            ActionID(rawValue: "window.bottom-quarter"),
            ActionID(rawValue: "window.left-quarter"),
            ActionID(rawValue: "window.left-middle-quarter"),
            ActionID(rawValue: "window.right-middle-quarter"),
            ActionID(rawValue: "window.right-quarter"),
            ActionID(rawValue: "window.top-left-sixth"),
            ActionID(rawValue: "window.top-center-sixth"),
            ActionID(rawValue: "window.top-right-sixth"),
            ActionID(rawValue: "window.bottom-left-sixth"),
            ActionID(rawValue: "window.bottom-center-sixth"),
            ActionID(rawValue: "window.bottom-right-sixth")
        ]
        return permitted.contains(actionID)
    }
}

/// User-configurable zone-to-action bindings and per-zone disabled switches (Z-07, Z-08).
public struct EdgeSnapZoneConfiguration: Equatable, Sendable {
    public var customActions: [EdgeSnapZone: ActionID]
    public var disabledZones: Set<EdgeSnapZone>

    public init(
        customActions: [EdgeSnapZone: ActionID] = [:],
        disabledZones: Set<EdgeSnapZone> = []
    ) {
        self.customActions = customActions
        self.disabledZones = disabledZones
    }

    /// Resolves the action for a zone, falling back to default action per Z-02/Z-07.
    public func action(for zone: EdgeSnapZone) -> ActionID {
        if let custom = customActions[zone], EdgeSnapZone.isPermittedAction(custom) {
            return custom
        }
        return zone.defaultAction
    }

    /// Checks if a zone is enabled per Z-08.
    public func isEnabled(_ zone: EdgeSnapZone) -> Bool {
        !disabledZones.contains(zone)
    }
}
