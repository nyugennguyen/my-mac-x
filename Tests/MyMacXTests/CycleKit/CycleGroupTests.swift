import XCTest

@testable import MyMacX

final class CycleGroupTests: XCTestCase {
    func testVerifiedCommitsTraverseTheOrderedActionsAndWrap() async throws {
        let cycles: some CycleGroupManaging = BoundedSessionCycleGroups(capacity: 4)
        let window = WindowIdentity()
        let group = try CycleGroup(
            key: CycleGroupKey(rawValue: "left-thirds"),
            actions: [action("left-half"), action("left-two-thirds"), action("left-third")]
        )

        let first = await cycles.stageNext(window: window, in: group)
        await cycles.commit(first)
        let second = await cycles.stageNext(window: window, in: group)
        await cycles.commit(second)
        let third = await cycles.stageNext(window: window, in: group)
        await cycles.commit(third)
        let wrapped = await cycles.stageNext(window: window, in: group)

        XCTAssertEqual(first.action, action("left-half"))
        XCTAssertEqual(second.action, action("left-two-thirds"))
        XCTAssertEqual(third.action, action("left-third"))
        XCTAssertEqual(wrapped.action, action("left-half"))
    }

    func testDiscardedOrFailedTransitionDoesNotAdvanceTheCycle() async throws {
        let cycles: some CycleGroupManaging = BoundedSessionCycleGroups(capacity: 4)
        let window = WindowIdentity()
        let group = try thirdsGroup()

        let failed = await cycles.stageNext(window: window, in: group)
        await cycles.discard(failed)
        let retry = await cycles.stageNext(window: window, in: group)
        await cycles.commit(retry)
        let afterVerifiedCommit = await cycles.stageNext(window: window, in: group)

        XCTAssertEqual(failed.action, action("left-half"))
        XCTAssertEqual(retry.action, action("left-half"))
        XCTAssertEqual(afterVerifiedCommit.action, action("left-two-thirds"))
    }

    func testOnlyOneOfTwoConcurrentStagesCanAdvanceTheSameCursor() async throws {
        let cycles: some CycleGroupManaging = BoundedSessionCycleGroups(capacity: 4)
        let window = WindowIdentity()
        let group = try thirdsGroup()

        let first = await cycles.stageNext(window: window, in: group)
        let duplicate = await cycles.stageNext(window: window, in: group)
        await cycles.commit(first)
        await cycles.commit(duplicate)
        let next = await cycles.stageNext(window: window, in: group)

        XCTAssertEqual(first.action, action("left-half"))
        XCTAssertEqual(duplicate.action, action("left-half"))
        XCTAssertEqual(next.action, action("left-two-thirds"))
    }

    func testStaleStageCannotAdvanceAfterAFullCycleWrapsToItsOriginalIndex() async throws {
        let cycles: some CycleGroupManaging = BoundedSessionCycleGroups(capacity: 4)
        let window = WindowIdentity()
        let group = try thirdsGroup()

        let staleFirst = await cycles.stageNext(window: window, in: group)
        let verifiedFirst = await cycles.stageNext(window: window, in: group)
        await cycles.commit(verifiedFirst)
        let verifiedSecond = await cycles.stageNext(window: window, in: group)
        await cycles.commit(verifiedSecond)
        let verifiedThird = await cycles.stageNext(window: window, in: group)
        await cycles.commit(verifiedThird)
        await cycles.commit(staleFirst)
        let afterStaleCommit = await cycles.stageNext(window: window, in: group)

        XCTAssertEqual(afterStaleCommit.action, action("left-half"))
    }

    func testSameKeyDefinitionChangeInvalidatesOlderStaging() async throws {
        let cycles: some CycleGroupManaging = BoundedSessionCycleGroups(capacity: 4)
        let window = WindowIdentity()
        let oldDefinition = try CycleGroup(
            key: CycleGroupKey(rawValue: "left"),
            actions: [action("left-half"), action("right-half")]
        )
        let replacement = try CycleGroup(
            key: oldDefinition.key,
            actions: [action("left-third"), action("left-two-thirds")]
        )

        let stale = await cycles.stageNext(window: window, in: oldDefinition)
        let current = await cycles.stageNext(window: window, in: replacement)
        await cycles.commit(current)
        await cycles.commit(stale)
        let next = await cycles.stageNext(window: window, in: replacement)

        XCTAssertEqual(next.action, action("left-two-thirds"))
    }

