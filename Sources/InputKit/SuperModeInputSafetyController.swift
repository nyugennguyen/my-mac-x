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

import Foundation

protocol SuperModeScheduledTimeout: Sendable {
    func cancel()
}

protocol SuperModeTimeoutScheduling: Sendable {
    func schedule(
        afterMilliseconds: UInt32,
        _ operation: @escaping @Sendable () -> Void
    ) -> any SuperModeScheduledTimeout
}

final class DispatchSuperModeTimeoutScheduler: SuperModeTimeoutScheduling, @unchecked Sendable {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    func schedule(
        afterMilliseconds: UInt32,
        _ operation: @escaping @Sendable () -> Void
    ) -> any SuperModeScheduledTimeout {
        let timeout = DispatchSuperModeScheduledTimeout()
        queue.asyncAfter(
            deadline: .now() + .milliseconds(Int(afterMilliseconds))
        ) {
            timeout.fire(operation)
        }
        return timeout
    }
}

private final class DispatchSuperModeScheduledTimeout: SuperModeScheduledTimeout, @unchecked Sendable {
    private let lock = NSLock()
    private var isPending = true

    func cancel() {
        lock.lock()
        isPending = false
        lock.unlock()
    }

    func fire(_ operation: @escaping @Sendable () -> Void) {
        lock.lock()
        guard isPending else {
            lock.unlock()
            return
        }
        isPending = false
        lock.unlock()
        operation()
    }
}

struct SuperModeInputSafetyTransition: Equatable, Sendable {
    let revision: SuperModeConfigurationRevision
    let transition: SuperModeTransition
}

/// Callback-safe owner of Super Mode input classification, reduction, and session timeouts.
/// It retains only validated configuration and current reducer state, never text or raw events.
final class SuperModeInputSafetyController: @unchecked Sendable {
    private static let escapeHardwareKeyCode: UInt16 = 53

    private struct State {
        var snapshot: SuperModeRuntimeSnapshot
        var reducer: SuperModeReducer
        var isEnabled = true
        var isStopped = false
        var scheduledTimeout: (any SuperModeScheduledTimeout)?
    }

    private let lock = NSLock()
    private let scheduler: any SuperModeTimeoutScheduling
    private let onTransition: @Sendable (SuperModeInputSafetyTransition) -> Void
    private let transitionQueue = DispatchQueue(
        label: "MyMacX.SuperModeInputSafety.Transitions"
    )
    private var state: State

    init(
        snapshot: SuperModeRuntimeSnapshot,
        scheduler: any SuperModeTimeoutScheduling = DispatchSuperModeTimeoutScheduler(),
        onTransition: @escaping @Sendable (SuperModeInputSafetyTransition) -> Void
    ) {
        self.scheduler = scheduler
        self.onTransition = onTransition
        state = State(
            snapshot: snapshot,
            reducer: SuperModeReducer(commandTree: snapshot.commandTree)
        )
    }

    func handle(_ signal: EventTapSignal) -> EventTapEventDisposition {
        let disposition: EventTapEventDisposition

        lock.lock()
        guard state.isEnabled, !state.isStopped else {
            lock.unlock()
            return .passThrough
        }

        let transition: SuperModeTransition
        switch signal {
        case .disabledByTimeout, .disabledByUserInput:
            transition = state.reducer.reduce(.tapDisabled)
        case let .key(keySignal):
            guard keySignal.kind == .keyDown, !keySignal.isRepeat else {
                lock.unlock()
                return .passThrough
            }
            let input = input(for: keySignal, state: state)
            transition = state.reducer.reduce(input)
        }

        disposition = EventTapEventDisposition(transition.disposition)
        updateTimeout(after: transition)
        enqueue(wrapper(for: transition))
        lock.unlock()
        return disposition
    }

    func update(snapshot: SuperModeRuntimeSnapshot) {
        lock.lock()
        guard !state.isStopped else {
            lock.unlock()
            return
        }

        let transition = state.reducer.reduce(.stop)
        state.scheduledTimeout?.cancel()
        state.scheduledTimeout = nil
        enqueue(wrapper(for: transition))
        state.snapshot = snapshot
        state.reducer = SuperModeReducer(commandTree: snapshot.commandTree)
        lock.unlock()
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        guard !state.isStopped, state.isEnabled != enabled else {
            lock.unlock()
            return
        }

        if enabled {
            state.isEnabled = true
        } else {
            let transition = state.reducer.reduce(.tapDisabled)
            state.isEnabled = false
            state.scheduledTimeout?.cancel()
            state.scheduledTimeout = nil
            enqueue(wrapper(for: transition))
        }
        lock.unlock()
    }

