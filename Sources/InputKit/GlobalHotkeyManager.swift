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

struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}

struct HotkeyChord: Codable, Equatable, Hashable, Sendable {
    let hardwareKeyCode: UInt16
    let modifiers: HotkeyModifiers
}

struct HotkeyBinding: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let hardwareKeyCode: UInt16
    let modifiers: HotkeyModifiers
    let actionID: ActionID
}

extension HotkeyBinding {
    var chord: HotkeyChord {
        HotkeyChord(hardwareKeyCode: hardwareKeyCode, modifiers: modifiers)
    }
}

struct HotkeyInvocation: Equatable, Sendable {
    let bindingID: UUID
    let actionID: ActionID
}

enum HotkeyRegistrationSnapshot: Equatable, Sendable {
    case active(bindingIDs: [UUID])
    case degraded(activeBindingIDs: [UUID], failures: [HotkeyRegistrationFailure])
}

enum HotkeyRegistrationFailure: Error, Equatable, Sendable {
    case chordUnavailable(bindingID: UUID)
    case registrationRejected(bindingID: UUID, status: Int32)
    case releaseFailed(bindingID: UUID, status: Int32)
    case eventHandlerFailed(status: Int32)
}

enum HotkeySystemReconciliation: Equatable, Sendable {
    case active(bindingIDs: [UUID])
    case degraded(activeBindingIDs: [UUID], failures: [HotkeyRegistrationFailure])
}

enum GlobalHotkeyLifecycleEvent: Sendable {
    case willSleep
    case didWake
}

protocol GlobalHotkeyManaging: Actor {
    var events: AsyncStream<HotkeyInvocation> { get }

    func reconcile(_ bindings: [HotkeyBinding]) async -> HotkeyRegistrationSnapshot
}

protocol GlobalHotkeySystem: Sendable {
    func observeLifecycle(
        _ handler: @escaping @Sendable (GlobalHotkeyLifecycleEvent) async -> Void
    ) async

    func reconcile(
        _ bindings: [HotkeyBinding],
        onInvocation: @escaping @Sendable (HotkeyInvocation) -> Void
    ) async -> HotkeySystemReconciliation
}

actor GlobalHotkeyManager: GlobalHotkeyManaging {
    let events: AsyncStream<HotkeyInvocation>

    private let system: any GlobalHotkeySystem
    private let continuation: AsyncStream<HotkeyInvocation>.Continuation
    private var currentBindings: [HotkeyBinding]?
    private var currentSnapshot: HotkeyRegistrationSnapshot?
    private var lifecycleObservationInstalled = false
    private var isSleeping = false

    init(system: any GlobalHotkeySystem) {
        let stream = AsyncStream.makeStream(
            of: HotkeyInvocation.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        events = stream.stream
        continuation = stream.continuation
        self.system = system
    }

    func reconcile(_ bindings: [HotkeyBinding]) async -> HotkeyRegistrationSnapshot {
        await installLifecycleObservationIfNeeded()

        if bindings == currentBindings, let currentSnapshot {
            return currentSnapshot
        }

        let continuation = continuation
        let result = await system.reconcile(bindings) { invocation in
            continuation.yield(invocation)
        }
        let snapshot: HotkeyRegistrationSnapshot
        switch result {
        case let .active(bindingIDs):
            snapshot = .active(bindingIDs: bindingIDs)
            currentBindings = bindings
            currentSnapshot = snapshot
        case let .degraded(activeBindingIDs, failures):
            snapshot = .degraded(activeBindingIDs: activeBindingIDs, failures: failures)
        }
        return snapshot
    }

    private func installLifecycleObservationIfNeeded() async {
        guard !lifecycleObservationInstalled else { return }
        lifecycleObservationInstalled = true
        await system.observeLifecycle { [weak self] event in
            await self?.handleLifecycle(event)
        }
    }

    private func handleLifecycle(_ event: GlobalHotkeyLifecycleEvent) async {
        switch event {
        case .willSleep:
            guard !isSleeping else { return }
            isSleeping = true
            guard currentBindings?.isEmpty == false else { return }
            _ = await reconcileSystem([])
        case .didWake:
            guard isSleeping else { return }
            isSleeping = false
            guard let currentBindings, !currentBindings.isEmpty else { return }
            let result = await reconcileSystem(currentBindings)
            currentSnapshot = snapshot(for: result)
        }
    }

    private func reconcileSystem(
        _ bindings: [HotkeyBinding]
    ) async -> HotkeySystemReconciliation {
        let continuation = continuation
        return await system.reconcile(bindings) { invocation in
            continuation.yield(invocation)
        }
    }

    private func snapshot(
        for result: HotkeySystemReconciliation
    ) -> HotkeyRegistrationSnapshot {
        switch result {
        case let .active(bindingIDs):
            return .active(bindingIDs: bindingIDs)
        case let .degraded(activeBindingIDs, failures):
            return .degraded(activeBindingIDs: activeBindingIDs, failures: failures)
        }
    }
}
