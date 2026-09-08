import Foundation

struct EventTapInstallation: Equatable, Hashable, Sendable {
    fileprivate let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

struct EventTapKeySignal: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    let kind: Kind
    let hardwareKeyCode: UInt16
    let modifierFlags: UInt64
    let isRepeat: Bool
}

enum EventTapSignal: Equatable, Sendable {
    case key(EventTapKeySignal)
    case disabledByTimeout
    case disabledByUserInput
}

enum EventTapEventDisposition: Equatable, Sendable {
    case consume
    case passThrough
}

enum EventTapStatus: Equatable, Sendable {
    case stopped
    case active
    case unavailable
}

protocol EventTapManaging: Actor {
    func start() async -> EventTapStatus
    func stop() async
    func status() -> EventTapStatus
}

protocol EventTapSystem: Sendable {
    func install(
        _ handler: @escaping @Sendable (EventTapSignal) -> EventTapEventDisposition
    ) async -> EventTapInstallation?

    func enable(_ installation: EventTapInstallation) async
    func invalidate(_ installation: EventTapInstallation) async
}

/// Owns Event Tap lifecycle state. Platform callbacks carry a generation so callbacks retained
/// by the system after stop/restart cannot affect the current tap.
actor EventTapManager: EventTapManaging {
    private enum Lifecycle {
        case stopped
        case starting(UInt64, Task<EventTapInstallation?, Never>)
        case active(UInt64, EventTapInstallation)
        case stopping(UInt64, Task<Void, Never>)
        case unavailable
    }

    private let system: any EventTapSystem
    private let handler: @Sendable (EventTapSignal) -> EventTapEventDisposition
    private let callbackGate = EventTapCallbackGate()
    private var lifecycle: Lifecycle = .stopped
    private var generation: UInt64 = 0

    init(
        system: any EventTapSystem,
        handler: @escaping @Sendable (EventTapSignal) -> EventTapEventDisposition
    ) {
        self.system = system
        self.handler = handler
    }

    func start() async -> EventTapStatus {
        switch lifecycle {
        case .active:
            return .active
        case .unavailable:
            return .unavailable
        case let .starting(generation, installationTask):
            return await finishStart(
                generation: generation,
                installationTask: installationTask
            )
        case let .stopping(stopGeneration, teardownTask):
            await teardownTask.value
            if case let .stopping(currentGeneration, _) = lifecycle,
               currentGeneration == stopGeneration {
                lifecycle = .stopped
            }
            return await start()
        case .stopped:
            break
        }

        generation &+= 1
        let startGeneration = generation
        let system = system
        let callbackGate = callbackGate
        let installationTask = Task { [weak self] in
            await system.install { [weak self, callbackGate] signal in
                let disposition = callbackGate.handle(
                    signal,
                    generation: startGeneration
                )
                if signal.isDisabledNotification {
                    Task {
                        await self?.receiveDisabledNotification(
                            generation: startGeneration
                        )
                    }
                }
                return disposition
            }
        }
        lifecycle = .starting(startGeneration, installationTask)
        return await finishStart(
            generation: startGeneration,
            installationTask: installationTask
        )
    }

    func stop() async {
        callbackGate.deactivate()
        generation &+= 1

        switch lifecycle {
        case .stopped:
            return
        case .unavailable:
            lifecycle = .stopped
        case let .active(_, installation):
            lifecycle = .stopped
            await system.invalidate(installation)
        case let .starting(_, installationTask):
            let stopGeneration = generation
            let system = system
            let teardownTask = Task {
                if let installation = await installationTask.value {
                    await system.invalidate(installation)
                }
            }
            lifecycle = .stopping(stopGeneration, teardownTask)
            await teardownTask.value
            if case let .stopping(currentGeneration, _) = lifecycle,
               currentGeneration == stopGeneration {
                lifecycle = .stopped
            }
        case let .stopping(_, teardownTask):
            await teardownTask.value
        }
    }

    func status() -> EventTapStatus {
        switch lifecycle {
        case .active:
            return .active
        case .unavailable:
            return .unavailable
        case .stopped, .starting, .stopping:
            return .stopped
        }
    }

    private func finishStart(
        generation startGeneration: UInt64,
        installationTask: Task<EventTapInstallation?, Never>
    ) async -> EventTapStatus {
        guard let installation = await installationTask.value else {
            if case let .starting(currentGeneration, _) = lifecycle,
               currentGeneration == startGeneration {
                lifecycle = .unavailable
                return .unavailable
            }
            return status()
        }

        guard case let .starting(currentGeneration, _) = lifecycle,
              currentGeneration == startGeneration
        else {
            // A concurrent stop owns teardown of a still-starting installation.
            return status()
        }

        lifecycle = .active(startGeneration, installation)
        callbackGate.activate(generation: startGeneration, handler: handler)
        await system.enable(installation)
        guard case let .active(currentGeneration, currentInstallation) = lifecycle,
              currentGeneration == startGeneration,
              currentInstallation == installation
        else {
            return status()
        }
        return .active
    }

    private func receiveDisabledNotification(generation callbackGeneration: UInt64) async {
        guard case let .active(activeGeneration, installation) = lifecycle,
              activeGeneration == callbackGeneration
        else { return }

        await system.enable(installation)
    }
}

private extension EventTapSignal {
    var isDisabledNotification: Bool {
        switch self {
        case .disabledByTimeout, .disabledByUserInput:
            return true
        case .key:
            return false
        }
    }
}

/// A callback-visible lifecycle gate. Deactivation is synchronous, so callbacks already retained by
/// CoreGraphics fail open before the tap is invalidated or a new generation is installed.
private final class EventTapCallbackGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeGeneration: UInt64?
    private var handler: (@Sendable (EventTapSignal) -> EventTapEventDisposition)?

    func activate(
        generation: UInt64,
        handler: @escaping @Sendable (EventTapSignal) -> EventTapEventDisposition
    ) {
        lock.lock()
        activeGeneration = generation
        self.handler = handler
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        activeGeneration = nil
        handler = nil
        lock.unlock()
    }

    func handle(
        _ signal: EventTapSignal,
        generation callbackGeneration: UInt64
    ) -> EventTapEventDisposition {
        lock.lock()
        guard activeGeneration == callbackGeneration, let handler else {
            lock.unlock()
            return .passThrough
        }
        let disposition = handler(signal)
        lock.unlock()
        return disposition
    }
}
