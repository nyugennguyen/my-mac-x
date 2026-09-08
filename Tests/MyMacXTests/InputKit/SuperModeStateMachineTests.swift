import XCTest
@testable import MyMacX

final class SuperModeStateMachineTests: XCTestCase {
    func testIdlePrefixArmsNewSessionAndConsumes() {
        var reducer = makeReducer()

        let transition = reducer.reduce(.prefix)
        let session = armedSession(in: transition.current)

        XCTAssertEqual(
            transition,
            SuperModeTransition(
                previous: .idle,
                current: .armed(session: session),
                disposition: .consume,
                outcome: .armed
            )
        )
    }

    func testIdleNonPrefixInputsPassThroughWithoutChangingPresentation() {
        let events: [SuperModeInput] = [
            .keyDown(hardwareKeyCode: 99),
            .escape,
            .timeout(session: SuperModeSessionID(rawValue: 1)),
            .tapDisabled,
            .stop,
        ]

        for event in events {
            var reducer = makeReducer()

            XCTAssertEqual(
                reducer.reduce(event),
                SuperModeTransition(
                    previous: .idle,
                    current: .idle,
                    disposition: .passThrough,
                    outcome: .none
                ),
                "Unexpected idle transition for \(event)"
            )
        }
    }

    func testArmedOneLevelKeyExecutesExactActionAndResetsBeforeReturning() {
        var reducer = makeReducer()
        let armed = reducer.reduce(.prefix).current

        XCTAssertEqual(
            reducer.reduce(.keyDown(hardwareKeyCode: 4)),
            SuperModeTransition(
                previous: armed,
                current: .idle,
                disposition: .consume,
                outcome: .execute(.leftHalf)
            )
        )
        XCTAssertEqual(reducer.presentation, .idle)
    }

    func testTwoLevelSequenceEntersSubmenuThenExecutesExactAction() {
        var reducer = makeReducer()
        let armed = reducer.reduce(.prefix).current
        let session = armedSession(in: armed)

        let entered = reducer.reduce(.keyDown(hardwareKeyCode: 10))
        XCTAssertEqual(
            entered,
            SuperModeTransition(
                previous: armed,
                current: .submenu(session: session, hardwareKeyCode: 10),
                disposition: .consume,
                outcome: .submenuEntered
            )
        )

        XCTAssertEqual(
            reducer.reduce(.keyDown(hardwareKeyCode: 11)),
            SuperModeTransition(
                previous: entered.current,
                current: .idle,
                disposition: .consume,
                outcome: .execute(.rightHalf)
            )
        )
        XCTAssertEqual(reducer.presentation, .idle)
    }

    func testInvalidArmedKeyCancelsButPassesKeyThrough() {
        var reducer = makeReducer()
        let armed = reducer.reduce(.prefix).current

        XCTAssertEqual(
            reducer.reduce(.keyDown(hardwareKeyCode: 99)),
            SuperModeTransition(
                previous: armed,
                current: .idle,
                disposition: .passThrough,
                outcome: .cancelled(.invalidKey(hardwareKeyCode: 99))
            )
        )
    }

    func testInvalidSubmenuKeyCancelsButPassesKeyThrough() {
        var reducer = makeReducer()
        _ = reducer.reduce(.prefix)
        let submenu = reducer.reduce(.keyDown(hardwareKeyCode: 10)).current

        XCTAssertEqual(
            reducer.reduce(.keyDown(hardwareKeyCode: 99)),
            SuperModeTransition(
                previous: submenu,
                current: .idle,
                disposition: .passThrough,
                outcome: .cancelled(.invalidKey(hardwareKeyCode: 99))
            )
        )
    }

    func testEscapeCancelsEachActivePresentationAndConsumes() {
        for enterSubmenu in [false, true] {
            var reducer = makeReducer()
            _ = reducer.reduce(.prefix)
            if enterSubmenu {
                _ = reducer.reduce(.keyDown(hardwareKeyCode: 10))
            }
            let active = reducer.presentation

            XCTAssertEqual(
                reducer.reduce(.escape),
                SuperModeTransition(
                    previous: active,
                    current: .idle,
                    disposition: .consume,
                    outcome: .cancelled(.escape)
                )
            )
        }
    }

    func testRepeatedPrefixCancelsEachActivePresentationAndConsumes() {
        for enterSubmenu in [false, true] {
            var reducer = makeReducer()
            _ = reducer.reduce(.prefix)
            if enterSubmenu {
                _ = reducer.reduce(.keyDown(hardwareKeyCode: 10))
            }
            let active = reducer.presentation

            XCTAssertEqual(
                reducer.reduce(.prefix),
                SuperModeTransition(
                    previous: active,
                    current: .idle,
                    disposition: .consume,
                    outcome: .cancelled(.repeatedPrefix)
                )
            )
        }
    }

    func testCurrentSessionTimeoutCancelsAndPassesThrough() {
        var reducer = makeReducer()
        let armed = reducer.reduce(.prefix).current
        let session = armedSession(in: armed)

        XCTAssertEqual(
            reducer.reduce(.timeout(session: session)),
            SuperModeTransition(
                previous: armed,
                current: .idle,
                disposition: .passThrough,
                outcome: .cancelled(.timeout)
            )
        )
    }

    func testStaleTimeoutDoesNotAffectNewerMonotonicSession() {
        var reducer = makeReducer()
        let firstSession = armedSession(in: reducer.reduce(.prefix).current)
        _ = reducer.reduce(.prefix)
        let secondArmed = reducer.reduce(.prefix).current
        let secondSession = armedSession(in: secondArmed)

        XCTAssertGreaterThan(secondSession.rawValue, firstSession.rawValue)
        XCTAssertEqual(
            reducer.reduce(.timeout(session: firstSession)),
            SuperModeTransition(
                previous: secondArmed,
                current: secondArmed,
                disposition: .passThrough,
                outcome: .none
            )
        )
    }

    func testTapDisableCancelsEachActivePresentationImmediately() {
        assertInfrastructureCancellation(input: .tapDisabled, reason: .tapDisabled)
    }

    func testStopCancelsEachActivePresentationImmediately() {
        assertInfrastructureCancellation(input: .stop, reason: .stopped)
    }

    private func assertInfrastructureCancellation(
        input: SuperModeInput,
        reason: SuperModeCancellationReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for enterSubmenu in [false, true] {
            var reducer = makeReducer()
            _ = reducer.reduce(.prefix)
            if enterSubmenu {
                _ = reducer.reduce(.keyDown(hardwareKeyCode: 10))
            }
            let active = reducer.presentation

            XCTAssertEqual(
                reducer.reduce(input),
                SuperModeTransition(
                    previous: active,
                    current: .idle,
                    disposition: .passThrough,
                    outcome: .cancelled(reason)
                ),
                file: file,
                line: line
            )
        }
    }

    private func makeReducer() -> SuperModeReducer {
        SuperModeReducer(
            commandTree: SuperModeCommandTree(
                oneLevel: [4: .leftHalf],
                twoLevel: [10: [11: .rightHalf, 12: .maximize]]
            )
        )
    }

    private func armedSession(
        in presentation: SuperModePresentationState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SuperModeSessionID {
        guard case let .armed(session) = presentation else {
            XCTFail("Expected armed presentation, got \(presentation)", file: file, line: line)
            return SuperModeSessionID(rawValue: 0)
        }
        return session
    }
}
