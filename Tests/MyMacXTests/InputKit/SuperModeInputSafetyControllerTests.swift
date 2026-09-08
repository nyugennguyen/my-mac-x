import CoreGraphics
import Foundation
import XCTest
@testable import MyMacX

final class SuperModeInputSafetyControllerTests: XCTestCase {
    func testRapidOneLevelSequenceConsumesOnlyOwnedDownEvents() async {
        let harness = makeHarness()

        let dispositions = [
            harness.controller.handle(prefix()),
            harness.controller.handle(keyDown(4, modifiers: [.maskControl])),
            harness.controller.handle(keyUp(4, modifiers: [.maskControl])),
            harness.controller.handle(keyDown(0)),
            harness.controller.handle(keyUp(0)),
        ]

        XCTAssertEqual(
            dispositions,
            [.consume, .consume, .passThrough, .passThrough, .passThrough]
        )
        await harness.recorder.waitForCount(2)
        XCTAssertEqual(harness.recorder.outcomes, [.armed, .execute(.maximize)])
    }

    func testRapidTwoLevelSequencesRemainOrderedAndReleaseNormalInput() async {
        let harness = makeHarness()

        for _ in 0..<100 {
            XCTAssertEqual(harness.controller.handle(prefix()), .consume)
            XCTAssertEqual(harness.controller.handle(keyDown(10)), .consume)
            XCTAssertEqual(harness.controller.handle(keyDown(11)), .consume)
            XCTAssertEqual(harness.controller.handle(keyUp(11)), .passThrough)
            XCTAssertEqual(harness.controller.handle(keyDown(0)), .passThrough)
            XCTAssertEqual(harness.controller.handle(keyUp(0)), .passThrough)
        }

        await harness.recorder.waitForCount(300)
        XCTAssertEqual(
            harness.recorder.outcomes.filter { $0 == .execute(.leftHalf) }.count,
            100
        )
    }

    func testCurrentTimeoutCancelsButCancelledStaleTimeoutCannotAffectNewSession() async {
        let harness = makeHarness()

        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        XCTAssertEqual(harness.controller.handle(keyDown(7)), .passThrough)
        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        await harness.recorder.waitForCount(3)

        harness.scheduler.fire(at: 0, evenIfCancelled: true)

        XCTAssertEqual(harness.controller.handle(keyUp(7)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyDown(4)), .consume)
        await harness.recorder.waitForCount(4)
        XCTAssertEqual(
            harness.recorder.outcomes,
            [
                .armed,
                .cancelled(.invalidKey(hardwareKeyCode: 7)),
                .armed,
                .execute(.maximize),
            ]
        )

        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        harness.scheduler.fire(at: 2)
        await harness.recorder.waitForCount(6)

        XCTAssertEqual(harness.recorder.outcomes.last, .cancelled(.timeout))
        XCTAssertEqual(harness.controller.handle(keyDown(0)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyUp(0)), .passThrough)
    }

    func testRepeatedKeyDownsNeverArmAdvanceOrExecute() async {
        let harness = makeHarness()

        XCTAssertEqual(harness.controller.handle(prefix(isRepeat: true)), .passThrough)
        XCTAssertTrue(harness.recorder.outcomes.isEmpty)

        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        XCTAssertEqual(harness.controller.handle(prefix(isRepeat: true)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyDown(4, isRepeat: true)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyDown(4)), .consume)
        XCTAssertEqual(harness.controller.handle(keyDown(4, isRepeat: true)), .passThrough)

        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        XCTAssertEqual(harness.controller.handle(keyDown(10, isRepeat: true)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyDown(10)), .consume)
        XCTAssertEqual(harness.controller.handle(keyDown(11, isRepeat: true)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyDown(11)), .consume)

        await harness.recorder.waitForCount(5)
        XCTAssertEqual(
            harness.recorder.outcomes.filter {
                if case .execute = $0 { return true }
                return false
            },
            [.execute(.maximize), .execute(.leftHalf)]
        )
    }

    func testKeyUpAndHeldOrReleasedModifiersAlwaysPassThrough() async {
        let harness = makeHarness()

        XCTAssertEqual(
            harness.controller.handle(flagsChanged(59, modifiers: [.maskControl])),
            .passThrough
        )
        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        XCTAssertEqual(
            harness.controller.handle(keyUp(49, modifiers: [.maskControl])),
            .passThrough
        )
        XCTAssertEqual(
            harness.controller.handle(flagsChanged(59, modifiers: [.maskControl])),
            .passThrough
        )
        XCTAssertEqual(
            harness.controller.handle(keyDown(4, modifiers: [.maskControl])),
            .consume
        )
        XCTAssertEqual(harness.controller.handle(keyUp(4, modifiers: [.maskControl])), .passThrough)
        XCTAssertEqual(harness.controller.handle(flagsChanged(59)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyUp(59)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyDown(0)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyUp(0)), .passThrough)
        await harness.recorder.waitForCount(2)
        XCTAssertEqual(harness.recorder.outcomes.last, .execute(.maximize))
    }

