import CoreGraphics
import XCTest

@testable import MyMacX

final class SnapInteractionStateMachineTests: XCTestCase {
    func testMouseUpCommitsTheSelectedPreviewExactlyOnceWithTheCapturedInteraction() async {
        let windowActions = RecordingSnapWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = InteractionID(
            UUID(uuidString: "59DC774E-93A4-427B-A43D-038326623906")!
        )
        let capturedWindow = capturedWindowIdentity

        _ = await stateMachine.consume(
            .pointer(.began(dragContext(interaction, capturedWindow: capturedWindow)))
        )
        _ = await stateMachine.consume(.trigger(.activated(DisplayID(rawValue: 7))))
        _ = await stateMachine.consume(.chooser(.selectionChanged(action: .leftHalf)))
        let committed = await stateMachine.consume(.pointer(.released(interaction: interaction)))
        let duplicateMouseUp = await stateMachine.consume(
            .pointer(.released(interaction: interaction))
        )
        let intents = await windowActions.recordedIntents()

        XCTAssertEqual(committed, .committedResult)
        XCTAssertNil(duplicateMouseUp)
        XCTAssertEqual(
            intents,
            [
                .preview(
                    action: .leftHalf,
                    interaction: interaction,
                    capturedWindow: capturedWindow,
                    targetDisplay: DisplayID(rawValue: 7)
                ),
                .commitPreview(interaction: interaction),
            ]
        )
    }

    func testEscapeCancelsThePreviewWithoutACommitOrFurtherMutation() async {
        let windowActions = RecordingSnapWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = interactionID("0C8265D8-7A5C-4E08-8770-DC9CE80C7356")

        await preparePreview(
            .rightHalf,
            interaction: interaction,
            in: stateMachine
        )
        let cancelled = await stateMachine.consume(.chooser(.cancelled))
        let mouseUpAfterEscape = await stateMachine.consume(
            .pointer(.released(interaction: interaction))
        )
        let intents = await windowActions.recordedIntents()

        XCTAssertEqual(cancelled, .cancelledResult)
        XCTAssertNil(mouseUpAfterEscape)
        XCTAssertEqual(
            intents,
            [
                .preview(
                    action: .rightHalf,
                    interaction: interaction,
                    capturedWindow: capturedWindowIdentity,
                    targetDisplay: DisplayID(rawValue: 7)
                ),
                .cancelPreview(interaction: interaction),
            ]
        )
    }

    func testDragOutCancelsThePreviewWithoutACommitOrFurtherMutation() async {
        let windowActions = RecordingSnapWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = interactionID("B3ED68B3-DDB4-4624-A1D1-A5C7F44BBE9C")
        let display = DisplayID(rawValue: 8)

        await preparePreview(
            .topLeftQuarter,
            interaction: interaction,
            display: display,
            in: stateMachine
        )
        let cancelled = await stateMachine.consume(.trigger(.deactivated(display)))
        let selectionAfterDragOut = await stateMachine.consume(
            .chooser(.selectionChanged(action: .bottomRightQuarter))
        )
        let intents = await windowActions.recordedIntents()

        XCTAssertEqual(cancelled, .cancelledResult)
        XCTAssertNil(selectionAfterDragOut)
        XCTAssertEqual(
            intents,
            [
                .preview(
                    action: .topLeftQuarter,
                    interaction: interaction,
                    capturedWindow: capturedWindowIdentity,
                    targetDisplay: DisplayID(rawValue: 8)
                ),
                .cancelPreview(interaction: interaction),
            ]
        )
    }

    func testKeyboardConfirmationPreviewsThenCommitsTheConfirmedActionOnce() async {
        let windowActions = RecordingSnapWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = interactionID("B8059193-F6B2-4842-8ED7-059E542B3D23")

        _ = await stateMachine.consume(.pointer(.began(dragContext(interaction))))
        _ = await stateMachine.consume(.trigger(.activated(DisplayID(rawValue: 9))))
        let confirmed = await stateMachine.consume(
            .chooser(.confirmed(action: .bottomHalf))
        )
        let mouseUpAfterConfirmation = await stateMachine.consume(
            .pointer(.released(interaction: interaction))
        )
        let intents = await windowActions.recordedIntents()

        XCTAssertEqual(confirmed, .committedResult)
        XCTAssertNil(mouseUpAfterConfirmation)
        XCTAssertEqual(
            intents,
            [
                .preview(
                    action: .bottomHalf,
                    interaction: interaction,
                    capturedWindow: capturedWindowIdentity,
                    targetDisplay: DisplayID(rawValue: 9)
                ),
                .commitPreview(interaction: interaction),
            ]
        )
    }

