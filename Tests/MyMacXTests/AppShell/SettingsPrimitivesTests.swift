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

import AppKit
import SwiftUI
import XCTest
@testable import MyMacX

final class SettingsPrimitivesTests: XCTestCase {

    // MARK: - 1. Recorder State Machine Tests

    func testRecorderStateMachineTransitionsThroughAllLifecycleStates() {
        let initialChord = KeyChord(modifiers: [.control, .option], key: "M")
        let defaultChord = KeyChord(modifiers: [.control], key: "Space")

        var model = ShortcutRecorderModel(
            currentChord: initialChord,
            defaultChord: defaultChord,
            conflictValidator: { chord in
                if chord.key == "D" {
                    return "Conflicts with system shortcut"
                }
                return nil
            }
        )

        // 1. Initial State: Idle with current chord
        XCTAssertEqual(model.state, .idle(chord: initialChord))
        XCTAssertFalse(model.isListening)
        XCTAssertNil(model.conflictMessage)
        XCTAssertTrue(model.canClear)
        XCTAssertTrue(model.canReset)

        // 2. Start Recording -> Listening
        model.startRecording()
        XCTAssertEqual(model.state, .listening)
        XCTAssertTrue(model.isListening)
        XCTAssertNil(model.conflictMessage)

        // 3. Cancel Recording -> Returns to previous idle
        model.cancelRecording()
        XCTAssertEqual(model.state, .idle(chord: initialChord))
        XCTAssertFalse(model.isListening)

        // 4. Record new valid shortcut -> Idle with new chord
        model.startRecording()
        let newChord = KeyChord(modifiers: [.command, .shift], key: "P")
        model.record(chord: newChord)
        XCTAssertEqual(model.state, .idle(chord: newChord))
        XCTAssertEqual(model.currentChord, newChord)
        XCTAssertNil(model.conflictMessage)

        // 5. Record conflicting shortcut -> Conflict state with message
        model.startRecording()
        let conflictChord = KeyChord(modifiers: [.control, .option], key: "D")
        model.record(chord: conflictChord)
        XCTAssertEqual(model.state, .conflict(chord: conflictChord, reason: "Conflicts with system shortcut"))
        XCTAssertEqual(model.currentChord, conflictChord)
        XCTAssertEqual(model.conflictMessage, "Conflicts with system shortcut")
        XCTAssertTrue(model.hasConflict)

        // 6. Clear shortcut -> Idle with nil
        model.clear()
        XCTAssertEqual(model.state, .idle(chord: nil))
        XCTAssertNil(model.currentChord)
        XCTAssertNil(model.conflictMessage)
        XCTAssertFalse(model.canClear)
        XCTAssertTrue(model.canReset)

        // 7. Reset shortcut -> Restores defaultChord
        model.reset()
        XCTAssertEqual(model.state, .idle(chord: defaultChord))
        XCTAssertEqual(model.currentChord, defaultChord)
        XCTAssertFalse(model.canReset)
    }

    func testRecorderButtonHasFixedWidthAndSingleFontSpec() {
        XCTAssertEqual(ShortcutRecorderLayout.buttonWidth, 108.0, "Recorder button must have fixed width ~108 pt")
        XCTAssertEqual(ShortcutRecorderLayout.buttonHeight, 26.0, "Recorder button height is 26 pt")
        XCTAssertEqual(ShortcutRecorderLayout.font, SettingsTypography.keycap, "Single font must be used in all states to prevent width jitter")
    }

    func testKeyChordModifierSortingNormalizesOrder() {
        let unsortedChord = KeyChord(modifiers: [.command, .shift, .control, .option], key: "K")
        XCTAssertEqual(unsortedChord.modifiers, [.control, .option, .shift, .command])
        XCTAssertEqual(unsortedChord.displayKeys, ["⌃", "⌥", "⇧", "⌘", "K"])
        XCTAssertEqual(unsortedChord.displayString, "⌃⌥⇧⌘K")
    }

    func testKeyChordDeduplicatesModifiers() {
        let duplicateChord = KeyChord(modifiers: [.command, .control, .command, .shift, .control], key: "K")
        XCTAssertEqual(duplicateChord.modifiers, [.control, .shift, .command])
        XCTAssertEqual(duplicateChord.displayKeys, ["⌃", "⇧", "⌘", "K"])
        XCTAssertEqual(duplicateChord.displayString, "⌃⇧⌘K")
    }

