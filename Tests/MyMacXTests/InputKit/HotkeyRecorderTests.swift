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

@MainActor
final class HotkeyRecorderTests: XCTestCase {
    func testBeginningWhileAlreadyRecordingPublishesOnlyOneRecordingState() async {
        let input = InMemoryHotkeyRecorderInputAdapter()
        let recorder: any HotkeyRecording = HotkeyRecorder(input: input)
        let updates = await recorder.updates

        await recorder.begin()
        await recorder.begin()

        let firstState = await nextState(from: updates)
        let secondState = await nextState(from: updates, within: .milliseconds(50))
        XCTAssertEqual(firstState, .recording)
        XCTAssertNil(secondState)
    }

    func testRecordingCapturesFirstNonModifierKeyDownAsHardwareChord() async {
        let input = InMemoryHotkeyRecorderInputAdapter()
        let recorder: any HotkeyRecording = HotkeyRecorder(input: input)
        let updates = await recorder.updates

        await recorder.begin()
        input.send(.keyDown(hardwareKeyCode: 0x7B, modifiers: [.command, .option]))

        let states = await recordedStates(from: updates, count: 2)
        input.send(.keyDown(hardwareKeyCode: 0x00, modifiers: [.shift]))
        let laterState = await nextState(from: updates, within: .milliseconds(50))

        XCTAssertEqual(
            states,
            [
                .recording,
                .captured(
                    HotkeyChord(
                        hardwareKeyCode: 0x7B,
                        modifiers: [.command, .option]
                    )
                ),
            ]
        )
        XCTAssertNil(laterState)
    }

    func testIdleRecorderIgnoresInput() async {
        let input = InMemoryHotkeyRecorderInputAdapter()
        let recorder: any HotkeyRecording = HotkeyRecorder(input: input)
        let updates = await recorder.updates

        input.send(.keyDown(hardwareKeyCode: 0x7B, modifiers: [.command, .option]))

        let state = await nextState(from: updates, within: .milliseconds(50))
        XCTAssertNil(state)
    }

    func testRecordingIgnoresModifierTransitionsBeforeCapturingAKeyDown() async {
        let input = InMemoryHotkeyRecorderInputAdapter()
        let recorder: any HotkeyRecording = HotkeyRecorder(input: input)
        let updates = await recorder.updates

        await recorder.begin()
        input.send(.modifierTransition)
        input.send(.keyDown(hardwareKeyCode: 0x00, modifiers: [.shift]))

        let states = await recordedStates(from: updates, count: 2)
        XCTAssertEqual(
            states,
            [
                .recording,
                .captured(HotkeyChord(hardwareKeyCode: 0x00, modifiers: [.shift])),
            ]
        )
    }

    func testEscapeCancelsRecordingWithoutCapturingAChord() async {
        let input = InMemoryHotkeyRecorderInputAdapter()
        let recorder: any HotkeyRecording = HotkeyRecorder(input: input)
        let updates = await recorder.updates

        await recorder.begin()
        input.send(.keyDown(hardwareKeyCode: 53, modifiers: [.command]))

        let modifiedEscapeStates = await recordedStates(from: updates, count: 2)
        await recorder.begin()
        input.send(.keyDown(hardwareKeyCode: 53, modifiers: []))
        let unmodifiedEscapeStates = await recordedStates(from: updates, count: 2)
        XCTAssertEqual(
            modifiedEscapeStates,
            [.recording, .cancelled]
        )
        XCTAssertEqual(unmodifiedEscapeStates, [.recording, .cancelled])
    }

    func testClearEndsRecordingAndIsIdempotent() async {
        let input = InMemoryHotkeyRecorderInputAdapter()
        let recorder: any HotkeyRecording = HotkeyRecorder(input: input)
        let updates = await recorder.updates

        await recorder.begin()
        await recorder.clear()
        await recorder.clear()

        let states = await recordedStates(from: updates, count: 2)
        let thirdState = await nextState(from: updates, within: .milliseconds(50))
        XCTAssertEqual(
            states,
            [.recording, .cleared]
        )
        XCTAssertNil(thirdState)
    }

    func testClearWhileNotRecordingPublishesOneClearedState() async {
        let input = InMemoryHotkeyRecorderInputAdapter()
        let recorder: any HotkeyRecording = HotkeyRecorder(input: input)
        let updates = await recorder.updates

        await recorder.clear()
        await recorder.clear()

        let firstState = await nextState(from: updates)
        let secondState = await nextState(from: updates, within: .milliseconds(50))
        XCTAssertEqual(firstState, .cleared)
        XCTAssertNil(secondState)
    }

    func testPresenterUsesOrderedModifierSymbolsAndMappedKeyLabel() {
        let presenter: any HotkeyChordPresenting = HotkeyChordPresenter(
            labelResolver: FixedHotkeyKeyLabelResolver(labels: [0x7B: "Left Arrow"])
        )

        let presentation = presenter.present(
            HotkeyChord(
                hardwareKeyCode: 0x7B,
                modifiers: [.command, .option, .control]
            )
        )

        XCTAssertEqual(presentation.modifierSymbols, [.control, .option, .command])
        XCTAssertEqual(presentation.keyLabel, "Left Arrow")
        XCTAssertEqual(presentation.accessibilityLabel, "Control Option Command Left Arrow")
        XCTAssertFalse(presentation.usedHardwareCodeFallback)
    }

    func testPresenterUsesVisibleHardwareCodeFallbackWithoutChangingChordIdentity() {
        let presenter: any HotkeyChordPresenting = HotkeyChordPresenter(
            labelResolver: FixedHotkeyKeyLabelResolver(labels: [:])
        )
        let chord = HotkeyChord(hardwareKeyCode: 0x7B, modifiers: [.command])

        let presentation = presenter.present(chord)

        XCTAssertEqual(presentation.keyLabel, "Key code 0x7B")
        XCTAssertEqual(presentation.accessibilityLabel, "Command Key code 0x7B")
        XCTAssertTrue(presentation.usedHardwareCodeFallback)
        XCTAssertEqual(
            chord,
            HotkeyChord(hardwareKeyCode: 0x7B, modifiers: [.command])
        )
    }
}

@MainActor
private func recordedStates(
    from updates: AsyncStream<HotkeyRecorderState>,
    count: Int
) async -> [HotkeyRecorderState] {
    var iterator = updates.makeAsyncIterator()
    var states: [HotkeyRecorderState] = []
    while states.count < count, let state = await iterator.next() {
        states.append(state)
    }
    return states
}

@MainActor
private func nextState(
    from updates: AsyncStream<HotkeyRecorderState>,
    within duration: Duration = .seconds(1)
) async -> HotkeyRecorderState? {
    await withTaskGroup(of: HotkeyRecorderState?.self) { group in
        group.addTask {
            var iterator = updates.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: duration)
            return nil
        }

        let state = await group.next()!
        group.cancelAll()
        return state
    }
}

private struct FixedHotkeyKeyLabelResolver: HotkeyKeyLabelResolving {
    let labels: [UInt16: String]

    func label(for hardwareKeyCode: UInt16) -> String? {
        labels[hardwareKeyCode]
    }
}
