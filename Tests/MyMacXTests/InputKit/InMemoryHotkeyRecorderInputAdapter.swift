import Foundation
@testable import MyMacX

@MainActor
final class InMemoryHotkeyRecorderInputAdapter: HotkeyRecorderInputMonitoring {
    private var sessionID: UUID?
    private var handler: (@Sendable (HotkeyRecorderInputEvent) -> Void)?

    func startCapturing(
        sessionID: UUID,
        handler: @escaping @Sendable (HotkeyRecorderInputEvent) -> Void
    ) {
        self.sessionID = sessionID
        self.handler = handler
    }

    func stopCapturing(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.sessionID = nil
        handler = nil
    }

    func send(_ event: HotkeyRecorderInputEvent) {
        handler?(event)
    }
}