    func testCancelRecordingPreservesPriorConflictState() {
        let chord = KeyChord(modifiers: [.control], key: "A")
        var model = ShortcutRecorderModel(
            currentChord: chord,
            conflictValidator: { _ in "Duplicate binding with Mission Control" }
        )
        model.record(chord: chord)
        XCTAssertTrue(model.hasConflict)
        XCTAssertEqual(model.conflictMessage, "Duplicate binding with Mission Control")
        XCTAssertEqual(model.state, .conflict(chord: chord, reason: "Duplicate binding with Mission Control"))

        model.startRecording()
        XCTAssertTrue(model.isListening)
        XCTAssertEqual(model.state, .listening)
        XCTAssertNil(model.conflictMessage)

        model.cancelRecording()
        XCTAssertFalse(model.isListening)
        XCTAssertTrue(model.hasConflict, "Cancelling recording must restore/retain prior conflict state")
        XCTAssertEqual(model.conflictMessage, "Duplicate binding with Mission Control")
        XCTAssertEqual(model.state, .conflict(chord: chord, reason: "Duplicate binding with Mission Control"))
        XCTAssertEqual(model.currentChord, chord)
    }

    func testSettingsRowSubcontentInsetModel() {
        XCTAssertEqual(SettingsRowLayout.subcontentInset(hasIcon: true), 38.0, "Subcontent with icon indents 38 pt")
        XCTAssertEqual(SettingsRowLayout.subcontentInset(hasIcon: false), 0.0, "Subcontent without icon has 0 pt indent to align with title")
    }

    func testShortcutRecorderModelEdgeCases() {
        var model = ShortcutRecorderModel(
            currentChord: nil,
            defaultChord: nil,
            conflictValidator: nil
        )

        // Clear when already nil is safe no-op
        model.clear()
        XCTAssertEqual(model.state, .idle(chord: nil))
        XCTAssertFalse(model.canClear)
        XCTAssertFalse(model.canReset)

        // Reset when defaultChord is nil sets chord to nil
        model.reset()
        XCTAssertEqual(model.state, .idle(chord: nil))

        // Start recording from conflict state, cancel returns to recorded chord
        let chord = KeyChord(modifiers: [.control], key: "A")
        var conflictModel = ShortcutRecorderModel(
            currentChord: chord,
            conflictValidator: { _ in "Conflict" }
        )
        conflictModel.record(chord: chord)
        XCTAssertTrue(conflictModel.hasConflict)

        conflictModel.startRecording()
        XCTAssertTrue(conflictModel.isListening)
        conflictModel.cancelRecording()
        XCTAssertEqual(conflictModel.currentChord, chord)
    }

    func testKeycapChainModelAccessibilityConversions() {
        let keys = ["←", "→", "↑", "↓", "⌫", "⌦", "↩", "⇥", " "]
        let chain = KeycapChainModel(keys: keys)
        XCTAssertEqual(
            chain.accessibleText,
            "Left Arrow, Right Arrow, Up Arrow, Down Arrow, Backspace, Forward Delete, Return, Tab, Space"
        )
    }

    // MARK: - 2. Keycap Chain Layout Model Tests

    func testKeycapChainLayoutModelBuildsSingleChordsAndChainedSequences() {
        // Single chord
        let singleModel = KeycapChainModel(keys: ["⌃", "⌥", "←"])
        XCTAssertEqual(singleModel.segments.count, 3)
        XCTAssertEqual(singleModel.segments, [
            .key("⌃"),
            .key("⌥"),
            .key("←")
        ])
        XCTAssertFalse(singleModel.hasArrowSeparators)
        XCTAssertEqual(singleModel.accessibleText, "Control, Option, Left Arrow")

        // Chained sequence with arrow steps (e.g. Super Mode tree: ⌃ Space ▸ 1)
        let chainedModel = KeycapChainModel(steps: [["⌃", "Space"], ["1"]])
        XCTAssertEqual(chainedModel.segments.count, 3)
        XCTAssertEqual(chainedModel.segments, [
            .keyGroup(["⌃", "Space"]),
            .arrow,
            .keyGroup(["1"])
        ])
        XCTAssertTrue(chainedModel.hasArrowSeparators)
        XCTAssertEqual(chainedModel.accessibleText, "Control Space then 1")
    }

