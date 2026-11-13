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

/// Regression coverage: the launch race must not erase layouts or display profiles, while a
/// genuine layout save must still win over what is on disk.
@MainActor
final class SettingsRuntimeLayoutPersistenceTests: XCTestCase {

    private func layout() -> LayoutDraft {
        LayoutDraft(
            id: "custom-coding",
            name: "Coding",
            regions: [
                LayoutRegionDraft(id: LayoutRegionID(rawValue: "editor"), normalizedFrame: CGRect(x: 0, y: 0, width: 0.625, height: 1)),
                LayoutRegionDraft(id: LayoutRegionID(rawValue: "terminal"), normalizedFrame: CGRect(x: 0.625, y: 0, width: 0.375, height: 0.5)),
                LayoutRegionDraft(id: LayoutRegionID(rawValue: "preview"), normalizedFrame: CGRect(x: 0.625, y: 0.5, width: 0.375, height: 0.5)),
            ]
        )
    }

    private func seededSnapshot() -> ConfigurationSnapshot {
        ConfigurationSnapshot(
            general: GeneralSettings(launchesAtLogin: false),
            snapping: SnappingSettings(
                isEnabled: true,
                trigger: .notch,
                dwellMilliseconds: 150,
                showsPlacementPreview: true,
                usesReducedEffects: false
            ),
            hotkeySettings: HotkeySettings(bindings: []),
            layouts: [layout()],
            displayProfiles: []
        )
    }

    private func makeRuntime(_ store: SettingsStore) throws -> ProductionSettingsRuntime {
        ProductionSettingsRuntime(
            store: store,
            appRules: AppRuleRuntime(),
            profileLayouts: try DisplayProfileLayoutRuntime(stableDisplays: LayoutRaceStableDisplays()),
            accessibilityPermissionStatus: { .granted },
            inputMonitoringAccess: { true },
            eventTapStatus: { .active },
            appStatus: { .ready },
            openSystemSettings: {},
            openGlobalHotkeySettings: {},
            openSuperModeSettings: {}
        )
    }

    func testLayoutsSurviveAChangeThatRacesTheInitialLoad() async throws {
        let store = SettingsStore(documents: InMemorySettingsDocumentAdapter(), actionRegistry: .builtIn)
        let seedResult = await store.saveConfiguration(seededSnapshot())
        XCTAssertEqual(seedResult, SettingsSaveResult.saved(schemaVersion: ConfigurationArchive.currentSchemaVersion))

        let runtime = try makeRuntime(store)
        runtime.apply(.snappingEnabled(false))
        for _ in 0..<400 { await Task.yield() }

        switch await store.loadConfiguration() {
        case let .loaded(snapshot, _):
            XCTAssertEqual(
                snapshot.layouts.map(\.id),
                ["custom-coding"],
                "REGRESSION: the launch race erased persisted layouts (document now holds \(snapshot.layouts.count))"
            )
        }
    }

    func testSavingALayoutStillReplacesWhatIsOnDisk() async throws {
        let store = SettingsStore(documents: InMemorySettingsDocumentAdapter(), actionRegistry: .builtIn)
        let seedResult = await store.saveConfiguration(seededSnapshot())
        XCTAssertEqual(seedResult, SettingsSaveResult.saved(schemaVersion: ConfigurationArchive.currentSchemaVersion))

        let runtime = try makeRuntime(store)
        let replacement = SettingsLayoutDraft(
            id: "custom-coding",
            name: "Renamed",
            regions: [SettingsLayoutRegionDraft(id: "full", normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 1))]
        )
        runtime.apply(.saveLayout(replacement))
        for _ in 0..<400 { await Task.yield() }

        switch await store.loadConfiguration() {
        case let .loaded(snapshot, _):
            XCTAssertEqual(
                snapshot.layouts.first(where: { $0.id == "custom-coding" })?.name,
                "Renamed",
                "REGRESSION: a genuine layout save was overwritten by the stale document value"
            )
        }
    }
}

private struct LayoutRaceStableDisplays: StableDisplayIdentifying {
    func stableDisplayID(for displayID: DisplayID) -> StableDisplayID? { nil }
}