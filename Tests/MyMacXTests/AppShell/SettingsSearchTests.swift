import AppKit
import SwiftUI
import XCTest
@testable import MyMacX

@MainActor
final class SettingsSearchTests: XCTestCase {
    func testEmptySearchQueryReturnsNoResults() {
        let index = SettingsSearchIndex()
        XCTAssertTrue(index.search(query: "").isEmpty)
        XCTAssertTrue(index.search(query: "   ").isEmpty)
    }

    func testSearchMatchesSectionTitlesAndRowLabelsAndCaptions() {
        let index = SettingsSearchIndex()

        let snappingResults = index.search(query: "snapping")
        XCTAssertFalse(snappingResults.isEmpty)
        XCTAssertTrue(snappingResults.contains { $0.section == .snapping })

        let dwellResults = index.search(query: "delay")
        XCTAssertFalse(dwellResults.isEmpty)
        XCTAssertTrue(dwellResults.contains { group in
            group.items.contains { $0.anchor == .snappingTrigger }
        })

        let loginResults = index.search(query: "login")
        XCTAssertFalse(loginResults.isEmpty)
        XCTAssertTrue(loginResults.contains { group in
            group.items.contains { $0.anchor == .generalStartup }
        })
    }

    func testSearchResultsGroupedBySettingsSectionInCanonicalOrder() {
        let index = SettingsSearchIndex()
        let results = index.search(query: "window")

        // Check canonical order of sections
        let sections = results.map(\.section)
        let canonicalAll = SettingsSection.allCases
        var lastIndex = -1
        for section in sections {
            let currentIndex = canonicalAll.firstIndex(of: section)!
            XCTAssertGreaterThan(currentIndex, lastIndex)
            lastIndex = currentIndex
        }
    }

    func testSearchKeywordsSupportAlternateTerms() {
        let index = SettingsSearchIndex()

        let shortcutResults = index.search(query: "shortcut")
        XCTAssertTrue(shortcutResults.contains { $0.section == .hotkeys })

        let dwellResults = index.search(query: "dwell")
        XCTAssertTrue(dwellResults.contains { group in
            group.items.contains { $0.anchor == .snappingTrigger }
        })
    }

    func testHighlightCoordinatorLandsOnAnchorAndSetsHighlighted() async {
        let coordinator = SettingsHighlightCoordinator(fadeDuration: 0.05)
        XCTAssertNil(coordinator.activeAnchor)
        XCTAssertFalse(coordinator.isHighlighted)

        coordinator.land(on: .snappingTrigger, reduceMotion: false)
        XCTAssertEqual(coordinator.activeAnchor, .snappingTrigger)
        XCTAssertTrue(coordinator.isHighlighted)

        // Wait for highlight duration to finish
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(coordinator.isHighlighted)
    }

    func testHighlightCoordinatorClearsOnReset() {
        let coordinator = SettingsHighlightCoordinator(fadeDuration: 1.8)
        coordinator.land(on: .generalPermissions)
        XCTAssertEqual(coordinator.activeAnchor, .generalPermissions)
        XCTAssertTrue(coordinator.isHighlighted)

        coordinator.clear()
        XCTAssertNil(coordinator.activeAnchor)
        XCTAssertFalse(coordinator.isHighlighted)
    }

    func testHighlightCoordinatorRespectsReducedMotion() async {
        let coordinator = SettingsHighlightCoordinator(fadeDuration: 1.8)
        coordinator.land(on: .hotkeysSuperMode, reduceMotion: true)
        // With reduced motion, highlight completes immediately or transitions to false
        XCTAssertFalse(coordinator.isHighlighted)
        XCTAssertEqual(coordinator.activeAnchor, .hotkeysSuperMode)
    }

    func testChordBridgeConvertsHotkeyChordToKeyChord() {
        let presenter = FixtureChordPresenter(labels: [4: "H"])
        let hotkeyChord = HotkeyChord(hardwareKeyCode: 4, modifiers: [.command, .shift])
        let keyChord = KeyChord(hotkeyChord: hotkeyChord, presenter: presenter)

        XCTAssertEqual(keyChord.key, "H")
        XCTAssertTrue(keyChord.modifiers.contains(.command))
        XCTAssertTrue(keyChord.modifiers.contains(.shift))
        XCTAssertFalse(keyChord.modifiers.contains(.control))
        XCTAssertFalse(keyChord.modifiers.contains(.option))

        let recoveredModifiers = hotkeyChord.modifiers
        XCTAssertEqual(keyChord.hotkeyModifiers, recoveredModifiers)
    }
}

private struct FixtureChordPresenter: HotkeyChordPresenting {
    let labels: [UInt16: String]

    func present(_ chord: HotkeyChord) -> HotkeyChordPresentation {
        let symbols: [(HotkeyModifiers, HotkeyModifierSymbol, String, String)] = [
            (.control, .control, "⌃", "Control"),
            (.option, .option, "⌥", "Option"),
            (.shift, .shift, "⇧", "Shift"),
            (.command, .command, "⌘", "Command"),
        ]
        let active = symbols.filter { chord.modifiers.contains($0.0) }
        let key = labels[chord.hardwareKeyCode] ?? "Key \(chord.hardwareKeyCode)"
        return HotkeyChordPresentation(
            modifierSymbols: active.map(\.1),
            keyLabel: key,
            accessibilityLabel: (active.map(\.3) + [key]).joined(separator: " "),
            usedHardwareCodeFallback: labels[chord.hardwareKeyCode] == nil
        )
    }
}