    func testPrefixRequiresExactNormalizedPrimaryModifiers() {
        let harness = makeHarness()

        XCTAssertEqual(harness.controller.handle(keyDown(49)), .passThrough)
        XCTAssertEqual(
            harness.controller.handle(keyDown(49, modifiers: [.maskControl, .maskShift])),
            .passThrough
        )
        XCTAssertEqual(
            harness.controller.handle(
                keyDown(49, modifiers: [.maskControl, .maskAlphaShift, .maskNumericPad])
            ),
            .consume
        )
        XCTAssertEqual(harness.controller.handle(keyDown(53)), .consume)
        XCTAssertEqual(harness.controller.handle(keyUp(53)), .passThrough)
    }

    func testInvalidInputAndEscapeReleaseFollowingCharactersAndModifiers() async {
        for enterSubmenu in [false, true] {
            let invalidHarness = makeHarness()
            XCTAssertEqual(invalidHarness.controller.handle(prefix()), .consume)
            if enterSubmenu {
                XCTAssertEqual(invalidHarness.controller.handle(keyDown(10)), .consume)
            }

            XCTAssertEqual(invalidHarness.controller.handle(keyDown(7)), .passThrough)
            XCTAssertEqual(invalidHarness.controller.handle(keyUp(7)), .passThrough)
            XCTAssertEqual(invalidHarness.controller.handle(flagsChanged(59)), .passThrough)
            XCTAssertEqual(invalidHarness.controller.handle(keyUp(59)), .passThrough)
            XCTAssertEqual(invalidHarness.controller.handle(keyDown(0)), .passThrough)
            XCTAssertEqual(invalidHarness.controller.handle(keyUp(0)), .passThrough)
            await invalidHarness.recorder.waitForCount(enterSubmenu ? 3 : 2)
            XCTAssertEqual(
                invalidHarness.recorder.outcomes.last,
                .cancelled(.invalidKey(hardwareKeyCode: 7))
            )

            let escapeHarness = makeHarness()
            XCTAssertEqual(escapeHarness.controller.handle(prefix()), .consume)
            if enterSubmenu {
                XCTAssertEqual(escapeHarness.controller.handle(keyDown(10)), .consume)
            }

            XCTAssertEqual(escapeHarness.controller.handle(keyDown(53)), .consume)
            XCTAssertEqual(escapeHarness.controller.handle(keyUp(53)), .passThrough)
            XCTAssertEqual(escapeHarness.controller.handle(flagsChanged(59)), .passThrough)
            XCTAssertEqual(escapeHarness.controller.handle(keyUp(59)), .passThrough)
            XCTAssertEqual(escapeHarness.controller.handle(keyDown(0)), .passThrough)
            XCTAssertEqual(escapeHarness.controller.handle(keyUp(0)), .passThrough)
            await escapeHarness.recorder.waitForCount(enterSubmenu ? 3 : 2)
            XCTAssertEqual(escapeHarness.recorder.outcomes.last, .cancelled(.escape))
        }
    }

    func testDisabledAndStoppedControllersFailOpenAndDisabledControllerRecovers() async {
        let harness = makeHarness()

        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        XCTAssertEqual(harness.controller.handle(.disabledByTimeout), .passThrough)
        await harness.recorder.waitForCount(2)
        XCTAssertEqual(harness.recorder.outcomes.last, .cancelled(.tapDisabled))
        XCTAssertEqual(harness.controller.handle(keyUp(49)), .passThrough)
        XCTAssertEqual(harness.controller.handle(flagsChanged(59)), .passThrough)

        harness.controller.setEnabled(false)
        XCTAssertEqual(harness.controller.handle(prefix()), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyDown(0)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyUp(0)), .passThrough)

        harness.controller.setEnabled(true)
        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        XCTAssertEqual(harness.controller.handle(keyDown(4)), .consume)

        XCTAssertEqual(harness.controller.handle(prefix()), .consume)
        XCTAssertEqual(harness.controller.handle(.disabledByUserInput), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyUp(49)), .passThrough)

        await harness.recorder.waitForCount(6)
        XCTAssertEqual(harness.recorder.outcomes.last, .cancelled(.tapDisabled))

        harness.controller.stop()
        XCTAssertEqual(harness.controller.handle(prefix()), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyDown(0)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyUp(0)), .passThrough)
        XCTAssertEqual(harness.controller.handle(flagsChanged(59)), .passThrough)
        XCTAssertEqual(harness.controller.handle(keyUp(59)), .passThrough)
    }
}