    func testKeycapChipDimensionsMatchSpec() {
        XCTAssertGreaterThanOrEqual(KeycapLayout.minWidth, 20.0, "Keycap min width must be at least 20 pt")
        XCTAssertEqual(KeycapLayout.height, 22.0, "Keycap height must be 22 pt")
        XCTAssertEqual(KeycapLayout.radius, 6.0, "Keycap radius must be r6")
        XCTAssertEqual(KeycapLayout.horizontalPadding, 6.0)
    }

    // MARK: - 3. Badge and Status Models Tests

    func testCapsuleBadgePresetsAndTypographySpec() {
        let beta = CapsuleBadgeModel.beta
        XCTAssertEqual(beta.text, "BETA")
        XCTAssertEqual(beta.fontSize, 8.5)
        XCTAssertEqual(beta.isBold, true)

        let experimental = CapsuleBadgeModel.experimental
        XCTAssertEqual(experimental.text, "EXPERIMENTAL")
        XCTAssertEqual(experimental.fontSize, 8.5)
        XCTAssertEqual(experimental.isBold, true)

        let custom = CapsuleBadgeModel(text: "Included", tint: .systemGreen)
        XCTAssertEqual(custom.text, "INCLUDED")
        XCTAssertEqual(custom.tint, .systemGreen)
    }

    func testStatusDotModelAndDiameterSpec() {
        XCTAssertGreaterThanOrEqual(StatusDotLayout.diameter, 5.0, "Status dot diameter lower bound is 5 pt")
        XCTAssertLessThanOrEqual(StatusDotLayout.diameter, 6.0, "Status dot diameter upper bound is 6 pt")

        let activeDot = StatusDotModel(state: .active)
        XCTAssertEqual(activeDot.color, NSColor.systemGreen)
        XCTAssertEqual(activeDot.accessibilityLabel, "Active")

        let inactiveDot = StatusDotModel(state: .inactive)
        XCTAssertEqual(inactiveDot.color, NSColor.tertiaryLabelColor)
        XCTAssertEqual(inactiveDot.accessibilityLabel, "Inactive")

        let warningDot = StatusDotModel(state: .warning)
        XCTAssertEqual(warningDot.color, NSColor.systemOrange)
        XCTAssertEqual(warningDot.accessibilityLabel, "Warning")

        let errorDot = StatusDotModel(state: .error)
        XCTAssertEqual(errorDot.color, NSColor.systemRed)
        XCTAssertEqual(errorDot.accessibilityLabel, "Error")
    }

    // MARK: - 4. Card, Row, and IconTile Layout Spec Tests

    func testSettingsCardLayoutSpec() {
        XCTAssertEqual(SettingsCardLayout.padding, 16.0, "Card padding must be 16 pt")
        XCTAssertEqual(SettingsCardLayout.cornerRadius, 16.0, "Card continuous radius must be 16 pt")
        XCTAssertEqual(SettingsCardLayout.stackGap, 20.0, "Card stack gap must be 20 pt")
        XCTAssertEqual(SettingsCardLayout.maxContentWidth, 760.0, "Max content column must be 760 pt")
        XCTAssertEqual(SettingsCardLayout.fillOpacity, 0.35, accuracy: 0.01, "Quaternary fill ~35%")
    }

    func testSettingsRowAndIconTileLayoutSpec() {
        XCTAssertEqual(IconTileLayout.size, 26.0, "Icon tile size must be 26x26 pt")
        XCTAssertEqual(IconTileLayout.cornerRadius, 7.0, "Icon tile radius must be r7")
        XCTAssertEqual(IconTileLayout.fillOpacity, 0.12, accuracy: 0.01, "Icon tile fill must be 12%")
        XCTAssertEqual(IconTileLayout.symbolPointSize, 12.0, "Icon tile symbol must be 12 pt semibold")

        XCTAssertEqual(SettingsRowLayout.subcontentInset, 38.0, "Row sub-content inset must be 38 pt")
        XCTAssertEqual(SettingsRowLayout.dividerHeight, 0.5, "Row thin divider must be 0.5 pt")
        XCTAssertEqual(SettingsRowLayout.titleFontSize, 13.0, "Row title must be 13 pt")
        XCTAssertEqual(SettingsRowLayout.captionFontSize, 11.0, "Row caption must be 11 pt")
        XCTAssertTrue(SettingsRowLayout.captionsWrapNeverTruncate, "Captions must wrap and never truncate")
    }
}
