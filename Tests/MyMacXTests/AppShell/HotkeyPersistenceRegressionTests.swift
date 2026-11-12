import XCTest
@testable import MyMacX

/// Regression coverage for global hotkeys disappearing from the Settings GUI after the
/// Settings window is closed and reopened.
///
/// These tests drive the REAL persistence stack (SettingsStore + ConfigurationArchive +
/// InMemorySettingsDocumentAdapter) instead of stubbing `load`/`apply` closures, because the
/// stubbed GlobalHotkeySettingsModel tests cannot observe a save/reload asymmetry between the
/// live runtime and what is actually on disk.
///
/// Each test asserts the DESIRED behavior, so a failing test reproduces the bug.
@MainActor
final class HotkeyPersistenceRegressionTests: XCTestCase {

    func testSavedHotkeySurvivesGlobalHotkeyEditorReopenThroughTheRealStore() async {
        let store = store()
        let desired = HotkeySettings(bindings: [binding("11111111-1111-1111-1111-111111111111")])
        let seeded = await store.save(desired)
        XCTAssertEqual(
            seeded,
            .saved(schemaVersion: ConfigurationArchive.currentSchemaVersion),
            "Test precondition: the editor's save path must be able to persist a hotkey"
        )

        let model = await GlobalHotkeySettingsModel(
            actionRegistry: .builtIn,
            load: {
                switch await store.load() {
                case let .loaded(settings, _): settings
                }
            },
            apply: { settings in
                switch await store.save(settings) {
                case .saved: return .applied(.active(bindingIDs: settings.bindings.map(\.id)))
                case let .failed(failure): return .saveFailed(failure)
                }
            }
        )

        await model.reload()
        model.addBinding()
        await model.save()
        let savedCount = model.settings.bindings.count
        XCTAssertEqual(savedCount, 2, "Test precondition: the editor holds two bindings after Add + Save")

        // Reopening the Settings window presents no new model; it calls reload() on this one.
        await model.reload()
        let reopenedCount = model.settings.bindings.count
        XCTAssertEqual(
            reopenedCount,
            savedCount,
            "REGRESSION: after close + reopen the GUI shows \(reopenedCount) bindings, but \(savedCount) were saved"
        )
    }

    func testUnrelatedSettingsSavePreservesPersistedHotkeys() async throws {
        let store = store()
        let original = ConfigurationSnapshot(
            general: GeneralSettings(launchesAtLogin: false),
            snapping: SnappingSettings(
                isEnabled: true,
                trigger: .notch,
                dwellMilliseconds: 150,
                showsPlacementPreview: true,
                usesReducedEffects: false
            ),
            hotkeySettings: HotkeySettings(bindings: [binding("22222222-2222-2222-2222-222222222222")]),
            layouts: [],
            displayProfiles: []
        )
        let firstSave = await store.saveConfiguration(original)
        XCTAssertEqual(
            firstSave,
            .saved(schemaVersion: ConfigurationArchive.currentSchemaVersion),
            "Test precondition: the configuration must be persisted before the unrelated save"
        )

        // A later, unrelated settings write built from a runtime snapshot.
        let later = ConfigurationSnapshot(
            general: original.general,
            snapping: SnappingSettings(
                isEnabled: false,
                trigger: .notch,
                dwellMilliseconds: 150,
                showsPlacementPreview: true,
                usesReducedEffects: false
            ),
            hotkeySettings: original.hotkeySettings,
            layouts: original.layouts,
            displayProfiles: original.displayProfiles
        )
        let secondSave = await store.saveConfiguration(later)
        XCTAssertEqual(
            secondSave,
            .saved(schemaVersion: ConfigurationArchive.currentSchemaVersion),
            "Test precondition: the unrelated save must succeed"
        )

        let persisted = await persistedBindings(store)
        XCTAssertEqual(
            persisted,
            original.hotkeySettings.bindings,
            "REGRESSION: a routine settings save erased the persisted global hotkey"
        )
    }

