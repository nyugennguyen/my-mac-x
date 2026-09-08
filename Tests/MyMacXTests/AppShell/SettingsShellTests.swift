import AppKit
import SwiftUI
import XCTest
@testable import MyMacX

@MainActor
final class SettingsShellTests: XCTestCase {
    func testHotkeySummaryRendersLongLocalizedContentAtAccessibilityTextSizeAndMinimumWindow() {
        let runtime = RuntimeHarness(
            snapshot: .init(
                general: .init(accessibility: .granted, inputMonitoringGranted: true, launchesAtLogin: false),
                snapping: .default,
                hotkeys: .init(
                    editor: .superMode,
                    recorder: .recording,
                    validationMessage: "The shortcut Control Option Shift Command F12 is already assigned to another Window Action.",
                    commandTree: [
                        .init(
                            keySequence: "Control Option Shift Command Space, Page Down",
                            actionTitle: "Move the captured window to the previous connected Display",
                            isAvailable: false
                        ),
                    ]
                )
            )
        )
        let controller = SettingsShellWindowController(runtime: runtime)
        controller.select(.hotkeys)
        let size = NSSize(width: 760, height: 520)

        assertProductionSettingsWindowRenders(
            controller.windowForTesting(contentSize: size, dynamicTypeSize: .accessibility3),
            contentSize: size
        )
    }

    func testHotkeySettingsSummaryRendersEmptyErrorAndRecordingAtSupportedWindowSizes() {
        let states: [SettingsHotkeysSnapshot] = [
            .empty,
            .init(
                editor: .hotkeys,
                recorder: .ready,
                validationMessage: "That shortcut is already assigned.",
                commandTree: []
            ),
            .init(
                editor: .superMode,
                recorder: .recording,
                validationMessage: nil,
                commandTree: [
                    .init(keySequence: "Control Space, L", actionTitle: "Left Half", isAvailable: true),
                ]
            ),
        ]

        for state in states {
            let runtime = RuntimeHarness(
                snapshot: .init(
                    general: .init(accessibility: .granted, inputMonitoringGranted: true, launchesAtLogin: false),
                    snapping: .default,
                    hotkeys: state
                )
            )
            let controller = SettingsShellWindowController(runtime: runtime)
            controller.select(.hotkeys)

            for size in [NSSize(width: 880, height: 620), NSSize(width: 760, height: 520)] {
                assertProductionSettingsWindowRenders(
                    controller.windowForTesting(contentSize: size),
                    contentSize: size
                )
            }
        }
    }

    func testQuickActionsEnableOnlyAvailableActionsForAnEligibleFocusedWindow() {
        let registry = ActionRegistry(actions: [
            .init(id: .leftHalf, title: "Left Half", symbolName: "rectangle.lefthalf.filled", availability: .available),
            .init(id: .nativeFullScreen, title: "Native Full Screen", symbolName: "arrow.up.left.and.arrow.down.right", availability: .unavailable(.experimental)),
        ])

        let items = MenuQuickActionPlanner().plan(
            focusedWindow: .active,
            registry: registry
        )

        XCTAssertEqual(items.map(\.actionID), [.leftHalf, .nativeFullScreen])
        XCTAssertTrue(items[0].isEnabled)
        XCTAssertNil(items[0].disabledReason)
        XCTAssertFalse(items[1].isEnabled)
        XCTAssertEqual(items[1].disabledReason, SettingsCopy.experimentalActionUnavailable)
    }

    func testQuickActionsExplainNoFocusedAndUnsupportedWindowWithoutOfferingExecution() {
        let registry = ActionRegistry(actions: [
            .init(id: .maximize, title: "Maximize", symbolName: "rectangle.inset.filled", availability: .available),
        ])
        let planner = MenuQuickActionPlanner()

        let noFocusedWindow = planner.plan(
            focusedWindow: .noFocusedEligibleWindow,
            registry: registry
        )
        let unsupportedWindow = planner.plan(
            focusedWindow: .unsupportedFocusedWindow,
            registry: registry
        )

        XCTAssertEqual(noFocusedWindow.first?.disabledReason, SettingsCopy.noFocusedEligibleWindow)
        XCTAssertFalse(noFocusedWindow.first?.isEnabled ?? true)
        XCTAssertEqual(unsupportedWindow.first?.disabledReason, SettingsCopy.unsupportedFocusedWindow)
        XCTAssertFalse(unsupportedWindow.first?.isEnabled ?? true)
    }

