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

import XCTest
@testable import MyMacX

final class HotkeyRuntimeBindingUpdaterTests: XCTestCase {
    func testApplyValidatedSavesAndActivatesReplacementWithoutRestart() async {
        let prior = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let desired = settings(binding: binding(id: "22222222-2222-2222-2222-222222222222", keyCode: 2, action: .rightHalf))
        let store = RuntimeSettingsStore(initial: prior)
        let manager = RuntimeHotkeyManager()
        await manager.enqueue(.active(bindingIDs: desired.bindings.map(\.id)))
        let updater: any HotkeyRuntimeBindingUpdating = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let result = await updater.applyValidated(desired)
        let savedSettings = await store.currentSettings
        let activeBindingIDs = await manager.activeBindingIDs

        XCTAssertEqual(result, .applied(.active(bindingIDs: desired.bindings.map(\.id))))
        XCTAssertEqual(savedSettings, desired)
        XCTAssertEqual(activeBindingIDs, desired.bindings.map(\.id))
    }

    func testApplyValidatedReturnsSaveFailureWithoutChangingRuntime() async {
        let prior = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let desired = settings(binding: binding(id: "22222222-2222-2222-2222-222222222222", keyCode: 2, action: .rightHalf))
        let store = RuntimeSettingsStore(initial: prior)
        await store.enqueueSaveResult(.failed(.documentNotWritable))
        let manager = RuntimeHotkeyManager(active: prior.bindings)
        let updater = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let result = await updater.applyValidated(desired)
        let activeBindingIDs = await manager.activeBindingIDs

        XCTAssertEqual(result, .saveFailed(.documentNotWritable))
        XCTAssertEqual(activeBindingIDs, prior.bindings.map(\.id))
    }

    func testApplyValidatedCompensatesDurableAndRuntimeSnapshotsAfterRegistrationFailure() async {
        let prior = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let desired = settings(binding: binding(id: "22222222-2222-2222-2222-222222222222", keyCode: 2, action: .rightHalf))
        let rejected = HotkeyRegistrationSnapshot.degraded(
            activeBindingIDs: prior.bindings.map(\.id),
            failures: [.chordUnavailable(bindingID: desired.bindings[0].id)]
        )
        let store = RuntimeSettingsStore(initial: prior)
        let manager = RuntimeHotkeyManager(active: prior.bindings)
        await manager.enqueue(rejected)
        await manager.enqueue(.active(bindingIDs: prior.bindings.map(\.id)))
        let updater = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let result = await updater.applyValidated(desired)
        let savedSettings = await store.currentSettings
        let activeBindingIDs = await manager.activeBindingIDs

        XCTAssertEqual(result, .rolledBackAfterRegistrationFailure(registration: rejected))
        XCTAssertEqual(savedSettings, prior)
        XCTAssertEqual(activeBindingIDs, prior.bindings.map(\.id))
    }

    func testApplyValidatedRestoresExactPriorBindingsAfterMixedRegistrationFailure() async {
        let prior = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let desired = settings(binding: binding(id: "22222222-2222-2222-2222-222222222222", keyCode: 2, action: .rightHalf))
        let mixedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let mixed = HotkeyRegistrationSnapshot.degraded(
            activeBindingIDs: [mixedID],
            failures: [.releaseFailed(bindingID: prior.bindings[0].id, status: -1)]
        )
        let store = RuntimeSettingsStore(initial: prior)
        let manager = RuntimeHotkeyManager(active: prior.bindings)
        await manager.enqueue(mixed)
        await manager.enqueue(.active(bindingIDs: prior.bindings.map(\.id)))
        let updater = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let result = await updater.applyValidated(desired)
        let activeBindingIDs = await manager.activeBindingIDs

        XCTAssertEqual(result, .rolledBackAfterRegistrationFailure(registration: mixed))
        XCTAssertEqual(activeBindingIDs, prior.bindings.map(\.id))
    }

