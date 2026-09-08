import AppKit
import Foundation
import XCTest
@testable import MyMacX

final class HotkeyKeyLabelResolverTests: XCTestCase {
    func testStableMacKeysResolveWithoutDependingOnTheCurrentKeyboardLayout() {
        let source = FixtureSource(layout: .unavailable)
        let resolver = MacOSHotkeyKeyLabelResolver(
            sourceProvider: source,
            translator: FixtureTranslator()
        )

        let expected: [UInt16: String] = [
            0x24: "Return",
            0x30: "Tab",
            0x31: "Space",
            0x33: "Delete",
            0x35: "Escape",
            0x4C: "Keypad Enter",
            0x52: "Keypad 0",
            0x73: "Home",
            0x74: "Page Up",
            0x75: "Forward Delete",
            0x77: "End",
            0x79: "Page Down",
            0x7A: "F1",
            0x6F: "F12",
            0x7B: "Left Arrow",
            0x7E: "Up Arrow",
        ]

        for (keyCode, label) in expected {
            XCTAssertEqual(resolver.label(for: keyCode), label, "key code \(keyCode)")
        }
        XCTAssertEqual(source.lookupCount, 0)
    }

    func testABCMappingResolvesLettersAndArrow() {
        let source = FixtureSource(layout: .abc)
        let resolver = MacOSHotkeyKeyLabelResolver(sourceProvider: source, translator: FixtureTranslator())

        XCTAssertEqual(resolver.label(for: 0x00), "A")
        XCTAssertEqual(resolver.label(for: 0x06), "Z")
        XCTAssertEqual(resolver.label(for: 0x7B), "Left Arrow")
        XCTAssertEqual(source.lookupCount, 2)
    }

    func testRepeatedLookupUsesOneSourceSnapshotAndCachesFailure() {
        let source = FixtureSource(layout: .abc)
        let resolver = MacOSHotkeyKeyLabelResolver(sourceProvider: source, translator: FixtureTranslator())

        XCTAssertEqual(resolver.label(for: 0x00), "A")
        XCTAssertEqual(resolver.label(for: 0x00), "A")
        XCTAssertNil(resolver.label(for: 0x99))
        XCTAssertNil(resolver.label(for: 0x99))
        XCTAssertEqual(source.lookupCount, 2)
    }

    func testSelectionChangeInvalidationDoesNotServeStaleLabel() {
        let source = FixtureSource(layout: .abc)
        let notificationCenter = NotificationCenter()
        let resolver = MacOSHotkeyKeyLabelResolver(
            sourceProvider: source,
            translator: FixtureTranslator(),
            notificationCenter: notificationCenter
        )

        XCTAssertEqual(resolver.label(for: 0x00), "A")
        source.layout = .telex
        notificationCenter.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)

