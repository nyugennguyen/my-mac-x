import XCTest
@testable import MyMacX

final class SuperModeActionDispatcherTests: XCTestCase {
    func testAvailableActionDispatchesExactlyOnceThroughSuperModeCommit() async {
        let expectedWindowResult = WindowActionResult(
            disposition: .succeeded,
            effect: .none,
            undoToken: nil,
            warnings: []
        )
        let windowActions = RecordingSuperModeWindowActions(result: expectedWindowResult)
        let dispatcher = SuperModeActionDispatcher(
            actionRegistry: registry(action: .leftHalf, availability: .available),
            windowActions: windowActions
        )

        let result = await dispatcher.dispatch(.leftHalf)
        let commits = await windowActions.recordedCommits()

        XCTAssertEqual(result, .dispatched(expectedWindowResult))
        XCTAssertEqual(
            commits,
            [SuperModeRecordedCommit(action: .leftHalf, source: .superMode)]
        )
    }

    func testUnregisteredActionReturnsTypedUnavailableWithoutDispatch() async {
        let windowActions = RecordingSuperModeWindowActions()
        let dispatcher = SuperModeActionDispatcher(
            actionRegistry: ActionRegistry(actions: []),
            windowActions: windowActions
        )

        let result = await dispatcher.dispatch(.leftHalf)
        let commits = await windowActions.recordedCommits()

        XCTAssertEqual(result, .unavailable(.notRegistered))
        XCTAssertEqual(commits, [])
    }

    func testRegisteredUnavailableActionReturnsReasonWithoutDispatch() async {
        let windowActions = RecordingSuperModeWindowActions()
        let dispatcher = SuperModeActionDispatcher(
            actionRegistry: registry(
                action: .leftHalf,
                availability: .unavailable(.disabled)
            ),
            windowActions: windowActions
        )

        let result = await dispatcher.dispatch(.leftHalf)
        let commits = await windowActions.recordedCommits()

        XCTAssertEqual(result, .unavailable(.action(.disabled)))
        XCTAssertEqual(commits, [])
    }

    private func registry(
        action: ActionID,
        availability: ActionAvailability
    ) -> ActionRegistry {
        ActionRegistry(actions: [
            ActionDescriptor(
                id: action,
                title: "Test Window Action",
                symbolName: "rectangle",
                availability: availability
            ),
        ])
    }
}
