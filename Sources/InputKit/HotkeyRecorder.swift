import AppKit
import Foundation

enum HotkeyRecorderState: Equatable, Sendable {
    case idle
    case recording
    case captured(HotkeyChord)
    case cancelled
    case cleared
}

protocol HotkeyRecording: Actor {
    var updates: AsyncStream<HotkeyRecorderState> { get }

    func begin() async
    func cancel() async
    func clear() async
}

/// Normalized local input passed only across the recorder's internal input seam.
enum HotkeyRecorderInputEvent: Sendable {
    case keyDown(hardwareKeyCode: UInt16, modifiers: HotkeyModifiers)
    case modifierTransition
}

@MainActor
protocol HotkeyRecorderInputMonitoring: AnyObject, Sendable {
    func startCapturing(
        sessionID: UUID,
        handler: @escaping @Sendable (HotkeyRecorderInputEvent) -> Void
    )

    func stopCapturing(sessionID: UUID)
}

actor HotkeyRecorder: HotkeyRecording {
    let updates: AsyncStream<HotkeyRecorderState>

    private let input: any HotkeyRecorderInputMonitoring
    private let continuation: AsyncStream<HotkeyRecorderState>.Continuation
    private var state: HotkeyRecorderState = .idle
    private var sessionID: UUID?

    init(input: any HotkeyRecorderInputMonitoring) {
        let stream = AsyncStream.makeStream(
            of: HotkeyRecorderState.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        updates = stream.stream
        continuation = stream.continuation
        self.input = input
    }

    func begin() async {
        guard state != .recording else { return }

        let sessionID = UUID()
        self.sessionID = sessionID
        transition(to: .recording)
        await input.startCapturing(sessionID: sessionID) { [weak self] event in
            Task {
                await self?.receive(event, from: sessionID)
            }
        }

        if self.sessionID != sessionID {
            await input.stopCapturing(sessionID: sessionID)
        }
    }

    func cancel() async {
        guard let sessionID, state == .recording else { return }
        self.sessionID = nil
        transition(to: .cancelled)
        await input.stopCapturing(sessionID: sessionID)
    }

    func clear() async {
        guard state != .cleared else { return }

        let sessionID = sessionID
        self.sessionID = nil
        transition(to: .cleared)
        if let sessionID {
            await input.stopCapturing(sessionID: sessionID)
        }
    }

    private func receive(_ event: HotkeyRecorderInputEvent, from sessionID: UUID) async {
        guard self.sessionID == sessionID, state == .recording else { return }

        switch event {
        case .modifierTransition:
            return
        case let .keyDown(hardwareKeyCode, modifiers):
            if hardwareKeyCode == 53 {
                await cancel()
                return
            }

            self.sessionID = nil
            transition(
                to: .captured(
                    HotkeyChord(
                        hardwareKeyCode: hardwareKeyCode,
                        modifiers: modifiers
                    )
                )
            )
            await input.stopCapturing(sessionID: sessionID)
        }
    }

    private func transition(to newState: HotkeyRecorderState) {
        state = newState
        continuation.yield(newState)
    }
}

@MainActor
final class AppKitHotkeyRecorderInputAdapter: HotkeyRecorderInputMonitoring {
    private var monitor: Any?
    private var sessionID: UUID?
    private var handler: (@Sendable (HotkeyRecorderInputEvent) -> Void)?

    func startCapturing(
        sessionID: UUID,
        handler: @escaping @Sendable (HotkeyRecorderInputEvent) -> Void
    ) {
        removeActiveMonitor()

        self.sessionID = sessionID
        self.handler = handler
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }

            switch event.type {
            case .flagsChanged:
                self.handler?(.modifierTransition)
            case .keyDown:
                if Self.isModifierKey(event.keyCode) {
                    self.handler?(.modifierTransition)
                    return event
                } else {
                    self.handler?(
                        .keyDown(
                            hardwareKeyCode: event.keyCode,
                            modifiers: Self.normalizedModifiers(from: event.modifierFlags)
                        )
                    )
                    return nil
                }
            default:
                break
            }

            return event
        }
    }

    func stopCapturing(sessionID: UUID) {
        guard let activeSessionID = self.sessionID, activeSessionID == sessionID else { return }
        removeActiveMonitor()
    }

    private func removeActiveMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        self.sessionID = nil
        handler = nil
    }

    private static func normalizedModifiers(from flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        var modifiers: HotkeyModifiers = []
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }
}
