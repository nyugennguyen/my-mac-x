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
        switch hardwareKeyCode {
        case 0x7B: return "Left Arrow"
        case 0x7C: return "Right Arrow"
        case 0x7D: return "Down Arrow"
        case 0x7E: return "Up Arrow"
        default: break
        }

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
