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

/// Read-only discovery for Window Actions that callers may present or bind.
///
/// This registry deliberately describes actions without resolving layouts, reading
/// Accessibility state, or executing an action. Execution remains behind
/// `WindowActionPerforming`.
public struct ActionRegistry: Sendable {
    public let actions: [ActionDescriptor]

    private let actionsByID: [ActionID: ActionDescriptor]

    public init(actions: [ActionDescriptor]) {
        precondition(
            Set(actions.map(\.id)).count == actions.count,
            "ActionRegistry requires unique ActionID values"
        )
        self.actions = actions
        actionsByID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
    }

    public func action(for id: ActionID) -> ActionDescriptor? {
        actionsByID[id]
    }
}

public struct ActionDescriptor: Equatable, Sendable {
    public let id: ActionID
    public let title: String
    public let symbolName: String
    public let availability: ActionAvailability

    public init(
        id: ActionID,
        title: String,
        symbolName: String,
        availability: ActionAvailability
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.availability = availability
    }
}

public enum ActionAvailability: Equatable, Sendable {
    case available
    case unavailable(ActionUnavailability)
}

public enum ActionUnavailability: Equatable, Sendable {
    case disabled
    case experimental
    case unsupportedOnCurrentSystem
}

public extension ActionRegistry {
    static let builtIn = Self(actions: [
        .init(id: .maximize, title: "Maximize", symbolName: "rectangle.inset.filled", availability: .available),
        .init(id: .nativeFullScreen, title: "Native Full Screen", symbolName: "arrow.up.left.and.arrow.down.right", availability: .available),
        .init(id: .leftHalf, title: "Left Half", symbolName: "rectangle.lefthalf.filled", availability: .available),
        .init(id: .rightHalf, title: "Right Half", symbolName: "rectangle.righthalf.filled", availability: .available),
        .init(id: .topHalf, title: "Top Half", symbolName: "rectangle.tophalf.filled", availability: .available),
        .init(id: .bottomHalf, title: "Bottom Half", symbolName: "rectangle.bottomhalf.filled", availability: .available),
        .init(id: .topLeftQuarter, title: "Top Left Quarter", symbolName: "rectangle.topthird.inset.filled", availability: .available),
        .init(id: .topRightQuarter, title: "Top Right Quarter", symbolName: "rectangle.topthird.inset.filled", availability: .available),
        .init(id: .bottomLeftQuarter, title: "Bottom Left Quarter", symbolName: "rectangle.bottomthird.inset.filled", availability: .available),
        .init(id: .bottomRightQuarter, title: "Bottom Right Quarter", symbolName: "rectangle.bottomthird.inset.filled", availability: .available),
        .init(id: .restore, title: "Restore", symbolName: "arrow.uturn.backward", availability: .available),
        .init(id: .moveDisplayNext, title: "Move to Next Display", symbolName: "rectangle.portrait.arrowtriangle.2.outward", availability: .available),
        .init(id: .moveDisplayPrevious, title: "Move to Previous Display", symbolName: "rectangle.portrait.arrowtriangle.2.outward", availability: .available),
        .init(id: .cycleLeftEdge, title: "Cycle Left Edge", symbolName: "arrow.triangle.2.circlepath", availability: .available),
        .init(id: .leftThird, title: "Left Third", symbolName: "rectangle.lefthalf.filled", availability: .available),
        .init(id: .leftTwoThirds, title: "Left Two Thirds", symbolName: "rectangle.lefthalf.filled", availability: .available),
    ])
}

/// Maps a registered hotkey event to the one accepted Window Action execution seam.
struct HotkeyActionDispatcher: Sendable {
    private let windowActions: any WindowActionPerforming

    init(windowActions: any WindowActionPerforming) {
        self.windowActions = windowActions
    }

    func dispatch(_ invocation: HotkeyInvocation) async -> WindowActionResult {
        await windowActions.perform(
            .commit(
                action: invocation.actionID,
                source: .hotkey(bindingID: invocation.bindingID)
            )
        )
    }
}
