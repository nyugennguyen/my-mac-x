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

/// Regression coverage for the Settings-runtime write path, which persists the WHOLE
/// configuration document.
///
/// `ProductionSettingsRuntime` starts life with an empty in-memory `ConfigurationSnapshot`
/// (hotkeys included) and only replaces it once the asynchronous `start()` load completes.
/// `apply(_:)` is synchronous and fire-and-forget, so a routine change that lands before —
/// or without — that load persists `hotkeyBindings: []` over the user's real hotkeys while
/// `GlobalHotkeyManager` keeps firing the old registrations from memory.
///
/// These tests drive the REAL persistence stack (SettingsStore + ConfigurationArchive +
/// InMemorySettingsDocumentAdapter) and assert the DESIRED behavior, so the pre-load test
/// reproduces the bug until the runtime stops persisting a stale/emptier hotkey list.
@MainActor
final class SettingsRuntimePersistenceRegressionTests: XCTestCase {

    /// THE BUG TEST: a Settings change that races the initial load must not erase the global
    /// hotkeys already on disk. The runtime was never given a chance to load them, but the
    /// document is authoritative and the user's hotkeys are not the thing being edited.
    func testSettingsChangeBeforeInitialLoadPreservesPersistedGlobalHotkeys() async throws {
        let binding = makeBinding("77777777-7777-7777-7777-777777777777")
        let seeded = configuration(bindings: [binding])
        let store = try await store(seeding: seeded)

        let runtime = try makeRuntime(store: store)

        // A real race: the Settings window accepts a Snap toggle while start() is still loading.
        // start() is deliberately NOT called, which is exactly the state the runtime is in
        // during the load window (and after it, if the load never lands).
        runtime.apply(.snappingEnabled(false))

        // apply() only spawns the persist Task; wait for the write to land on disk.
        await eventually { await self.persistedSnappingEnabled(store) == false }

        let persisted = await persistedBindings(store)
        XCTAssertEqual(
            persisted,
            [binding],
            "REGRESSION: a Snap toggle that raced the initial load erased the persisted global hotkey (document now holds \(persisted.count) bindings instead of 1)"
        )
    }

    /// The normal path: once start() has loaded the document, a change must persist the loaded
    /// hotkeys unchanged, and the runtime's in-memory presentation must agree with the store.
    ///
    /// `SettingsHotkeysSnapshot.globalHotkeys` DOES surface the runtime's bindings (one
    /// `SettingsCommandTreeItem` per `HotkeyBinding`), so a divergence check is possible here.
    func testSettingsChangeAfterLoadedSnapshotPreservesPersistedGlobalHotkeys() async throws {
        let binding = makeBinding("88888888-8888-8888-8888-888888888888")
        let seeded = configuration(bindings: [binding])
        let store = try await store(seeding: seeded)

        let runtime = try makeRuntime(store: store)
        runtime.start()

        // Wait until the async load has actually replaced the runtime's empty snapshot.
        await eventually { runtime.currentSettings().hotkeys.globalHotkeys.count == 1 }
        XCTAssertEqual(
            runtime.currentSettings().hotkeys.globalHotkeys.count,
            1,
            "Test precondition: start() must load the seeded hotkey into the runtime"
        )

        runtime.apply(.snappingEnabled(false))
        await eventually { await self.persistedSnappingEnabled(store) == false }

        let persisted = await persistedBindings(store)
        XCTAssertEqual(
            persisted,
            [binding],
            "REGRESSION: a Snap toggle erased a global hotkey the runtime had already loaded (document now holds \(persisted.count) bindings instead of 1)"
        )

        let inMemory = runtime.currentSettings().hotkeys.globalHotkeys.count
        XCTAssertEqual(
            inMemory,
            persisted.count,
            "REGRESSION: the Settings GUI shows \(inMemory) global hotkeys while the document holds \(persisted.count)"
        )
    }