    func testQuickActionsCanDisableOneActionForTheCapturedWindowCapability() {
        let registry = ActionRegistry(actions: [
            .init(id: .leftHalf, title: "Left Half", symbolName: "rectangle.lefthalf.filled", availability: .available),
            .init(id: .nativeFullScreen, title: "Native Full Screen", symbolName: "arrow.up.left.and.arrow.down.right", availability: .available),
        ])

        let items = MenuQuickActionPlanner().plan(
            focusedWindow: .activeWithUnavailableActions([.nativeFullScreen: "Already in full screen."]),
            registry: registry
        )

        XCTAssertTrue(items[0].isEnabled)
        XCTAssertFalse(items[1].isEnabled)
        XCTAssertEqual(items[1].disabledReason, "Already in full screen.")
    }

    func testQuickActionCapabilityPlanningDisablesOnlyActionsTheCapturedWindowCannotPerform() {
        let capabilities = WindowCapabilities(
            isMovable: false,
            isResizable: true,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )

        let state = MenuQuickActionPlanner().focusedWindowState(capabilities: capabilities)

        guard case let .activeWithUnavailableActions(unavailable) = state else {
            return XCTFail("Expected per-action capability restrictions")
        }
        XCTAssertNil(unavailable[.leftHalf])
        XCTAssertEqual(unavailable[.moveDisplayNext], SettingsCopy.actionRequiresMovableWindow)
        XCTAssertEqual(unavailable[.moveDisplayPrevious], SettingsCopy.actionRequiresMovableWindow)
        XCTAssertEqual(unavailable[.nativeFullScreen], SettingsCopy.nativeFullScreenStateUnavailable)
    }

    func testQuickActionDispatcherCommitsThroughWindowActionInterfaceAsMenuBarSource() async {
        let actions = RecordingMenuWindowActions()
        let dispatcher = MenuQuickActionDispatcher(windowActions: actions)

        await dispatcher.perform(.maximize)

        let intent = await actions.lastIntent
        guard case let .commit(action, source)? = intent else {
            return XCTFail("Expected a direct Window Action commit")
        }
        XCTAssertEqual(action, .maximize)
        XCTAssertEqual(source, .menuBar)
    }

    func testSnappingChangesApplyToRuntimeImmediatelyAndReloadsPermissionStatus() {
        let runtime = RuntimeHarness(
            snapshot: .init(
                general: .init(
                    accessibility: .notRequested,
                    inputMonitoringGranted: false,
                    launchesAtLogin: false
                ),
                snapping: .init(
                    isEnabled: false,
                    trigger: .topCenter,
                    triggerAvailability: .available,
                    dwellMilliseconds: 150,
                    showsPlacementPreview: true,
                    usesReducedEffects: false
                ),
                hotkeys: .empty
            )
        )
        let model = SettingsShellModel(runtime: runtime)

        model.setSnappingEnabled(true)
        runtime.snapshot.general.accessibility = .granted
        model.reload()

        XCTAssertEqual(runtime.changes, [.snappingEnabled(true)])
        XCTAssertTrue(model.snapshot.snapping.isEnabled)
        XCTAssertEqual(model.snapshot.general.accessibility, .granted)
        XCTAssertEqual(model.generalPermissionMessage, SettingsCopy.accessibilityGranted)
    }