    func testApplyValidatedReportsRuntimeRecoveryWhenPriorBindingsCannotBeRestored() async {
        let prior = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let desired = settings(binding: binding(id: "22222222-2222-2222-2222-222222222222", keyCode: 2, action: .rightHalf))
        let rejected = HotkeyRegistrationSnapshot.degraded(activeBindingIDs: [], failures: [.chordUnavailable(bindingID: desired.bindings[0].id)])
        let rollback = HotkeyRegistrationSnapshot.degraded(activeBindingIDs: [], failures: [.chordUnavailable(bindingID: prior.bindings[0].id)])
        let store = RuntimeSettingsStore(initial: prior)
        let manager = RuntimeHotkeyManager(active: prior.bindings)
        await manager.enqueue(rejected)
        await manager.enqueue(rollback)
        let updater = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let result = await updater.applyValidated(desired)
        let savedSettings = await store.currentSettings

        XCTAssertEqual(result, .recoveryRequired(.runtimeRollbackFailed(attempted: rejected, rollback: rollback)))
        XCTAssertEqual(savedSettings, desired)
    }

    func testApplyValidatedReportsPersistenceRecoveryWhenRestoringPriorSettingsFails() async {
        let prior = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let desired = settings(binding: binding(id: "22222222-2222-2222-2222-222222222222", keyCode: 2, action: .rightHalf))
        let rejected = HotkeyRegistrationSnapshot.degraded(activeBindingIDs: [], failures: [.chordUnavailable(bindingID: desired.bindings[0].id)])
        let store = RuntimeSettingsStore(initial: prior)
        await store.enqueueSaveResult(.saved(schemaVersion: 1))
        await store.enqueueSaveResult(.failed(.atomicReplacementFailed))
        let manager = RuntimeHotkeyManager(active: prior.bindings)
        await manager.enqueue(rejected)
        await manager.enqueue(.active(bindingIDs: prior.bindings.map(\.id)))
        let updater = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let result = await updater.applyValidated(desired)
        let savedSettings = await store.currentSettings
        let activeBindingIDs = await manager.activeBindingIDs

        XCTAssertEqual(result, .recoveryRequired(.persistenceRollbackFailed(registration: rejected, save: .atomicReplacementFailed)))
        XCTAssertEqual(savedSettings, desired)
        XCTAssertEqual(activeBindingIDs, prior.bindings.map(\.id))
    }

    func testStartLoadsPersistedSettingsWithoutWritingOrDuplicatingRegistration() async {
        let persisted = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let store = RuntimeSettingsStore(initial: persisted)
        let manager = RuntimeHotkeyManager()
        let updater: any HotkeyRuntimeBindingUpdating = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let first = await updater.start()
        let second = await updater.start()
        let saves = await store.saveCallCount
        let registrations = await manager.registrationPassCount

        XCTAssertEqual(first, .active(settings: persisted, origin: .persisted(schemaVersion: 1)))
        XCTAssertEqual(second, .active(settings: persisted, origin: .persisted(schemaVersion: 1)))
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(registrations, 1)
    }

    func testStartUsesStoreDefaultSnapshotAsTheOnlyLaunchBindingSource() async {
        let defaults = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let store = RuntimeSettingsStore(initial: defaults, origin: .defaults(reason: .corruptDocumentQuarantined))
        let manager = RuntimeHotkeyManager()
        let updater = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let result = await updater.start()
        let activeBindingIDs = await manager.activeBindingIDs

        XCTAssertEqual(result, .active(settings: defaults, origin: .defaults(reason: .corruptDocumentQuarantined)))
        XCTAssertEqual(activeBindingIDs, defaults.bindings.map(\.id))
    }

    func testApplyValidatedSerializesRapidUpdatesAcrossTheWholeCompensationBoundary() async {
        let prior = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let first = settings(binding: binding(id: "22222222-2222-2222-2222-222222222222", keyCode: 2, action: .rightHalf))
        let second = settings(binding: binding(id: "33333333-3333-3333-3333-333333333333", keyCode: 3, action: .maximize))
        let store = RuntimeSettingsStore(initial: prior)
        let manager = RuntimeHotkeyManager()
        await manager.pauseNextReconciliation()
        let updater = HotkeyRuntimeBindingUpdater(store: store, manager: manager)

        let firstTask = Task { await updater.applyValidated(first) }
        await manager.waitUntilReconciliationPaused()
        let secondTask = Task { await updater.applyValidated(second) }
        await Task.yield()
        let savesBeforeResume = await store.saveCallCount
        await manager.resumeReconciliation()
        let firstResult = await firstTask.value
        let secondResult = await secondTask.value
        let savedSettings = await store.currentSettings

        XCTAssertEqual(savesBeforeResume, 1)
        XCTAssertEqual(firstResult, .applied(.active(bindingIDs: first.bindings.map(\.id))))
        XCTAssertEqual(secondResult, .applied(.active(bindingIDs: second.bindings.map(\.id))))
        XCTAssertEqual(savedSettings, second)
    }