        XCTAssertNil(resolver.label(for: 0x00))
        let presentation = HotkeyChordPresenter(labelResolver: resolver).present(
            HotkeyChord(hardwareKeyCode: 0x00, modifiers: [.command])
        )
        XCTAssertEqual(presentation.keyLabel, "Key code 0x00")
        XCTAssertEqual(presentation.accessibilityLabel, "Command Key code 0x00")
        XCTAssertTrue(presentation.usedHardwareCodeFallback)
        XCTAssertEqual(source.lookupCount, 2)
    }

    func testInvalidationIsIdempotentAndLaterSourceCanRecover() {
        let source = FixtureSource(layout: .telex)
        let resolver = MacOSHotkeyKeyLabelResolver(sourceProvider: source, translator: FixtureTranslator())

        XCTAssertNil(resolver.label(for: 0x00))
        resolver.invalidateForKeyboardSelectionChange()
        resolver.invalidateForKeyboardSelectionChange()
        XCTAssertNil(resolver.label(for: 0x99))
        source.layout = .abc

        XCTAssertEqual(resolver.label(for: 0x00), "A")
        XCTAssertEqual(source.lookupCount, 3)
    }

    func testAmbiguousAndUnsupportedResultsUsePresenterHardwareFallback() {
        let source = FixtureSource(layout: .abc)
        let translator = FixtureTranslator(results: [
            0x01: .empty,
            0x02: .multiCharacter,
            0x03: .deadKey,
            0x04: .unsupported,
        ])
        let resolver = MacOSHotkeyKeyLabelResolver(sourceProvider: source, translator: translator)
        let presenter = HotkeyChordPresenter(labelResolver: resolver)

        for code in [UInt16(0x01), 0x02, 0x03, 0x04] {
            let presentation = presenter.present(HotkeyChord(hardwareKeyCode: code, modifiers: [.command]))
            XCTAssertEqual(presentation.keyLabel, String(format: "Key code 0x%02X", code))
            XCTAssertEqual(presentation.accessibilityLabel, "Command " + presentation.keyLabel)
            XCTAssertTrue(presentation.usedHardwareCodeFallback)
        }
    }

    func testChangingPresentationLabelDoesNotChangeChordIdentity() {
        let source = FixtureSource(layout: .abc)
        let abcResolver = MacOSHotkeyKeyLabelResolver(
            sourceProvider: source,
            translator: FixtureTranslator()
        )
        let alternateResolver = MacOSHotkeyKeyLabelResolver(
            sourceProvider: source,
            translator: FixtureTranslator(results: [0x00: .alternateLabel])
        )
        let chord = HotkeyChord(hardwareKeyCode: 0x00, modifiers: [.command, .shift])

        let abcPresentation = HotkeyChordPresenter(labelResolver: abcResolver).present(chord)
        let alternatePresentation = HotkeyChordPresenter(labelResolver: alternateResolver).present(chord)

        XCTAssertEqual(chord, HotkeyChord(hardwareKeyCode: 0x00, modifiers: [.command, .shift]))
        XCTAssertEqual(chord.hashValue, HotkeyChord(hardwareKeyCode: 0x00, modifiers: [.command, .shift]).hashValue)
        XCTAssertEqual(abcPresentation.keyLabel, "A")
        XCTAssertEqual(alternatePresentation.keyLabel, "Q")
        XCTAssertNotEqual(abcPresentation, alternatePresentation)
    }

    func testSourceProviderOutageFallsBackAndLaterSuccessfulLookupRecovers() {
        let source = FixtureSource(layout: .unavailable)
        let resolver = MacOSHotkeyKeyLabelResolver(sourceProvider: source, translator: FixtureTranslator())
        let presenter = HotkeyChordPresenter(labelResolver: resolver)
        let chord = HotkeyChord(hardwareKeyCode: 0x00, modifiers: [.command])

        XCTAssertEqual(presenter.present(chord).keyLabel, "Key code 0x00")
        source.layout = .abc
        resolver.invalidateForKeyboardSelectionChange()

        XCTAssertEqual(presenter.present(chord).keyLabel, "A")
        XCTAssertEqual(source.lookupCount, 2)
    }
}

private final class FixtureSource: MacOSHotkeyLayoutProviding, @unchecked Sendable {
    enum Layout { case abc, telex, unavailable }
    var layout: Layout
    private(set) var lookupCount = 0

    init(layout: Layout) { self.layout = layout }

    func currentKeyboardLayout() -> MacOSHotkeyLayoutSnapshot? {
        lookupCount += 1
        switch layout {
        case .abc: return MacOSHotkeyLayoutSnapshot(identifier: "fixture.abc", data: Data([0x01]))
        case .telex: return nil
        case .unavailable: return nil
        }
    }
}

private struct FixtureTranslator: MacOSHotkeyLayoutTranslating {
    enum Result { case empty, multiCharacter, deadKey, unsupported, alternateLabel }
    var results: [UInt16: Result] = [:]

    func label(for hardwareKeyCode: UInt16, in snapshot: MacOSHotkeyLayoutSnapshot) -> String? {
        if let result = results[hardwareKeyCode] {
            switch result {
            case .empty, .deadKey, .unsupported: return nil
            case .multiCharacter: return "AB"
            case .alternateLabel: return "q"
            }
        }
        switch hardwareKeyCode {
        case 0x00: return "a"
        case 0x06: return "z"
        case 0x7B: return "Left Arrow"
        default: return nil
        }
    }
}