    func testHotkeyEditorStateProvidesAnAccessibleTreeAndRoutesToTheRequestedEditor() {
        let runtime = RuntimeHarness(
            snapshot: .init(
                general: .init(accessibility: .granted, inputMonitoringGranted: true, launchesAtLogin: false),
                snapping: .default,
                hotkeys: .init(
                    editor: .superMode,
                    recorder: .recording,
                    validationMessage: "Two bindings use the same key sequence.",
                    commandTree: [
                        .init(keySequence: "Control Space, L", actionTitle: "Left Half", isAvailable: true),
                        .init(keySequence: "Control Space, R", actionTitle: "Right Half", isAvailable: true),
                    ]
                )
            )
        )
        let model = SettingsShellModel(runtime: runtime)

        model.select(.hotkeys)
        let presentation = try! XCTUnwrap(model.hotkeyEditorPresentation)
        model.openHotkeyEditor()

        XCTAssertEqual(model.selectedSection, .hotkeys)
        XCTAssertEqual(presentation.recorderAccessibilityLabel, SettingsCopy.recordingShortcut)
        XCTAssertEqual(presentation.commandTreeAccessibilityLabel, "Super Mode commands, 2 bindings.")
        XCTAssertEqual(presentation.commandTree[0].accessibilityLabel, "Control Space, L: Left Half")
        XCTAssertEqual(runtime.openedEditors, [.superMode])
    }

    func testMicrocopyProvidesStableAccessibilityLabelsAndEmptyState() {
        XCTAssertEqual(SettingsCopy.hotkeyEmptyState, "No Super Mode commands are configured.")
        XCTAssertEqual(SettingsAccessibilityID.snappingEnabled, "settings.snapping.enabled")
        XCTAssertEqual(SettingsAccessibilityID.hotkeyCommandTree, "settings.hotkeys.command-tree")
    }

    func testSettingsWindowCanRouteDirectlyToHotkeysAndSuperModeSection() {
        let runtime = RuntimeHarness(
            snapshot: .init(
                general: .init(
                    accessibility: .granted,
                    inputMonitoringGranted: true,
                    launchesAtLogin: false
                ),
                snapping: .default,
                hotkeys: .init(
                    editor: .superMode,
                    recorder: .ready,
                    validationMessage: nil,
                    commandTree: []
                )
            )
        )
        let controller = SettingsShellWindowController(runtime: runtime)

        controller.select(.hotkeys)
        controller.modelForTesting.openHotkeyEditor()

        XCTAssertEqual(controller.modelForTesting.selectedSection, .hotkeys)
        XCTAssertEqual(runtime.openedEditors, [.superMode])
    }


    func testAllSprintSixSectionsAreKeyboardSelectableAndEditorsRouteThroughRuntime() {
        let runtime = RuntimeHarness(snapshot: baselineSnapshot())
        let model = SettingsShellModel(runtime: runtime)

        for section in SettingsSection.allCases { model.select(section) }
        model.openHotkeyEditor(.hotkeys)
        model.openHotkeyEditor(.superMode)

        XCTAssertEqual(SettingsSection.allCases, [.general, .snapping, .hotkeys, .layouts, .displays, .appRules, .transfer, .about])
        XCTAssertEqual(runtime.openedEditors, [.hotkeys, .superMode])
    }

    func testLayoutProfileAndAppRuleEditsApplyImmediatelyThroughRuntime() {
        let runtime = RuntimeHarness(snapshot: baselineSnapshot())
        let model = SettingsShellModel(runtime: runtime)
        let layout = SettingsLayoutDraft(
            id: "focus",
            name: "Focus",
            regions: [.init(id: "main", normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 1))]
        )
        let profile = SettingsDisplayProfileDraft(stableDisplayID: "display-1", gap: 12, layoutIDs: ["focus"])
        let appID = ApplicationBundleIdentifier("com.example.Editor")!

        model.saveLayout(layout)
        let edit = SettingsLayoutEdit.split(
            regionID: "main", direction: .columns, firstFraction: 0.5,
            firstRegionID: "left", secondRegionID: "right"
        )
        model.editLayout(id: layout.id, edit: edit)
        model.saveDisplayProfile(profile)
        model.replaceAppRules(defaultDecision: .included, rules: [.init(bundleIdentifier: appID, decision: .excluded)])