    func testSuccessfulUpdatePersistsBindingsForAFreshUpdaterStart() async {
        let prior = settings(binding: binding(id: "11111111-1111-1111-1111-111111111111", keyCode: 0, action: .leftHalf))
        let desired = settings(binding: binding(id: "22222222-2222-2222-2222-222222222222", keyCode: 2, action: .rightHalf))
        let store = RuntimeSettingsStore(initial: prior)
        let firstManager = RuntimeHotkeyManager()
        let firstUpdater = HotkeyRuntimeBindingUpdater(store: store, manager: firstManager)
        _ = await firstUpdater.applyValidated(desired)
        let freshManager = RuntimeHotkeyManager()
        let freshUpdater = HotkeyRuntimeBindingUpdater(store: store, manager: freshManager)

        let start = await freshUpdater.start()
        let saves = await store.saveCallCount

        XCTAssertEqual(start, .active(settings: desired, origin: .persisted(schemaVersion: 1)))
        XCTAssertEqual(saves, 1)
    }
}

private actor RuntimeSettingsStore: SettingsStoring {
    private(set) var currentSettings: HotkeySettings
    private var saveResults: [SettingsSaveResult] = []

    private let origin: SettingsLoadOrigin
    private(set) var saveCallCount = 0

    init(initial: HotkeySettings, origin: SettingsLoadOrigin = .persisted(schemaVersion: 1)) {
        currentSettings = initial
        self.origin = origin
    }

    func load() async -> SettingsLoadResult {
        .loaded(currentSettings, origin: origin)
    }

    func save(_ settings: HotkeySettings) async -> SettingsSaveResult {
        saveCallCount += 1
        let result = saveResults.isEmpty ? .saved(schemaVersion: 1) : saveResults.removeFirst()
        if case .saved = result { currentSettings = settings }
        return result
    }

    func enqueueSaveResult(_ result: SettingsSaveResult) {
        saveResults.append(result)
    }
}

private actor RuntimeHotkeyManager: GlobalHotkeyManaging {
    nonisolated let events = AsyncStream<HotkeyInvocation> { _ in }

    private var nextSnapshots: [HotkeyRegistrationSnapshot] = []
    private var bindings: [HotkeyBinding]
    private var pausedReconciliation: CheckedContinuation<Void, Never>?
    private var pausedObserver: CheckedContinuation<Void, Never>?
    private var pauseNext = false
    private(set) var registrationPassCount = 0

    init(active: [HotkeyBinding] = []) {
        bindings = active
    }

    var activeBindingIDs: [UUID] { bindings.map(\.id) }

    func reconcile(_ requested: [HotkeyBinding]) async -> HotkeyRegistrationSnapshot {
        if bindings == requested, nextSnapshots.isEmpty { return .active(bindingIDs: requested.map(\.id)) }
        registrationPassCount += 1
        if pauseNext {
            pauseNext = false
            pausedObserver?.resume()
            pausedObserver = nil
            await withCheckedContinuation { pausedReconciliation = $0 }
        }
        let snapshot = nextSnapshots.isEmpty
            ? .active(bindingIDs: requested.map(\.id))
            : nextSnapshots.removeFirst()
        switch snapshot {
        case let .active(bindingIDs) where bindingIDs == requested.map(\.id):
            bindings = requested
        case let .degraded(activeBindingIDs, _):
            bindings = activeBindingIDs.map { id in
                HotkeyBinding(id: id, hardwareKeyCode: 0, modifiers: [], actionID: .leftHalf)
            }
        default:
            break
        }
        return snapshot
    }

    func enqueue(_ snapshot: HotkeyRegistrationSnapshot) {
        nextSnapshots.append(snapshot)
    }

    func pauseNextReconciliation() { pauseNext = true }

    func waitUntilReconciliationPaused() async {
        await withCheckedContinuation { pausedObserver = $0 }
    }

    func resumeReconciliation() {
        pausedReconciliation?.resume()
        pausedReconciliation = nil
    }
}

private func settings(binding: HotkeyBinding) -> HotkeySettings {
    HotkeySettings(bindings: [binding])
}

private func binding(id: String, keyCode: UInt16, action: ActionID) -> HotkeyBinding {
    HotkeyBinding(
        id: UUID(uuidString: id)!,
        hardwareKeyCode: keyCode,
        modifiers: [.command, .option],
        actionID: action
    )
}
