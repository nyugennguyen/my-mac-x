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

    /// Default partition assignments per Z-03.
    public func defaultPartitions(count: Int) -> [ActionID] {
        if isCorner {
            return [defaultAction]
        }
        let clampedCount = min(max(count, 1), 4)
        if isHorizontalEdge {
            switch clampedCount {
            case 1:
                return [defaultAction]
            case 2:
                return [.leftHalf, .rightHalf]
            case 3:
                return [
                    .leftThird,
                    ActionID(rawValue: "window.center-third"),
                    ActionID(rawValue: "window.right-third")
                ]
            case 4:
                return [
                    ActionID(rawValue: "window.left-quarter"),
                    ActionID(rawValue: "window.left-middle-quarter"),
                    ActionID(rawValue: "window.right-middle-quarter"),
                    ActionID(rawValue: "window.right-quarter")
                ]
            default:
                return [defaultAction]
            }
        } else {
            switch clampedCount {
            case 1:
                return [defaultAction]
            case 2:
                return [.topHalf, .bottomHalf]
            case 3:
                return [
                    ActionID(rawValue: "window.top-third"),
                    ActionID(rawValue: "window.middle-third"),
                    ActionID(rawValue: "window.bottom-third")
                ]
            case 4:
                return [
                    ActionID(rawValue: "window.top-quarter"),
                    ActionID(rawValue: "window.upper-middle-quarter"),
                    ActionID(rawValue: "window.lower-middle-quarter"),
                    ActionID(rawValue: "window.bottom-quarter")
                ]
            default:
                return [defaultAction]
            }
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

/// User-configurable zone-to-action bindings, multi-area partitions, and per-zone disabled switches (Z-03, Z-04, Z-07, Z-08).
public struct EdgeSnapZoneConfiguration: Equatable, Sendable {
    public var customActions: [EdgeSnapZone: ActionID]
    public var customPartitions: [EdgeSnapZone: [ActionID]]
    public var disabledZones: Set<EdgeSnapZone>

    public init(
        customActions: [EdgeSnapZone: ActionID] = [:],
        customPartitions: [EdgeSnapZone: [ActionID]] = [:],
        disabledZones: Set<EdgeSnapZone> = []
    ) {
        var actions = customActions
        var partitions = customPartitions

        for (zone, action) in customActions {
            if partitions[zone] == nil || partitions[zone]?.isEmpty == true {
                partitions[zone] = [action]
            }
        }
        for (zone, actionList) in partitions {
            if actions[zone] == nil, let first = actionList.first {
                actions[zone] = first
            }
        }

        self.customActions = actions
        self.customPartitions = partitions
        self.disabledZones = disabledZones
    }

    /// Resolves the partitions for a zone, validating whitelist and partition counts,
    /// falling back cleanly to defaults per Z-05/Z-07.
    public func actions(for zone: EdgeSnapZone) -> [ActionID] {
        let maxParts = zone.isCorner ? 1 : 4
        if let partitions = customPartitions[zone], !partitions.isEmpty {
            if partitions.count <= maxParts && partitions.allSatisfy(EdgeSnapZone.isPermittedAction) {
                return partitions
            }
            return [zone.defaultAction]
        }
        if let custom = customActions[zone] {
            if EdgeSnapZone.isPermittedAction(custom) {
                return [custom]
            }
            return [zone.defaultAction]
        }
        return [zone.defaultAction]
    }

    /// Resolves the action for a zone and sub-partition index, falling back to default action per Z-02/Z-07.
    public func action(for zone: EdgeSnapZone, partitionIndex: Int = 0) -> ActionID {
        let list = actions(for: zone)
        if partitionIndex >= 0 && partitionIndex < list.count {
            return list[partitionIndex]
        }
        return list.first ?? zone.defaultAction
    }

    /// Checks if a zone is enabled per Z-08.
    public func isEnabled(_ zone: EdgeSnapZone) -> Bool {
        !disabledZones.contains(zone)
    }
}
