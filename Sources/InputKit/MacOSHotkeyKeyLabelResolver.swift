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
import Carbon.HIToolbox
import Foundation

struct MacOSHotkeyLayoutSnapshot: Sendable {
    let identifier: String
    let data: Data
}

protocol MacOSHotkeyLayoutProviding: Sendable {
    func currentKeyboardLayout() -> MacOSHotkeyLayoutSnapshot?
}

protocol MacOSHotkeyLayoutTranslating: Sendable {
    func label(for hardwareKeyCode: UInt16, in snapshot: MacOSHotkeyLayoutSnapshot) -> String?
}

/// Resolves presentation-only key labels against the currently selected macOS layout.
/// The physical key code remains the hotkey's identity and is never replaced by text.
final class MacOSHotkeyKeyLabelResolver: HotkeyKeyLabelResolving, @unchecked Sendable {
    private let sourceProvider: any MacOSHotkeyLayoutProviding
    private let translator: any MacOSHotkeyLayoutTranslating
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var generation = 0
    private struct CacheKey: Hashable {
        let generation: Int
        let hardwareKeyCode: UInt16
    }
    private enum CachedLabel {
        case resolved(String)
        case unavailable
    }
    private var cache: [CacheKey: CachedLabel] = [:]
    private var observer: NSObjectProtocol?

    init(
        sourceProvider: any MacOSHotkeyLayoutProviding = SystemMacOSHotkeyLayoutProvider(),
        translator: any MacOSHotkeyLayoutTranslating = CarbonMacOSHotkeyLayoutTranslator(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.sourceProvider = sourceProvider
        self.translator = translator
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidateForKeyboardSelectionChange()
        }
    }

    deinit {
        if let observer { notificationCenter.removeObserver(observer) }
    }

    func invalidateForKeyboardSelectionChange() {
        lock.lock()
        generation &+= 1
        cache.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func label(for hardwareKeyCode: UInt16) -> String? {
        if let label = Self.stableMacKeyLabel(for: hardwareKeyCode) {
            return label
        }

        lock.lock()
        let key = CacheKey(generation: generation, hardwareKeyCode: hardwareKeyCode)
        if let cached = cache[key] {
            lock.unlock()
            if case let .resolved(label) = cached { return label }
            return nil
        }
        lock.unlock()

        let snapshot = sourceProvider.currentKeyboardLayout()
        let result = snapshot
            .flatMap { translator.label(for: hardwareKeyCode, in: $0) }
            .flatMap(Self.normalize)

        lock.lock()
        cache[key] = result.map(CachedLabel.resolved) ?? .unavailable
        lock.unlock()
        return result
    }

    private static func stableMacKeyLabel(for hardwareKeyCode: UInt16) -> String? {
        switch hardwareKeyCode {
        case 0x24: return "Return"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x33: return "Delete"
        case 0x35: return "Escape"
        case 0x40: return "F17"
        case 0x41: return "Keypad Decimal"
        case 0x43: return "Keypad Multiply"
        case 0x45: return "Keypad Plus"
        case 0x47: return "Keypad Clear"
        case 0x4B: return "Keypad Divide"
        case 0x4C: return "Keypad Enter"
        case 0x4E: return "Keypad Minus"
        case 0x4F: return "F18"
        case 0x50: return "F19"
        case 0x51: return "Keypad Equals"
        case 0x52: return "Keypad 0"
        case 0x53: return "Keypad 1"
        case 0x54: return "Keypad 2"
        case 0x55: return "Keypad 3"
        case 0x56: return "Keypad 4"
        case 0x57: return "Keypad 5"
        case 0x58: return "Keypad 6"
        case 0x59: return "Keypad 7"
        case 0x5A: return "F20"
        case 0x5B: return "Keypad 8"
        case 0x5C: return "Keypad 9"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x63: return "F3"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x67: return "F11"
        case 0x69: return "F13"
        case 0x6A: return "F16"
        case 0x6B: return "F14"
        case 0x6D: return "F10"
        case 0x6F: return "F12"
        case 0x71: return "F15"
        case 0x72: return "Help"
        case 0x73: return "Home"
        case 0x74: return "Page Up"
        case 0x75: return "Forward Delete"
        case 0x76: return "F4"
        case 0x77: return "End"
        case 0x78: return "F2"
        case 0x79: return "Page Down"
        case 0x7A: return "F1"
        case 0x7B: return "Left Arrow"
        case 0x7C: return "Right Arrow"
        case 0x7D: return "Down Arrow"
        case 0x7E: return "Up Arrow"
        default: return nil
        }
    }

    private static func normalize(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Layout translation may yield one keycap character or an explicit stable
        // name such as "Left Arrow". A contiguous multi-character result is
        // composed/ambiguous output and must fall back to the physical code.
        if trimmed.count > 1 && !trimmed.contains(where: { $0.isWhitespace }) {
            return nil
        }
        return trimmed.count == 1 ? trimmed.uppercased() : trimmed
    }
}

private struct SystemMacOSHotkeyLayoutProvider: MacOSHotkeyLayoutProviding {
    func currentKeyboardLayout() -> MacOSHotkeyLayoutSnapshot? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let identifierValue = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              let layoutValue = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let identifier = Unmanaged<CFString>.fromOpaque(identifierValue).takeUnretainedValue() as String
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutValue).takeUnretainedValue() as Data
        guard !layoutData.isEmpty else { return nil }
        return MacOSHotkeyLayoutSnapshot(identifier: identifier, data: layoutData)
    }
}

private struct CarbonMacOSHotkeyLayoutTranslator: MacOSHotkeyLayoutTranslating {
    func label(for hardwareKeyCode: UInt16, in snapshot: MacOSHotkeyLayoutSnapshot) -> String? {
        guard let pointer = snapshot.data.withUnsafeBytes({ rawBuffer -> UnsafePointer<UCKeyboardLayout>? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            return baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
        }) else { return nil }

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        let status = UCKeyTranslate(
            pointer,
            UInt16(hardwareKeyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, deadKeyState == 0, length == 1,
              let scalar = UnicodeScalar(characters[0]),
              scalar.value >= 0x20, scalar.value != 0x7F else { return nil }
        let character = String(scalar)
        return character.count == 1 ? character.uppercased() : nil
    }
}
