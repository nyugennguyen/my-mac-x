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

protocol HotkeyRuntimeBindingUpdating: Actor {
    func start() async -> HotkeyRuntimeStartResult
    func applyValidated(_ desired: HotkeySettings) async -> HotkeyRuntimeUpdateResult
}

enum HotkeyRuntimeStartResult: Equatable, Sendable {
    case active(settings: HotkeySettings, origin: SettingsLoadOrigin)
    case degraded(
        settings: HotkeySettings,
        origin: SettingsLoadOrigin,
        registration: HotkeyRegistrationSnapshot
    )
}

enum HotkeyRuntimeUpdateResult: Equatable, Sendable {
    case applied(HotkeyRegistrationSnapshot)
    case saveFailed(SettingsSaveFailure)
    case rolledBackAfterRegistrationFailure(registration: HotkeyRegistrationSnapshot)
    case recoveryRequired(HotkeyRuntimeRecovery)
}

enum HotkeyRuntimeRecovery: Equatable, Sendable {
    case runtimeRollbackFailed(
        attempted: HotkeyRegistrationSnapshot,
        rollback: HotkeyRegistrationSnapshot
    )
    case persistenceRollbackFailed(
        registration: HotkeyRegistrationSnapshot,
        save: SettingsSaveFailure
    )
}

actor HotkeyRuntimeBindingUpdater: HotkeyRuntimeBindingUpdating {
    private let store: any SettingsStoring
    private let manager: any GlobalHotkeyManaging
    private let operationGate = HotkeyRuntimeOperationGate()

    init(store: any SettingsStoring, manager: any GlobalHotkeyManaging) {
        self.store = store
        self.manager = manager
    }

    func start() async -> HotkeyRuntimeStartResult {
        await operationGate.enter()
        let result = await startLoadedSettings()
        await operationGate.leave()
        return result
    }

    func applyValidated(_ desired: HotkeySettings) async -> HotkeyRuntimeUpdateResult {
        await operationGate.enter()
        let result = await applyValidatedSettings(desired)
        await operationGate.leave()
        return result
    }

    private func startLoadedSettings() async -> HotkeyRuntimeStartResult {
        let loaded = await store.load()
        switch loaded {
        case let .loaded(settings, origin):
            let registration = await manager.reconcile(settings.bindings)
            if isExactActive(registration, for: settings) {
                return .active(settings: settings, origin: origin)
            }
            return .degraded(
                settings: settings,
                origin: origin,
                registration: registration
            )
        }
    }

    private func applyValidatedSettings(_ desired: HotkeySettings) async -> HotkeyRuntimeUpdateResult {
        let prior = await store.load()
        guard case let .loaded(previousSettings, origin) = prior,
              canSafelyReplace(origin) else {
            return .saveFailed(.recoveryRequired)
        }

        switch await store.save(desired) {
        case .saved:
            break
        case let .failed(failure):
            return .saveFailed(failure)
        }

        let registration = await manager.reconcile(desired.bindings)
        guard !isExactActive(registration, for: desired) else {
            return .applied(registration)
        }

        let rollback = await manager.reconcile(previousSettings.bindings)
        guard isExactActive(rollback, for: previousSettings) else {
            return .recoveryRequired(
                .runtimeRollbackFailed(attempted: registration, rollback: rollback)
            )
        }

        switch await store.save(previousSettings) {
        case .saved:
            return .rolledBackAfterRegistrationFailure(registration: registration)
        case let .failed(failure):
            return .recoveryRequired(
                .persistenceRollbackFailed(registration: registration, save: failure)
            )
        }
    }

    private func canSafelyReplace(_ origin: SettingsLoadOrigin) -> Bool {
        switch origin {
        case .defaults(.unsupportedFutureVersion), .defaults(.corruptDocumentCouldNotBeQuarantined):
            false
        case .persisted, .migrated, .defaults:
            true
        }
    }

    private func isExactActive(
        _ registration: HotkeyRegistrationSnapshot,
        for settings: HotkeySettings
    ) -> Bool {
        guard case let .active(bindingIDs) = registration else { return false }
        return bindingIDs == settings.bindings.map(\.id)
    }
}

private actor HotkeyRuntimeOperationGate {
    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard isOccupied else {
            isOccupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        guard !waiters.isEmpty else {
            isOccupied = false
            return
        }
        waiters.removeFirst().resume()
    }
}