private extension SuperModeInputSafetyControllerTests {
    struct Harness {
        let controller: SuperModeInputSafetyController
        let scheduler: ManualSuperModeTimeoutScheduler
        let recorder: SuperModeInputSafetyTransitionRecorder
    }

    func makeHarness() -> Harness {
        let scheduler = ManualSuperModeTimeoutScheduler()
        let recorder = SuperModeInputSafetyTransitionRecorder()
        let controller = SuperModeInputSafetyController(
            snapshot: makeSnapshot(),
            scheduler: scheduler,
            onTransition: recorder.record
        )
        return Harness(controller: controller, scheduler: scheduler, recorder: recorder)
    }

    func makeSnapshot() -> SuperModeRuntimeSnapshot {
        let configuration = SuperModeConfiguration(
            prefix: HotkeyChord(hardwareKeyCode: 49, modifiers: [.control]),
            timeoutMilliseconds: 250,
            commandBindings: [
                SuperModeCommandBinding(hardwareKeyCodes: [4], actionID: .maximize),
                SuperModeCommandBinding(hardwareKeyCodes: [10, 11], actionID: .leftHalf),
            ]
        )
        let validator = SuperModeConfigurationValidator(actionRegistry: .builtIn)
        guard case let .valid(validated) = validator.validate(configuration, hotkeyBindings: []) else {
            XCTFail("Expected the test configuration to be valid")
            fatalError("Invalid test configuration")
        }
        return SuperModeRuntimeSnapshot(
            revision: SuperModeConfigurationRevision(rawValue: 1),
            configuration: validated.configuration,
            commandTree: validated.commandTree
        )
    }

    func prefix(isRepeat: Bool = false) -> EventTapSignal {
        keyDown(49, modifiers: [.maskControl], isRepeat: isRepeat)
    }

    func keyDown(
        _ hardwareKeyCode: UInt16,
        modifiers: CGEventFlags = [],
        isRepeat: Bool = false
    ) -> EventTapSignal {
        .key(
            EventTapKeySignal(
                kind: .keyDown,
                hardwareKeyCode: hardwareKeyCode,
                modifierFlags: modifiers.rawValue,
                isRepeat: isRepeat
            )
        )
    }

    func keyUp(
        _ hardwareKeyCode: UInt16,
        modifiers: CGEventFlags = []
    ) -> EventTapSignal {
        .key(
            EventTapKeySignal(
                kind: .keyUp,
                hardwareKeyCode: hardwareKeyCode,
                modifierFlags: modifiers.rawValue,
                isRepeat: false
            )
        )
    }

    func flagsChanged(
        _ hardwareKeyCode: UInt16,
        modifiers: CGEventFlags = []
    ) -> EventTapSignal {
        .key(
            EventTapKeySignal(
                kind: .flagsChanged,
                hardwareKeyCode: hardwareKeyCode,
                modifierFlags: modifiers.rawValue,
                isRepeat: false
            )
        )
    }
}

private final class SuperModeInputSafetyTransitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SuperModeInputSafetyTransition] = []

    var outcomes: [SuperModeOutcome] {
        lock.withLock { recorded.map(\.transition.outcome) }
    }

    func waitForCount(_ expectedCount: Int) async {
        while lock.withLock({ recorded.count }) < expectedCount {
            await Task.yield()
        }
    }

    func record(_ transition: SuperModeInputSafetyTransition) {
        lock.withLock { recorded.append(transition) }
    }
}

private final class ManualSuperModeTimeoutScheduler: SuperModeTimeoutScheduling, @unchecked Sendable {
    private struct ScheduledOperation {
        let token: ManualSuperModeScheduledTimeout
        let operation: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var operations: [ScheduledOperation] = []

    func schedule(
        afterMilliseconds _: UInt32,
        _ operation: @escaping @Sendable () -> Void
    ) -> any SuperModeScheduledTimeout {
        let token = ManualSuperModeScheduledTimeout()
        lock.withLock {
            operations.append(ScheduledOperation(token: token, operation: operation))
        }
        return token
    }

    func fire(at index: Int, evenIfCancelled: Bool = false) {
        let scheduled = lock.withLock { operations[index] }
        if evenIfCancelled || !scheduled.token.isCancelled {
            scheduled.operation()
        }
    }
}

private final class ManualSuperModeScheduledTimeout: SuperModeScheduledTimeout, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}