    func testWindowsAndGroupsKeepInterleavedCyclesIndependent() async throws {
        let cycles: some CycleGroupManaging = BoundedSessionCycleGroups(capacity: 4)
        let firstWindow = WindowIdentity()
        let secondWindow = WindowIdentity()
        let thirds = try thirdsGroup()
        let halves = try CycleGroup(
            key: CycleGroupKey(rawValue: "left-halves"),
            actions: [action("left-half"), action("right-half")]
        )

        let firstThird = await cycles.stageNext(window: firstWindow, in: thirds)
        await cycles.commit(firstThird)
        let firstHalf = await cycles.stageNext(window: firstWindow, in: halves)
        await cycles.commit(firstHalf)
        let secondThird = await cycles.stageNext(window: secondWindow, in: thirds)
        await cycles.commit(secondThird)

        let nextFirstThird = await cycles.stageNext(window: firstWindow, in: thirds)
        let nextFirstHalf = await cycles.stageNext(window: firstWindow, in: halves)
        let nextSecondThird = await cycles.stageNext(window: secondWindow, in: thirds)

        XCTAssertEqual(nextFirstThird.action, action("left-two-thirds"))
        XCTAssertEqual(nextFirstHalf.action, action("right-half"))
        XCTAssertEqual(nextSecondThird.action, action("left-two-thirds"))
    }

    func testResetAndInterruptionRestartTheAffectedCycleAndInvalidateStagedWork() async throws {
        let cycles: some CycleGroupManaging = BoundedSessionCycleGroups(capacity: 4)
        let window = WindowIdentity()
        let thirds = try thirdsGroup()
        let halves = try CycleGroup(
            key: CycleGroupKey(rawValue: "left-halves"),
            actions: [action("left-half"), action("right-half")]
        )

        let verifiedThird = await cycles.stageNext(window: window, in: thirds)
        await cycles.commit(verifiedThird)
        let staleHalf = await cycles.stageNext(window: window, in: halves)
        await cycles.reset(window: window, group: halves.key)
        await cycles.commit(staleHalf)
        let resetHalf = await cycles.stageNext(window: window, in: halves)
        await cycles.interrupt(window: window)
        let restartedThird = await cycles.stageNext(window: window, in: thirds)

        XCTAssertEqual(resetHalf.action, action("left-half"))
        XCTAssertEqual(restartedThird.action, action("left-half"))
    }

    func testPruningAndBoundedCapacityRemoveStaleCursorStateDeterministically() async throws {
        let cycles: some CycleGroupManaging = BoundedSessionCycleGroups(capacity: 2)
        let staleWindow = WindowIdentity()
        let retainedWindow = WindowIdentity()
        let newestWindow = WindowIdentity()
        let group = try thirdsGroup()

        let stale = await cycles.stageNext(window: staleWindow, in: group)
        await cycles.commit(stale)
        let retained = await cycles.stageNext(window: retainedWindow, in: group)
        await cycles.commit(retained)
        let newest = await cycles.stageNext(window: newestWindow, in: group)
        await cycles.commit(newest)
        let evictedStale = await cycles.stageNext(window: staleWindow, in: group)
        let retainedNext = await cycles.stageNext(window: retainedWindow, in: group)
        let pendingNewest = await cycles.stageNext(window: newestWindow, in: group)
        await cycles.prune(keeping: [retainedWindow])
        await cycles.commit(pendingNewest)
        let prunedNewest = await cycles.stageNext(window: newestWindow, in: group)

        XCTAssertEqual(evictedStale.action, action("left-half"))
        XCTAssertEqual(retainedNext.action, action("left-two-thirds"))
        XCTAssertEqual(prunedNewest.action, action("left-half"))
    }

    func testGroupRejectsAnEmptyKeyOrActionOrder() {
        XCTAssertThrowsError(try CycleGroup(key: CycleGroupKey(rawValue: ""), actions: [action("left-half")])) {
            XCTAssertEqual($0 as? CycleGroupValidationError, .emptyKey)
        }
        XCTAssertThrowsError(try CycleGroup(key: CycleGroupKey(rawValue: "left"), actions: [])) {
            XCTAssertEqual($0 as? CycleGroupValidationError, .emptyActions)
        }
    }

    private func thirdsGroup() throws -> CycleGroup {
        try CycleGroup(
            key: CycleGroupKey(rawValue: "left-thirds"),
            actions: [action("left-half"), action("left-two-thirds"), action("left-third")]
        )
    }

    private func action(_ rawValue: String) -> ActionID {
        ActionID(rawValue: rawValue)
    }
}