    func stop() {
        lock.lock()
        guard !state.isStopped else {
            lock.unlock()
            return
        }

        let transition = state.reducer.reduce(.stop)
        state.isStopped = true
        state.isEnabled = false
        state.scheduledTimeout?.cancel()
        state.scheduledTimeout = nil
        enqueue(wrapper(for: transition))
        lock.unlock()
    }

    private func input(
        for signal: EventTapKeySignal,
        state: State
    ) -> SuperModeInput {
        let prefix = state.snapshot.configuration.prefix
        if signal.hardwareKeyCode == prefix.hardwareKeyCode,
           Self.normalizedModifiers(from: signal.modifierFlags) == prefix.modifiers {
            return .prefix
        }
        if signal.hardwareKeyCode == Self.escapeHardwareKeyCode,
           state.reducer.presentation != .idle {
            return .escape
        }
        return .keyDown(hardwareKeyCode: signal.hardwareKeyCode)
    }

    private func updateTimeout(after transition: SuperModeTransition) {
        switch transition.outcome {
        case .armed, .submenuEntered:
            guard let session = transition.current.session else {
                preconditionFailure("Active Super Mode transition must carry a session")
            }
            state.scheduledTimeout?.cancel()
            let revision = state.snapshot.revision
            let milliseconds = state.snapshot.configuration.timeoutMilliseconds
            state.scheduledTimeout = scheduler.schedule(
                afterMilliseconds: milliseconds
            ) { [weak self] in
                self?.timeout(session: session, revision: revision)
            }
        case .execute, .cancelled:
            state.scheduledTimeout?.cancel()
            state.scheduledTimeout = nil
        case .none:
            break
        }
    }

    private func timeout(
        session: SuperModeSessionID,
        revision: SuperModeConfigurationRevision
    ) {
        lock.lock()
        guard state.isEnabled,
              !state.isStopped,
              state.snapshot.revision == revision,
              state.reducer.presentation.session == session
        else {
            lock.unlock()
            return
        }

        let transition = state.reducer.reduce(.timeout(session: session))
        state.scheduledTimeout = nil
        enqueue(wrapper(for: transition))
        lock.unlock()
    }

    private func wrapper(
        for transition: SuperModeTransition
    ) -> SuperModeInputSafetyTransition? {
        guard transition.outcome != .none else { return nil }
        return SuperModeInputSafetyTransition(
            revision: state.snapshot.revision,
            transition: transition
        )
    }

    private func enqueue(_ transition: SuperModeInputSafetyTransition?) {
        guard let transition else { return }
        transitionQueue.async { [onTransition] in
            onTransition(transition)
        }
    }

    private static func normalizedModifiers(from rawFlags: UInt64) -> HotkeyModifiers {
        // CGEventFlags values are stable ABI constants. Only the four configurable modifiers
        // participate; Caps Lock, numeric-pad, Help and Fn bits are intentionally ignored.
        let commandMask: UInt64 = 0x0010_0000
        let optionMask: UInt64 = 0x0008_0000
        let controlMask: UInt64 = 0x0004_0000
        let shiftMask: UInt64 = 0x0002_0000
        var result: HotkeyModifiers = []
        if rawFlags & commandMask != 0 { result.insert(.command) }
        if rawFlags & optionMask != 0 { result.insert(.option) }
        if rawFlags & controlMask != 0 { result.insert(.control) }
        if rawFlags & shiftMask != 0 { result.insert(.shift) }
        return result
    }
}

private extension SuperModePresentationState {
    var session: SuperModeSessionID? {
        switch self {
        case .idle:
            return nil
        case let .armed(session), let .submenu(session, _):
            return session
        }
    }
}

private extension EventTapEventDisposition {
    init(_ disposition: SuperModeEventDisposition) {
        switch disposition {
        case .consume:
            self = .consume
        case .passThrough:
            self = .passThrough
        }
    }
}
