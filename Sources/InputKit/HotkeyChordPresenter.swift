import Foundation

struct HotkeyChordPresentation: Equatable, Sendable {
    let modifierSymbols: [HotkeyModifierSymbol]
    let keyLabel: String
    let accessibilityLabel: String
    let usedHardwareCodeFallback: Bool
}

enum HotkeyModifierSymbol: Equatable, Sendable {
    case control
    case option
    case shift
    case command
}

protocol HotkeyChordPresenting: Sendable {
    func present(_ chord: HotkeyChord) -> HotkeyChordPresentation
}

/// The H3-07 system input-source implementation and test mapping implementations vary here.
protocol HotkeyKeyLabelResolving: Sendable {
    func label(for hardwareKeyCode: UInt16) -> String?
}

struct HotkeyChordPresenter: HotkeyChordPresenting {
    private let labelResolver: any HotkeyKeyLabelResolving

    init(labelResolver: any HotkeyKeyLabelResolving) {
        self.labelResolver = labelResolver
    }

    func present(_ chord: HotkeyChord) -> HotkeyChordPresentation {
        let modifierSymbols = Self.modifierSymbols(for: chord.modifiers)
        let keyLabel = labelResolver.label(for: chord.hardwareKeyCode)
        let visibleKeyLabel = keyLabel ?? Self.hardwareCodeLabel(for: chord.hardwareKeyCode)
        let accessibilityParts = modifierSymbols.map(\.accessibilityName) + [visibleKeyLabel]

        return HotkeyChordPresentation(
            modifierSymbols: modifierSymbols,
            keyLabel: visibleKeyLabel,
            accessibilityLabel: accessibilityParts.joined(separator: " "),
            usedHardwareCodeFallback: keyLabel == nil
        )
    }

    private static func modifierSymbols(for modifiers: HotkeyModifiers) -> [HotkeyModifierSymbol] {
        var symbols: [HotkeyModifierSymbol] = []
        if modifiers.contains(.control) {
            symbols.append(.control)
        }
        if modifiers.contains(.option) {
            symbols.append(.option)
        }
        if modifiers.contains(.shift) {
            symbols.append(.shift)
        }
        if modifiers.contains(.command) {
            symbols.append(.command)
        }
        return symbols
    }

    private static func hardwareCodeLabel(for hardwareKeyCode: UInt16) -> String {
        String(format: "Key code 0x%02X", hardwareKeyCode)
    }
}

private extension HotkeyModifierSymbol {
    var accessibilityName: String {
        switch self {
        case .control:
            return "Control"
        case .option:
            return "Option"
        case .shift:
            return "Shift"
        case .command:
            return "Command"
        }
    }
}
