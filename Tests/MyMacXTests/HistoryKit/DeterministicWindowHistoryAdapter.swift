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

/// A deterministic test Adapter for callers that need prearranged history outcomes.
actor DeterministicWindowHistoryAdapter: WindowHistoryManaging {
    enum Outcome: Sendable {
        case undo(WindowHistoryUndo?)
        case restore(WindowRestoreAnchor?)
    }

    private let outcomes: [Outcome]
    private var cursor = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func stage(
        window: WindowIdentity,
        before: AppKitGlobalLogicalFrame,
        destination: WindowHistoryPlacement
    ) -> WindowHistoryStaging {
        WindowHistoryStaging()
    }

    func commit(
        _ staging: WindowHistoryStaging,
        actualFrame: AppKitGlobalLogicalFrame
    ) -> UndoToken? {
        UndoToken()
    }

    func discard(_ staging: WindowHistoryStaging) {}

    func stageUndo(token: UndoToken?, for window: WindowIdentity) -> WindowHistoryUndo? {
        nextUndoOutcome()
    }

    func commit(_ undo: WindowHistoryUndo) {}

    func discard(_ undo: WindowHistoryUndo) {}

    func restore(for window: WindowIdentity) -> WindowRestoreAnchor? {
        nextRestoreOutcome()
    }

    func prune(keeping windows: Set<WindowIdentity>) {}

    private func nextUndoOutcome() -> WindowHistoryUndo? {
        guard cursor < outcomes.count else { return nil }
        defer { cursor += 1 }
        guard case let .undo(value) = outcomes[cursor] else { return nil }
        return value
    }

    private func nextRestoreOutcome() -> WindowRestoreAnchor? {
        guard cursor < outcomes.count else { return nil }
        defer { cursor += 1 }
        guard case let .restore(value) = outcomes[cursor] else { return nil }
        return value
    }
}
