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