    func testSuperModeSaveDoesNotErasePersistedGlobalHotkeys() async {
        let store = store()
        let globalHotkey = binding("33333333-3333-3333-3333-333333333333")
        let seeded = await store.save(HotkeySettings(bindings: [globalHotkey]))
        XCTAssertEqual(
            seeded,
            .saved(schemaVersion: ConfigurationArchive.currentSchemaVersion),
            "Test precondition: the global hotkey must exist on disk before Super Mode saves"
        )

        // A caller that only knows about Super Mode passes an empty hotkey list.
        let module = makeModule(store: store)
        let result = await module.apply(SuperModeConfiguration.default, hotkeyBindings: [])

        let persisted = await persistedBindings(store)
        XCTAssertEqual(
            persisted,
            [globalHotkey],
            "REGRESSION: saving Super Mode erased the global hotkey it was not editing, so settings.json holds \(persisted) while the live runtime keeps firing the old registration"
        )

        guard case let .applied(appliedSettings, _) = result else {
            return XCTFail("Expected the valid Super Mode configuration to be applied, got \(result)")
        }
        XCTAssertEqual(
            appliedSettings.bindings,
            persisted,
            "REGRESSION: apply reported bindings \(appliedSettings.bindings) that do not match what it persisted (\(persisted))"
        )
    }

    func testSuperModeSaveIgnoresCallerSuppliedStaleBindings() async {
        let store = store()
        let persistedHotkey = binding("44444444-4444-4444-4444-444444444444")
        let staleHotkey = binding("55555555-5555-5555-5555-555555555555", keyCode: 5)
        let seeded = await store.save(HotkeySettings(bindings: [persistedHotkey]))
        XCTAssertEqual(
            seeded,
            .saved(schemaVersion: ConfigurationArchive.currentSchemaVersion),
            "Test precondition: the current global hotkey must exist on disk"
        )

        // The caller's cached snapshot is stale: it still carries a hotkey the store no longer holds.
        let module = makeModule(store: store)
        let result = await module.apply(SuperModeConfiguration.default, hotkeyBindings: [staleHotkey])

        let persisted = await persistedBindings(store)
        XCTAssertEqual(
            persisted,
            [persistedHotkey],
            "REGRESSION: a stale caller-supplied list \([staleHotkey]) replaced the hotkeys the store currently holds"
        )

        guard case let .applied(appliedSettings, _) = result else {
            return XCTFail("Expected the valid Super Mode configuration to be applied, got \(result)")
        }
        XCTAssertEqual(
            appliedSettings.bindings,
            persisted,
            "REGRESSION: apply reported bindings \(appliedSettings.bindings) that do not match what it persisted (\(persisted))"
        )
    }

    func testSuperModeSaveWithCurrentBindingsKeepsThemPersistedAndReportsTheSameSettings() async {
        let store = store()
        let currentHotkey = binding("66666666-6666-6666-6666-666666666666")
        let seeded = await store.save(HotkeySettings(bindings: [currentHotkey]))
        XCTAssertEqual(
            seeded,
            .saved(schemaVersion: ConfigurationArchive.currentSchemaVersion),
            "Test precondition: the current global hotkey must exist on disk"
        )

        let configuration = SuperModeConfiguration(
            prefix: HotkeyChord(hardwareKeyCode: 49, modifiers: [.control]),
            timeoutMilliseconds: 1_500,
            commandBindings: []
        )
        let module = makeModule(store: store)
        let result = await module.apply(configuration, hotkeyBindings: [currentHotkey])

        guard case let .applied(appliedSettings, _) = result else {
            return XCTFail("Expected the valid Super Mode configuration to be applied, got \(result)")
        }
        let persisted = await persistedBindings(store)
        XCTAssertEqual(persisted, [currentHotkey], "The up-to-date caller list must stay persisted")
        XCTAssertEqual(
            appliedSettings,
            HotkeySettings(bindings: [currentHotkey], superModeConfiguration: configuration),
            "apply must persist and report the Super Mode configuration it actually saved"
        )
    }

    private func store() -> SettingsStore {
        SettingsStore(documents: InMemorySettingsDocumentAdapter(), actionRegistry: .builtIn)
    }

    private func makeModule(store: SettingsStore) -> SuperModeConfigurationModule {
        SuperModeConfigurationModule(
            store: store,
            runtime: SuperModeRuntimeConfiguration(),
            validator: SuperModeConfigurationValidator(actionRegistry: .builtIn)
        )
    }

    private func persistedBindings(_ store: SettingsStore) async -> [HotkeyBinding] {
        switch await store.load() {
        case let .loaded(settings, _): settings.bindings
        }
    }

    private func binding(_ id: String, keyCode: UInt16 = 4) -> HotkeyBinding {
        HotkeyBinding(
            id: UUID(uuidString: id)!,
            hardwareKeyCode: keyCode,
            modifiers: [.control],
            actionID: .leftHalf
        )
    }
}