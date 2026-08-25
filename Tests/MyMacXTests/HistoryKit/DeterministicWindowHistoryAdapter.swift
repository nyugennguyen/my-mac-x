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
