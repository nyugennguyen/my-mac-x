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

import CoreGraphics
import XCTest

@testable import MyMacX

final class WindowHistoryTests: XCTestCase {
    func testDiscardedStageDoesNotCreateUndoHistory() async {
        let history = BoundedSessionWindowHistory(capacity: 3)
        let window = WindowIdentity()

        let stage = await history.stage(
            window: window,
            before: frame(x: 20, y: 30, width: 800, height: 600),
            destination: .layout
        )
        await history.discard(stage)

        let undo = await history.stageUndo(token: nil, for: window)
        let restore = await history.restore(for: window)
        XCTAssertNil(undo)
        XCTAssertNil(restore)
    }

    func testCommittedEntriesStayDistinctForTwoWindowsFromTheSameApplication() async {
        let history = BoundedSessionWindowHistory(capacity: 3)
        let firstWindow = WindowIdentity()
        let secondWindow = WindowIdentity()
        let firstBefore = frame(x: 20, y: 30, width: 800, height: 600)
        let secondBefore = frame(x: 860, y: 30, width: 800, height: 600)

        let firstToken = await commit(
            history,
            window: firstWindow,
            before: firstBefore,
            after: frame(x: 0, y: 0, width: 720, height: 900)
        )
        let secondToken = await commit(
            history,
            window: secondWindow,
            before: secondBefore,
            after: frame(x: 720, y: 0, width: 720, height: 900)
        )

        let firstUndo = await history.stageUndo(token: firstToken, for: firstWindow)
        let secondUndo = await history.stageUndo(token: secondToken, for: secondWindow)

        XCTAssertEqual(firstUndo?.targetFrame, firstBefore)
        XCTAssertEqual(secondUndo?.targetFrame, secondBefore)
        let wrongWindowUndo = await history.stageUndo(token: firstToken, for: secondWindow)
        XCTAssertNil(wrongWindowUndo)
    }

    func testNilUndoSelectsTheLatestCommittedEntryForTheCapturedWindow() async {
        let history = BoundedSessionWindowHistory(capacity: 3)
        let window = WindowIdentity()
        let original = frame(x: 20, y: 30, width: 800, height: 600)
        let firstSnap = frame(x: 0, y: 0, width: 720, height: 900)

        _ = await commit(history, window: window, before: original, after: firstSnap)
        _ = await commit(
            history,
            window: window,
            before: firstSnap,
            after: frame(x: 720, y: 0, width: 720, height: 900)
        )

        let undo = await history.stageUndo(token: nil, for: window)

        XCTAssertEqual(undo?.targetFrame, firstSnap)
    }

    func testExplicitUndoTokenSelectsThatExactEntryAndOnlyPrunesAfterCommit() async {
        let history = BoundedSessionWindowHistory(capacity: 3)
        let window = WindowIdentity()
        let original = frame(x: 20, y: 30, width: 800, height: 600)
        let firstSnap = frame(x: 0, y: 0, width: 720, height: 900)

        let firstToken = await commit(history, window: window, before: original, after: firstSnap)
        let secondToken = await commit(
            history,
            window: window,
            before: firstSnap,
            after: frame(x: 720, y: 0, width: 720, height: 900)
        )

        let undo = await history.stageUndo(token: secondToken, for: window)
        XCTAssertEqual(undo?.targetFrame, firstSnap)
        let pendingUndo = await history.stageUndo(token: secondToken, for: window)
        XCTAssertNotNil(pendingUndo)

        await history.commit(undo!)

        let consumedUndo = await history.stageUndo(token: secondToken, for: window)
        let latestUndo = await history.stageUndo(token: nil, for: window)
        let firstTokenUndo = await history.stageUndo(token: firstToken, for: window)
        XCTAssertNil(consumedUndo)
        XCTAssertEqual(
            latestUndo?.targetFrame,
            original
        )
        XCTAssertNotNil(firstTokenUndo)
    }

    func testCommittingOlderExplicitUndoInvalidatesThatWindowTimelineFromThatEntryForward() async {
        let history = BoundedSessionWindowHistory(capacity: 4)
        let window = WindowIdentity()
        let original = frame(x: 20, y: 30, width: 800, height: 600)
        let firstSnap = frame(x: 0, y: 0, width: 720, height: 900)

        let firstToken = await commit(history, window: window, before: original, after: firstSnap)
        let secondToken = await commit(
            history,
            window: window,
            before: firstSnap,
            after: frame(x: 720, y: 0, width: 720, height: 900)
        )

        let olderUndo = await history.stageUndo(token: firstToken, for: window)
        XCTAssertEqual(olderUndo?.targetFrame, original)
        await history.commit(olderUndo!)

        let latestUndo = await history.stageUndo(token: nil, for: window)
        let firstTokenUndo = await history.stageUndo(token: firstToken, for: window)
        let secondTokenUndo = await history.stageUndo(token: secondToken, for: window)
        XCTAssertNil(latestUndo)
        XCTAssertNil(firstTokenUndo)
        XCTAssertNil(secondTokenUndo)
    }