    func testPreviewFailureCancelsTheTransactionAndIgnoresLaterTerminalInput() async {
        let windowActions = RecordingSnapWindowActions(
            scriptedResults: [.rejectedResult, .cancelledResult]
        )
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = interactionID("6A3A0274-B95D-42ED-9296-3D20C88EA4AF")

        _ = await stateMachine.consume(.pointer(.began(dragContext(interaction))))
        _ = await stateMachine.consume(.trigger(.activated(DisplayID(rawValue: 10))))
        let failed = await stateMachine.consume(
            .chooser(.selectionChanged(action: .maximize))
        )
        let mouseUpAfterFailure = await stateMachine.consume(
            .pointer(.released(interaction: interaction))
        )
        let intents = await windowActions.recordedIntents()

        XCTAssertEqual(failed, .rejectedResult)
        XCTAssertNil(mouseUpAfterFailure)
        XCTAssertEqual(
            intents,
            [
                .preview(
                    action: .maximize,
                    interaction: interaction,
                    capturedWindow: capturedWindowIdentity,
                    targetDisplay: DisplayID(rawValue: 10)
                ),
                .cancelPreview(interaction: interaction),
            ]
        )
    }

    func testCommitFailureTerminatesWithoutRetryingTheWindowMutation() async {
        let windowActions = RecordingSnapWindowActions(
            scriptedResults: [.previewResult, .rejectedResult]
        )
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = interactionID("6125DC82-6D4F-470B-BE37-99E9EFC3F8BF")

        await preparePreview(.topHalf, interaction: interaction, in: stateMachine)
        let failed = await stateMachine.consume(.pointer(.released(interaction: interaction)))
        let duplicateMouseUp = await stateMachine.consume(
            .pointer(.released(interaction: interaction))
        )
        let intents = await windowActions.recordedIntents()

        XCTAssertEqual(failed, .rejectedResult)
        XCTAssertNil(duplicateMouseUp)
        XCTAssertEqual(
            intents,
            [
                .preview(
                    action: .topHalf,
                    interaction: interaction,
                    capturedWindow: capturedWindowIdentity,
                    targetDisplay: DisplayID(rawValue: 7)
                ),
                .commitPreview(interaction: interaction),
            ]
        )
    }

    func testPointerInterruptionCancelsAndStaleEventsCannotRetargetTheInteraction() async {
        let windowActions = RecordingSnapWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = interactionID("0B0A1457-D393-43C5-8B40-C6FED33B001F")
        let staleInteraction = interactionID("BA11600B-4D89-4DF2-8840-BB66EE34C749")

        await preparePreview(.leftHalf, interaction: interaction, in: stateMachine)
        let staleCancel = await stateMachine.consume(
            .pointer(.cancelled(interaction: staleInteraction))
        )
        let cancelled = await stateMachine.consume(
            .pointer(.cancelled(interaction: interaction))
        )
        let intents = await windowActions.recordedIntents()

        XCTAssertNil(staleCancel)
        XCTAssertEqual(cancelled, .cancelledResult)
        XCTAssertEqual(
            intents,
            [
                .preview(
                    action: .leftHalf,
                    interaction: interaction,
                    capturedWindow: capturedWindowIdentity,
                    targetDisplay: DisplayID(rawValue: 7)
                ),
                .cancelPreview(interaction: interaction),
            ]
        )
    }

    func testDuplicateBeginCannotRetargetAnInteractionToAnotherWindowIdentity() async {
        let windowActions = RecordingSnapWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = interactionID("31E16764-3781-41A2-91D8-90816D202BD2")
        let originalWindow = capturedWindowIdentity
        let retargetedWindow = WindowIdentity()

        _ = await stateMachine.consume(
            .pointer(.began(dragContext(interaction, capturedWindow: originalWindow)))
        )
        _ = await stateMachine.consume(
            .pointer(.began(dragContext(interaction, capturedWindow: retargetedWindow)))
        )
        _ = await stateMachine.consume(.trigger(.activated(DisplayID(rawValue: 7))))
        _ = await stateMachine.consume(.chooser(.selectionChanged(action: .leftHalf)))
        let intents = await windowActions.recordedIntents()

        XCTAssertEqual(
            intents,
            [
                .preview(
                    action: .leftHalf,
                    interaction: interaction,
                    capturedWindow: originalWindow,
                    targetDisplay: DisplayID(rawValue: 7)
                ),
            ]
        )
    }

    // MARK: - SOL Finding 3: AX Adapter identity must be shared with Window Action Module