        XCTAssertEqual(runtime.changes, [
            .saveLayout(layout),
            .editLayout(id: layout.id, edit: edit),
            .saveDisplayProfile(profile),
            .replaceAppRules(defaultDecision: .included, rules: [.init(bundleIdentifier: appID, decision: .excluded)]),
        ])
    }

    func testUserCanRequestProfilesForConnectedDisplaysFromAnEmptyConfiguration() {
        let runtime = RuntimeHarness(snapshot: baselineSnapshot())
        let model = SettingsShellModel(runtime: runtime)

        model.createDisplayProfilesForConnectedDisplays()

        XCTAssertEqual(runtime.changes, [.createDisplayProfilesForConnectedDisplays])
    }

    func testImportExportAndRedactedDiagnosticsCommandsAreReachable() {
        let runtime = RuntimeHarness(snapshot: baselineSnapshot())
        let model = SettingsShellModel(runtime: runtime)

        model.importConfiguration()
        model.exportConfiguration()
        model.copyDiagnosticsReport()

        XCTAssertEqual(runtime.operations, [.importConfiguration, .exportConfiguration, .copyDiagnostics])
        XCTAssertEqual(SettingsAccessibilityID.layoutLibrary, "settings.layouts.library")
        XCTAssertEqual(SettingsAccessibilityID.diagnostics, "settings.about.diagnostics")
    }

    func testAsyncImportRefreshesSettingsOnlyWhenRuntimeFinishes() {
        let runtime = RuntimeHarness(snapshot: baselineSnapshot())
        let model = SettingsShellModel(runtime: runtime)
        var imported = baselineSnapshot()
        imported.general.launchesAtLogin = true
        runtime.importedSnapshot = imported
        runtime.defersImportCompletion = true

        model.importConfiguration()
        XCTAssertFalse(model.snapshot.general.launchesAtLogin)

        runtime.completeImport()
        XCTAssertTrue(model.snapshot.general.launchesAtLogin)
    }

    func testProductionImportRestoreHotAppliesRuntimeAndPersistsBeforeRefreshing() async throws {
        let documents = InMemorySettingsDocumentAdapter()
        let store = SettingsStore(documents: documents, actionRegistry: .builtIn)
        let profileLayouts = try DisplayProfileLayoutRuntime(
            stableDisplays: NoStableDisplays()
        )
        let applied = ImportedHotkeyRecorder()
        let launch = LaunchAtLoginRecorder()
        let runtime = ProductionSettingsRuntime(
            store: store,
            appRules: AppRuleRuntime(),
            profileLayouts: profileLayouts,
            accessibilityPermissionStatus: { .granted },
            inputMonitoringAccess: { true },
            openSystemSettings: {},
            openGlobalHotkeySettings: {},
            openSuperModeSettings: {},
            applyImportedHotkeys: { settings in
                await applied.apply(settings)
                return true
            },
            setLaunchAtLogin: { enabled in launch.apply(enabled); return true }
        )
        let imported = ConfigurationSnapshot(
            general: GeneralSettings(launchesAtLogin: true),
            hotkeySettings: HotkeySettings(bindings: []),
            layouts: [],
            displayProfiles: []
        )
        let refreshed = expectation(description: "settings refreshed")

        runtime.restoreImported(imported) { refreshed.fulfill() }
        await fulfillment(of: [refreshed])

        let appliedSettings = await applied.recordedSettings()
        XCTAssertEqual(appliedSettings, [imported.hotkeySettings])
        XCTAssertEqual(launch.values, [true])
        XCTAssertTrue(runtime.currentSettings().general.launchesAtLogin)
        guard case let .loaded(persisted, _) = await store.loadConfiguration() else {
            return XCTFail("Expected imported configuration")
        }
        XCTAssertEqual(persisted, imported)
    }

    func testFailedImportedRuntimeApplyRollsBackLaunchAtLoginAndKeepsPresentedConfiguration() async throws {
        let store = SettingsStore(
            documents: InMemorySettingsDocumentAdapter(),
            actionRegistry: .builtIn
        )
        let profileLayouts = try DisplayProfileLayoutRuntime(stableDisplays: NoStableDisplays())
        let launch = LaunchAtLoginRecorder()
        let runtime = ProductionSettingsRuntime(
            store: store,
            appRules: AppRuleRuntime(),
            profileLayouts: profileLayouts,
            accessibilityPermissionStatus: { .granted },
            inputMonitoringAccess: { true },
            openSystemSettings: {},
            openGlobalHotkeySettings: {},
            openSuperModeSettings: {},
            applyImportedHotkeys: { _ in false },
            setLaunchAtLogin: { enabled in launch.apply(enabled); return true }
        )
        let imported = ConfigurationSnapshot(
            general: GeneralSettings(launchesAtLogin: true),
            hotkeySettings: HotkeySettings(bindings: []),
            layouts: [],
            displayProfiles: []
        )
        let finished = expectation(description: "rollback finished")

        runtime.restoreImported(imported) { finished.fulfill() }
        await fulfillment(of: [finished])

        XCTAssertEqual(launch.values, [true, false])
        XCTAssertFalse(runtime.currentSettings().general.launchesAtLogin)
        XCTAssertTrue(runtime.currentSettings().transfer.isError)
    }

    private func baselineSnapshot() -> SettingsRuntimeSnapshot {
        .init(
            general: .init(accessibility: .granted, inputMonitoringGranted: true, launchesAtLogin: false),
            snapping: .default,
            hotkeys: .empty
        )
    }
}

