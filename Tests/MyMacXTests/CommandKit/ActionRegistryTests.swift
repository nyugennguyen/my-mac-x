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

import XCTest
@testable import MyMacX

final class ActionRegistryTests: XCTestCase {
    func testBuiltInActionsHaveStableUniqueIDs() {
        let actions = ActionRegistry.builtIn.actions

        XCTAssertEqual(
            actions.map(\.id.rawValue),
            [
                "window.maximize",
                "window.native-full-screen",
                "window.left-half",
                "window.right-half",
                "window.top-half",
                "window.bottom-half",
                "window.top-left-quarter",
                "window.top-right-quarter",
                "window.bottom-left-quarter",
                "window.bottom-right-quarter",
                "window.restore",
                "window.move-display-next",
                "window.move-display-previous",
                "window.cycle-left-edge",
                "window.left-third",
                "window.left-two-thirds",
            ]
        )
        XCTAssertEqual(Set(actions.map(\.id)).count, actions.count)
    }

    func testDisabledActionRemainsDiscoverableWithTypedAvailability() {
        let disabled = ActionDescriptor(
            id: ActionID(rawValue: "window.disabled-grid"),
            title: "Disabled Grid",
            symbolName: "square.grid.2x2",
            availability: .unavailable(.disabled)
        )
        let registry = ActionRegistry(actions: [disabled])

        XCTAssertEqual(registry.action(for: disabled.id), disabled)
        XCTAssertEqual(disabled.availability, .unavailable(.disabled))
    }

    func testActionMetadataIsLimitedToDisplaySafeValueTypes() throws {
        let action = try XCTUnwrap(ActionRegistry.builtIn.action(for: .leftHalf))

        XCTAssertEqual(action.title, "Left Half")
        XCTAssertEqual(action.symbolName, "rectangle.lefthalf.filled")
        XCTAssertEqual(action.availability, .available)
    }

    func testHotkeyInvocationDispatchesOnceWithExactBindingAndAction() async {
        let bindingID = UUID(uuidString: "90E0D434-DA13-4DB4-8CB2-54E5A832D62B")!
        let invocation = HotkeyInvocation(bindingID: bindingID, actionID: .leftHalf)
        let windowActions = RecordingWindowActions()
        let dispatcher = HotkeyActionDispatcher(windowActions: windowActions)

        _ = await dispatcher.dispatch(invocation)
        let commits = await windowActions.recordedCommits

        XCTAssertEqual(
            commits,
            [RecordedCommit(actionID: .leftHalf, bindingID: bindingID)]
        )
    }
}

private struct RecordedCommit: Equatable, Sendable {
    let actionID: ActionID
    let bindingID: UUID
}

private actor RecordingWindowActions: WindowActionPerforming {
    private(set) var recordedCommits: [RecordedCommit] = []

    func perform(_ intent: WindowIntent) async -> WindowActionResult {
        if case let .commit(action, .hotkey(bindingID)) = intent {
            recordedCommits.append(RecordedCommit(actionID: action, bindingID: bindingID))
        }

        return WindowActionResult(
            disposition: .succeeded,
            effect: .none,
            undoToken: nil,
            warnings: []
        )
    }
}