    func testCapturedWindowIdentityPersistsThroughFocusChangeAndMultiplePreviews() async {
        let windowActions = RecordingSnapWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let interaction = interactionID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
        let originalWindow = WindowIdentity(
            rawValue: UUID(uuidString: "D4F7A210-3B8E-4C6D-9F52-1A0E8B7C6D54")!
        )
        let focusChangedWindow = WindowIdentity(
            rawValue: UUID(uuidString: "E5A8B321-4C9F-5D7E-A063-2B1F9C8D7E65")!
        )

        _ = await stateMachine.consume(
            .pointer(.began(dragContext(interaction, capturedWindow: originalWindow)))
        )
        _ = await stateMachine.consume(.trigger(.activated(DisplayID(rawValue: 7))))

        // First preview — must carry originalWindow.
        _ = await stateMachine.consume(.chooser(.selectionChanged(action: .leftHalf)))

        // Simulate focus change: duplicate .began with different window, same interaction.
        _ = await stateMachine.consume(
            .pointer(.began(dragContext(interaction, capturedWindow: focusChangedWindow)))
        )

        // Second preview after focus change — must STILL carry originalWindow.
        _ = await stateMachine.consume(.chooser(.selectionChanged(action: .rightHalf)))

        // Third preview — identity must still be originalWindow.
        _ = await stateMachine.consume(.chooser(.selectionChanged(action: .maximize)))

        let intents = await windowActions.recordedIntents()

        XCTAssertEqual(intents.count, 3)
        XCTAssertEqual(
            intents[0],
            .preview(
                action: .leftHalf,
                interaction: interaction,
                capturedWindow: originalWindow,
                targetDisplay: DisplayID(rawValue: 7)
            )
        )
        XCTAssertEqual(
            intents[1],
            .preview(
                action: .rightHalf,
                interaction: interaction,
                capturedWindow: originalWindow,
                targetDisplay: DisplayID(rawValue: 7)
            )
        )
        XCTAssertEqual(
            intents[2],
            .preview(
                action: .maximize,
                interaction: interaction,
                capturedWindow: originalWindow,
                targetDisplay: DisplayID(rawValue: 7)
            )
        )
    }
}

// MARK: - Test Helpers

private actor RecordingSnapWindowActions: WindowActionPerforming {
    private var intents: [RecordedSnapWindowIntent] = []
    private var scriptedResults: [WindowActionResult]

    init(scriptedResults: [WindowActionResult] = []) {
        self.scriptedResults = scriptedResults
    }

    func perform(_ intent: WindowIntent) -> WindowActionResult {
        let defaultResult: WindowActionResult
        switch intent {
        case let .preview(action, interaction, capturedWindow, targetDisplay):
            intents.append(
                .preview(
                    action: action,
                    interaction: interaction,
                    capturedWindow: capturedWindow,
                    targetDisplay: targetDisplay
                )
            )
            defaultResult = .previewResult
        case .commitPreview(let interaction):
            intents.append(.commitPreview(interaction: interaction))
            defaultResult = .committedResult
        case .cancelPreview(let interaction):
            intents.append(.cancelPreview(interaction: interaction))
            defaultResult = .cancelledResult
        case .commit, .undo:
            XCTFail("Snap interaction must use preview transaction intents only")
            defaultResult = .rejectedResult
        }
        return scriptedResults.isEmpty ? defaultResult : scriptedResults.removeFirst()
    }

    func recordedIntents() -> [RecordedSnapWindowIntent] {
        intents
    }
}

private enum RecordedSnapWindowIntent: Equatable {
    case preview(
        action: ActionID,
        interaction: InteractionID,
        capturedWindow: WindowIdentity?,
        targetDisplay: DisplayID? = nil
    )
    case commitPreview(interaction: InteractionID)
    case cancelPreview(interaction: InteractionID)
}

private let capturedWindowIdentity = WindowIdentity(
    rawValue: UUID(uuidString: "E34969D1-7E31-4964-9998-F2954AD67372")!
)

private func dragContext(
    _ interaction: InteractionID,
    capturedWindow: WindowIdentity = capturedWindowIdentity
) -> PointerDragContext {
    PointerDragContext(
        interaction: interaction,
        capturedWindow: capturedWindow,
        pointerLocation: CGPoint(x: 640, y: 22)
    )
}

private func interactionID(_ value: String) -> InteractionID {
    InteractionID(UUID(uuidString: value)!)
}

private func preparePreview(
    _ action: ActionID,
    interaction: InteractionID,
    display: DisplayID = DisplayID(rawValue: 7),
    in stateMachine: SnapInteractionStateMachine
) async {
    _ = await stateMachine.consume(.pointer(.began(dragContext(interaction))))
    _ = await stateMachine.consume(.trigger(.activated(display)))
    _ = await stateMachine.consume(.chooser(.selectionChanged(action: action)))
}

private extension WindowActionResult {
    static let previewResult = WindowActionResult(
        disposition: .succeeded,
        effect: .preview(
            frame: CGRect(x: 0, y: 0, width: 720, height: 900),
            displayID: 7,
            constrained: false
        ),
        undoToken: nil,
        warnings: []
    )

    static let committedResult = WindowActionResult(
        disposition: .succeeded,
        effect: .committed(
            actualFrame: CGRect(x: 0, y: 0, width: 720, height: 900),
            constrained: false
        ),
        undoToken: nil,
        warnings: []
    )

    static let cancelledResult = WindowActionResult(
        disposition: .cancelled,
        effect: .none,
        undoToken: nil,
        warnings: []
    )

    static let rejectedResult = WindowActionResult(
        disposition: .rejected(.previewMissingOrExpired),
        effect: .none,
        undoToken: nil,
        warnings: []
    )
}