    /// The contract stated independently of the initial-load race: a change must preserve
    /// persisted hotkeys the runtime has never observed, for any change kind. Two bindings and
    /// a different change case than the bug test, so the guarantee is not specific to
    /// `.snappingEnabled` or to a single binding.
    func testSettingsChangePreservesPersistedHotkeysThatTheRuntimeNeverLoaded() async throws {
        let first = makeBinding("99999999-9999-9999-9999-999999999999")
        let second = makeBinding("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", keyCode: 5)
        let seeded = configuration(bindings: [first, second], dwellMilliseconds: 150)
        let store = try await store(seeding: seeded)

        let runtime = try makeRuntime(store: store)

        runtime.apply(.snappingDwellMilliseconds(250))
        await eventually { await self.persistedDwellMilliseconds(store) == 250 }

        let persisted = await persistedBindings(store)
        XCTAssertEqual(
            persisted,
            [first, second],
            "REGRESSION: changing the Snap dwell erased \(2 - persisted.count) persisted global hotkey(s) the runtime never loaded"
        )
    }

    // MARK: - Fixtures

    private func configuration(
        bindings: [HotkeyBinding],
        dwellMilliseconds: UInt32 = 150
    ) -> ConfigurationSnapshot {
        ConfigurationSnapshot(
            general: GeneralSettings(launchesAtLogin: false),
            snapping: SnappingSettings(
                isEnabled: true,
                trigger: .notch,
                dwellMilliseconds: dwellMilliseconds,
                showsPlacementPreview: true,
                usesReducedEffects: false
            ),
            hotkeySettings: HotkeySettings(bindings: bindings),
            layouts: [],
            displayProfiles: []
        )
    }

    private func store(seeding snapshot: ConfigurationSnapshot) async throws -> SettingsStore {
        let store = SettingsStore(documents: InMemorySettingsDocumentAdapter(), actionRegistry: .builtIn)
        let result = await store.saveConfiguration(snapshot)
        XCTAssertEqual(
            result,
            .saved(schemaVersion: ConfigurationArchive.currentSchemaVersion),
            "Test precondition: the configuration must be persisted before the runtime is constructed"
        )
        return store
    }

    private func makeRuntime(store: SettingsStore) throws -> ProductionSettingsRuntime {
        ProductionSettingsRuntime(
            store: store,
            appRules: AppRuleRuntime(),
            profileLayouts: try DisplayProfileLayoutRuntime(stableDisplays: RuntimePersistenceStableDisplays()),
            accessibilityPermissionStatus: { .granted },
            inputMonitoringAccess: { true },
            eventTapStatus: { .active },
            appStatus: { .ready },
            openSystemSettings: {},
            openGlobalHotkeySettings: {},
            openSuperModeSettings: {}
        )
    }

    private func persistedBindings(_ store: SettingsStore) async -> [HotkeyBinding] {
        switch await store.load() {
        case let .loaded(settings, _): settings.bindings
        }
    }

    private func persistedSnappingEnabled(_ store: SettingsStore) async -> Bool {
        switch await store.loadConfiguration() {
        case let .loaded(snapshot, _): snapshot.snapping.isEnabled
        }
    }

    private func persistedDwellMilliseconds(_ store: SettingsStore) async -> UInt32 {
        switch await store.loadConfiguration() {
        case let .loaded(snapshot, _): snapshot.snapping.dwellMilliseconds
        }
    }

    private func makeBinding(_ id: String, keyCode: UInt16 = 4) -> HotkeyBinding {
        HotkeyBinding(
            id: UUID(uuidString: id)!,
            hardwareKeyCode: keyCode,
            modifiers: [.control],
            actionID: .leftHalf
        )
    }
}

/// `ProductionSettingsRuntime` requires a stable-display resolver; this suite needs none.
/// Named uniquely to avoid colliding with the file-scope stubs in the other AppShell and
/// CrossDisplayKit test files.
private struct RuntimePersistenceStableDisplays: StableDisplayIdentifying {
    func stableDisplayID(for displayID: DisplayID) -> StableDisplayID? { nil }
}

@MainActor
private func eventually(
    timeout: Duration = .milliseconds(2_000),
    condition: @escaping () async -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()), clock.now < deadline {
        await Task.yield()
    }
}