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

enum SuperModeDispatchUnavailability: Equatable, Sendable {
    case notRegistered
    case action(ActionUnavailability)
}

enum SuperModeDispatchResult: Equatable, Sendable {
    case dispatched(WindowActionResult)
    case dispatchedAppAction
    case unavailable(SuperModeDispatchUnavailability)
}

/// The sole Super Mode execution Adapter. Availability is resolved before the shared
/// Window Action Interface is crossed, and an available action is performed exactly once.
struct SuperModeActionDispatcher: Sendable {
    private let actionRegistry: ActionRegistry
    private let windowActions: any WindowActionPerforming

    init(
        actionRegistry: ActionRegistry,
        windowActions: any WindowActionPerforming
    ) {
        self.actionRegistry = actionRegistry
        self.windowActions = windowActions
    }

    func dispatch(_ action: ActionID) async -> SuperModeDispatchResult {
        guard let descriptor = actionRegistry.action(for: action) else {
            return .unavailable(.notRegistered)
        }

        guard case .available = descriptor.availability else {
            guard case let .unavailable(reason) = descriptor.availability else {
                preconditionFailure("Unhandled ActionAvailability")
            }
            return .unavailable(.action(reason))
        }

        let result = await windowActions.perform(
            .commit(action: action, source: .superMode)
        )
        return .dispatched(result)
    }
}
