import Foundation
@testable import MyMacX

actor InMemoryEventTapSystem: EventTapSystem {
    private let allowsInstallation: Bool
    private var nextInstallationID: UInt64 = 1
    private var currentInstallation: EventTapInstallation?
    private var handlers: [
        EventTapInstallation: @Sendable (EventTapSignal) -> EventTapEventDisposition
    ] = [:]
    private var installIsPaused = false
    private var installWasRequested = false
    private var installContinuation: CheckedContinuation<Void, Never>?

    private(set) var installCount = 0
    private(set) var enabledInstallations: [EventTapInstallation] = []
    private(set) var invalidatedInstallations: [EventTapInstallation] = []

    init(allowsInstallation: Bool = true) {
        self.allowsInstallation = allowsInstallation
    }

    var enableCount: Int { enabledInstallations.count }
    var invalidateCount: Int { invalidatedInstallations.count }

    func install(
        _ handler: @escaping @Sendable (EventTapSignal) -> EventTapEventDisposition
    ) async -> EventTapInstallation? {
        installCount += 1
        installWasRequested = true
        if installIsPaused {
            await withCheckedContinuation { continuation in
                installContinuation = continuation
            }
        }
        guard allowsInstallation else { return nil }
        let installation = EventTapInstallation(rawValue: nextInstallationID)
        nextInstallationID += 1
        currentInstallation = installation
        handlers[installation] = handler
        return installation
    }

    func enable(_ installation: EventTapInstallation) {
        guard currentInstallation == installation else { return }
        enabledInstallations.append(installation)
    }

    func invalidate(_ installation: EventTapInstallation) {
        guard currentInstallation == installation else { return }
        invalidatedInstallations.append(installation)
        currentInstallation = nil
        // Keep the handler so tests can simulate a system-delivered stale callback.
    }

    func pauseNextInstall() {
        installIsPaused = true
    }

    func waitUntilInstallRequested() async {
        while !installWasRequested {
            await Task.yield()
        }
    }

    func waitUntilEnableCount(_ expectedCount: Int) async {
        while enableCount < expectedCount {
            await Task.yield()
        }
    }

    func waitUntilInvalidateCount(_ expectedCount: Int) async {
        while invalidateCount < expectedCount {
            await Task.yield()
        }
    }

    func resumeInstall() {
        installIsPaused = false
        installContinuation?.resume()
        installContinuation = nil
    }

    func emit(_ signal: EventTapSignal) -> EventTapEventDisposition {
        guard let currentInstallation else { return .passThrough }
        return handlers[currentInstallation]?(signal) ?? .passThrough
    }

    func emit(
        _ signal: EventTapSignal,
        from installation: EventTapInstallation
    ) -> EventTapEventDisposition {
        handlers[installation]?(signal) ?? .passThrough
    }
}
