import AppKit
import Carbon.HIToolbox
import Foundation

private let macOSHotkeySignature: OSType = 0x4D_4D_58_31 // "MMX1"

@MainActor
final class MacOSGlobalHotkeySystem: GlobalHotkeySystem {
    private struct Chord: Hashable {
        let hardwareKeyCode: UInt16
        let modifiers: HotkeyModifiers
    }

    private struct Registration {
        let reference: EventHotKeyRef
        let numericID: UInt32
        let binding: HotkeyBinding
    }

    private final class CleanupState: @unchecked Sendable {
        var registrations: [Chord: Registration] = [:]
        var eventHandlerReference: EventHandlerRef?
        var workspaceObservationTokens: [NSObjectProtocol] = []

        func unregisterAll() {
            for registration in registrations.values {
                UnregisterEventHotKey(registration.reference)
            }
            registrations.removeAll()
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
                self.eventHandlerReference = nil
            }
            let center = NSWorkspace.shared.notificationCenter
            for token in workspaceObservationTokens {
                center.removeObserver(token)
            }
            workspaceObservationTokens.removeAll()
        }
    }

    private let cleanupState = CleanupState()

    private var registrations: [Chord: Registration] {
        get { cleanupState.registrations }
        set { cleanupState.registrations = newValue }
    }
    private var bindingsByNumericID: [UInt32: HotkeyBinding] = [:]
    private var nextNumericID: UInt32 = 1
    private var eventHandlerReference: EventHandlerRef? {
        get { cleanupState.eventHandlerReference }
        set { cleanupState.eventHandlerReference = newValue }
    }
    private var workspaceObservationTokens: [NSObjectProtocol] {
        get { cleanupState.workspaceObservationTokens }
        set { cleanupState.workspaceObservationTokens = newValue }
    }

    func observeLifecycle(
        _ handler: @escaping @Sendable (GlobalHotkeyLifecycleEvent) async -> Void
    ) async {
        guard workspaceObservationTokens.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservationTokens = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { await handler(.willSleep) }
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { await handler(.didWake) }
            },
        ]
    }

    func reconcile(
        _ bindings: [HotkeyBinding],
        onInvocation: @escaping @Sendable (HotkeyInvocation) -> Void
    ) async -> HotkeySystemReconciliation {
        let desired = desiredBindingsByChord(bindings)
        if let duplicate = desired.duplicate {
            return .degraded(
                activeBindingIDs: activeBindingIDs,
                failures: [.chordUnavailable(bindingID: duplicate.id)]
            )
        }

        if !bindings.isEmpty, let failure = installEventHandlerIfNeeded() {
            return .degraded(
                activeBindingIDs: activeBindingIDs,
                failures: [failure]
            )
        }

        var staged: [Chord: Registration] = [:]
        var retained: [Chord: Registration] = [:]

        for (chord, binding) in desired.bindings {
            if let existing = registrations[chord] {
                retained[chord] = Registration(
                    reference: existing.reference,
                    numericID: existing.numericID,
                    binding: binding
                )
                continue
            }

            switch register(binding, chord: chord) {
            case let .success(registration):
                staged[chord] = registration
            case let .failure(failure):
                return rollBack(staged, after: failure)
            }
        }

        var next = retained.merging(staged) { _, staged in staged }
        var failures: [HotkeyRegistrationFailure] = []
        for (chord, registration) in registrations where desired.bindings[chord] == nil {
            let status = UnregisterEventHotKey(registration.reference)
            if status != noErr {
                next[chord] = registration
                failures.append(
                    .releaseFailed(bindingID: registration.binding.id, status: status)
                )
            }
        }

        registrations = next
        bindingsByNumericID = Dictionary(
            uniqueKeysWithValues: next.values.map { ($0.numericID, $0.binding) }
        )
        invocationHandler = onInvocation

        if registrations.isEmpty, let status = removeEventHandlerIfInstalled() {
            failures.append(.eventHandlerFailed(status: status))
        }

        if failures.isEmpty {
            return .active(bindingIDs: bindings.map(\.id))
        }
        return .degraded(activeBindingIDs: activeBindingIDs, failures: failures)
    }

    deinit {
        cleanupState.unregisterAll()
    }

    private var activeBindingIDs: [UUID] {
        Set(registrations.values.map(\.binding.id))
            .sorted { $0.uuidString < $1.uuidString }
    }

    private func desiredBindingsByChord(
        _ bindings: [HotkeyBinding]
    ) -> (bindings: [Chord: HotkeyBinding], duplicate: HotkeyBinding?) {
        var result: [Chord: HotkeyBinding] = [:]
        for binding in bindings {
            let chord = Chord(
                hardwareKeyCode: binding.hardwareKeyCode,
                modifiers: binding.modifiers
            )
            if result[chord] != nil {
                return (result, binding)
            }
            result[chord] = binding
        }
        return (result, nil)
    }

    private func installEventHandlerIfNeeded() -> HotkeyRegistrationFailure? {
        guard eventHandlerReference == nil else { return nil }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            macOSGlobalHotkeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &reference
        )
        guard status == noErr, let reference else {
            return .eventHandlerFailed(status: status)
        }
        eventHandlerReference = reference
        return nil
    }

    private func register(
        _ binding: HotkeyBinding,
        chord: Chord
    ) -> Result<Registration, HotkeyRegistrationFailure> {
        let numericID = allocateNumericID()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(chord.hardwareKeyCode),
            carbonModifiers(for: chord.modifiers),
            EventHotKeyID(signature: macOSHotkeySignature, id: numericID),
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            if status == eventHotKeyExistsErr {
                return .failure(.chordUnavailable(bindingID: binding.id))
            }
            return .failure(
                .registrationRejected(bindingID: binding.id, status: status)
            )
        }
        return .success(
            Registration(reference: reference, numericID: numericID, binding: binding)
        )
    }

    private func rollBack(
        _ staged: [Chord: Registration],
        after failure: HotkeyRegistrationFailure
    ) -> HotkeySystemReconciliation {
        var failures = [failure]
        for (chord, registration) in staged {
            let status = UnregisterEventHotKey(registration.reference)
            if status != noErr {
                registrations[chord] = registration
                failures.append(
                    .releaseFailed(bindingID: registration.binding.id, status: status)
                )
            }
        }
        bindingsByNumericID = Dictionary(
            uniqueKeysWithValues: registrations.values.map { ($0.numericID, $0.binding) }
        )
        return .degraded(activeBindingIDs: activeBindingIDs, failures: failures)
    }

    private func removeEventHandlerIfInstalled() -> OSStatus? {
        guard let eventHandlerReference else { return nil }
        let status = RemoveEventHandler(eventHandlerReference)
        if status == noErr {
            self.eventHandlerReference = nil
        }
        return status == noErr ? nil : status
    }

    private func allocateNumericID() -> UInt32 {
        while bindingsByNumericID[nextNumericID] != nil {
            nextNumericID &+= 1
            if nextNumericID == 0 {
                nextNumericID = 1
            }
        }
        let value = nextNumericID
        nextNumericID &+= 1
        if nextNumericID == 0 {
            nextNumericID = 1
        }
        return value
    }

    private func carbonModifiers(for modifiers: HotkeyModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    fileprivate func publishInvocation(numericID: UInt32) {
        guard let binding = bindingsByNumericID[numericID] else { return }
        invocationHandler?(
            HotkeyInvocation(bindingID: binding.id, actionID: binding.actionID)
        )
    }

    private var invocationHandler: (@Sendable (HotkeyInvocation) -> Void)?
}

private let macOSGlobalHotkeyEventHandler: EventHandlerUPP = {
    _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr,
          hotkeyID.signature == macOSHotkeySignature
    else {
        return OSStatus(eventNotHandledErr)
    }

    let owner = Unmanaged<MacOSGlobalHotkeySystem>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let numericID = hotkeyID.id
    Task { @MainActor [weak owner] in
        owner?.publishInvocation(numericID: numericID)
    }
    return OSStatus(noErr)
}