private struct NoStableDisplays: StableDisplayIdentifying {
    func stableDisplayID(for displayID: DisplayID) -> StableDisplayID? { nil }
}

private actor ImportedHotkeyRecorder {
    private(set) var settings: [HotkeySettings] = []
    func apply(_ settings: HotkeySettings) { self.settings.append(settings) }
    func recordedSettings() -> [HotkeySettings] { settings }
}

@MainActor
private final class LaunchAtLoginRecorder {
    private(set) var values: [Bool] = []
    func apply(_ enabled: Bool) { values.append(enabled) }
}

private actor RecordingMenuWindowActions: WindowActionPerforming {
    private(set) var lastIntent: WindowIntent?

    func perform(_ intent: WindowIntent) -> WindowActionResult {
        lastIntent = intent
        return WindowActionResult(
            disposition: .succeeded,
            effect: .none,
            undoToken: nil,
            warnings: []
        )
    }
}

@MainActor
private final class RuntimeHarness: SettingsRuntimeProviding {
    enum Operation: Equatable { case importConfiguration, exportConfiguration, copyDiagnostics }
    var snapshot: SettingsRuntimeSnapshot
    var changes: [SettingsRuntimeChange] = []
    var openedEditors: [SettingsHotkeyEditor] = []
    var openedSystemSettings = false
    var operations: [Operation] = []
    var importedSnapshot: SettingsRuntimeSnapshot?
    var defersImportCompletion = false
    private var importCompletion: (@MainActor () -> Void)?

    init(snapshot: SettingsRuntimeSnapshot) {
        self.snapshot = snapshot
    }

    func currentSettings() -> SettingsRuntimeSnapshot {
        snapshot
    }

    func apply(_ change: SettingsRuntimeChange) {
        changes.append(change)
        switch change {
        case let .snappingEnabled(isEnabled):
            snapshot.snapping.isEnabled = isEnabled
        case let .snappingTrigger(trigger):
            snapshot.snapping.trigger = trigger
        case let .snappingDwellMilliseconds(milliseconds):
            snapshot.snapping.dwellMilliseconds = milliseconds
        case let .placementPreviewEnabled(isEnabled):
            snapshot.snapping.showsPlacementPreview = isEnabled
        case let .reducedEffectsEnabled(isEnabled):
            snapshot.snapping.usesReducedEffects = isEnabled
        case let .launchAtLoginEnabled(isEnabled):
            snapshot.general.launchesAtLogin = isEnabled
        case .saveLayout, .editLayout, .deleteLayout, .saveDisplayProfile,
             .createDisplayProfilesForConnectedDisplays, .deleteDisplayProfile, .replaceAppRules:
            break
        }
    }

    func openSystemSettings() {
        openedSystemSettings = true
    }

    func openHotkeyEditor(_ editor: SettingsHotkeyEditor) {
        openedEditors.append(editor)
    }

    func importConfiguration(completion: @escaping @MainActor () -> Void) {
        operations.append(.importConfiguration)
        importCompletion = completion
        if !defersImportCompletion { completeImport() }
    }

    func completeImport() {
        if let importedSnapshot { snapshot = importedSnapshot }
        importCompletion?()
        importCompletion = nil
    }
    func exportConfiguration() { operations.append(.exportConfiguration) }
    func copyDiagnosticsReport() { operations.append(.copyDiagnostics) }
}
