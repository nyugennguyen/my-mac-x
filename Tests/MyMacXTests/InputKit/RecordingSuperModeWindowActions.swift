import Foundation
@testable import MyMacX

struct SuperModeRecordedCommit: Equatable, Sendable {
    let action: ActionID
    let source: ActionSource
}

actor RecordingSuperModeWindowActions: WindowActionPerforming {
    private var commits: [SuperModeRecordedCommit] = []
    private let result: WindowActionResult

    init(
        result: WindowActionResult = WindowActionResult(
            disposition: .succeeded,
            effect: .none,
            undoToken: nil,
            warnings: []
        )
    ) {
        self.result = result
    }

    func perform(_ intent: WindowIntent) async -> WindowActionResult {
        if case let .commit(action, source) = intent {
            commits.append(SuperModeRecordedCommit(action: action, source: source))
        }
        return result
    }

    func recordedCommits() -> [SuperModeRecordedCommit] {
        commits
    }
}