    func testCommittingOlderExplicitUndoLeavesOtherWindowTimelineUntouched() async {
        let history = BoundedSessionWindowHistory(capacity: 4)
        let firstWindow = WindowIdentity()
        let secondWindow = WindowIdentity()
        let originalFirst = frame(x: 20, y: 30, width: 800, height: 600)
        let firstSnap = frame(x: 0, y: 0, width: 720, height: 900)
        let originalSecond = frame(x: 860, y: 30, width: 800, height: 600)

        let firstToken = await commit(
            history,
            window: firstWindow,
            before: originalFirst,
            after: firstSnap
        )
        let secondWindowToken = await commit(
            history,
            window: secondWindow,
            before: originalSecond,
            after: frame(x: 720, y: 0, width: 720, height: 900)
        )
        let laterFirstToken = await commit(
            history,
            window: firstWindow,
            before: firstSnap,
            after: frame(x: 0, y: 0, width: 1440, height: 900)
        )

        let olderUndo = await history.stageUndo(token: firstToken, for: firstWindow)
        await history.commit(olderUndo!)

        let firstLatestUndo = await history.stageUndo(token: nil, for: firstWindow)
        let invalidatedFirstToken = await history.stageUndo(token: laterFirstToken, for: firstWindow)
        let secondWindowUndo = await history.stageUndo(token: secondWindowToken, for: secondWindow)
        XCTAssertNil(firstLatestUndo)
        XCTAssertNil(invalidatedFirstToken)
        XCTAssertEqual(secondWindowUndo?.targetFrame, originalSecond)
    }

    func testRestoreRetainsOriginalNonLayoutPlacementAcrossConsecutiveSnaps() async {
        let history = BoundedSessionWindowHistory(capacity: 3)
        let window = WindowIdentity()
        let original = frame(x: 42, y: 56, width: 800, height: 600)
        let leftSnap = frame(x: 0, y: 0, width: 720, height: 900)

        _ = await commit(history, window: window, before: original, after: leftSnap)
        _ = await commit(
            history,
            window: window,
            before: leftSnap,
            after: frame(x: 720, y: 0, width: 720, height: 900)
        )

        let restore = await history.restore(for: window)
        XCTAssertEqual(restore?.frame, original)
    }

    func testPruningStaleIdentityAlsoInvalidatesItsTokensAndPendingStages() async {
        let history = BoundedSessionWindowHistory(capacity: 3)
        let staleWindow = WindowIdentity()
        let liveWindow = WindowIdentity()
        let staleToken = await commit(
            history,
            window: staleWindow,
            before: frame(x: 20, y: 30, width: 800, height: 600),
            after: frame(x: 0, y: 0, width: 720, height: 900)
        )
        let staleStage = await history.stage(
            window: staleWindow,
            before: frame(x: 0, y: 0, width: 720, height: 900),
            destination: .layout
        )

        await history.prune(keeping: [liveWindow])

        let staleUndo = await history.stageUndo(token: staleToken, for: staleWindow)
        let staleRestore = await history.restore(for: staleWindow)
        let staleCommit = await history.commit(
            staleStage,
            actualFrame: frame(x: 720, y: 0, width: 720, height: 900)
        )
        XCTAssertNil(staleUndo)
        XCTAssertNil(staleRestore)
        XCTAssertNil(staleCommit)
    }

    func testBoundedCapacityEvictsOldestCommittedEntryInCommitOrder() async {
        let history = BoundedSessionWindowHistory(capacity: 2)
        let firstWindow = WindowIdentity()
        let secondWindow = WindowIdentity()
        let firstToken = await commit(
            history,
            window: firstWindow,
            before: frame(x: 20, y: 30, width: 800, height: 600),
            after: frame(x: 0, y: 0, width: 720, height: 900)
        )
        let secondToken = await commit(
            history,
            window: secondWindow,
            before: frame(x: 860, y: 30, width: 800, height: 600),
            after: frame(x: 720, y: 0, width: 720, height: 900)
        )
        let latestFirstToken = await commit(
            history,
            window: firstWindow,
            before: frame(x: 0, y: 0, width: 720, height: 900),
            after: frame(x: 0, y: 0, width: 1440, height: 900)
        )

        let evictedUndo = await history.stageUndo(token: firstToken, for: firstWindow)
        let retainedSecondUndo = await history.stageUndo(token: secondToken, for: secondWindow)
        let retainedLatestUndo = await history.stageUndo(token: latestFirstToken, for: firstWindow)
        XCTAssertNil(evictedUndo)
        XCTAssertNotNil(retainedSecondUndo)
        XCTAssertNotNil(retainedLatestUndo)
    }

    private func commit(
        _ history: some WindowHistoryManaging,
        window: WindowIdentity,
        before: AppKitGlobalLogicalFrame,
        after: AppKitGlobalLogicalFrame
    ) async -> UndoToken {
        let stage = await history.stage(window: window, before: before, destination: .layout)
        guard let token = await history.commit(stage, actualFrame: after) else {
            XCTFail("A staged verified mutation must commit one exact Undo token")
            fatalError("Missing Undo token")
        }
        return token
    }

    private func frame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> AppKitGlobalLogicalFrame {
        AppKitGlobalLogicalFrame(CGRect(x: x, y: y, width: width, height: height))
    }
}
