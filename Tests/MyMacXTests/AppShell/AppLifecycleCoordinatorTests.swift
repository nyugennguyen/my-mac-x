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

import AppKit
import XCTest
@testable import MyMacX

final class FirstLaunchOnboardingPolicyTests: XCTestCase {
    func testPresentsExplanationBeforePermissionHasBeenRequested() {
        XCTAssertTrue(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: false,
            permissionState: .notRequested
        ))
    }

    func testDoesNotInterruptReturningOrAlreadyAuthorizedUser() {
        XCTAssertFalse(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: true,
            permissionState: .denied
        ))
        XCTAssertFalse(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: false,
            permissionState: .granted
        ))
    }
}

@MainActor
final class AppLifecycleCoordinatorTests: XCTestCase {
    func testMenuStateCoversPermissionAndSuperModePresentationMatrix() {
        let cases: [(AccessibilityPermissionState, AppShellSuperModeStatus, Bool, String, String, Bool)] = [
            (.granted, .active, false, "Super Mode: Active — Accessibility: Granted", "Pause Super Mode", true),
            (.granted, .active, true, "Super Mode: Paused — Accessibility: Granted", "Resume Super Mode", true),
            (.denied, .unavailable, false, "Super Mode: Unavailable — Accessibility: Denied", "Pause Super Mode", false),
            (.revoked, .unavailable, false, "Super Mode: Unavailable — Accessibility: Revoked", "Pause Super Mode", false),
        ]

        for (permission, runtime, paused, statusTitle, pauseTitle, pauseEnabled) in cases {
            let controller = makeMenuController(
                isSuperModePaused: { paused },
                superModeStatus: { runtime },
                accessibilityPermissionStatus: { permission }
            )

            let state = controller.currentState()
            XCTAssertEqual(state.statusTitle, statusTitle)
            XCTAssertEqual(state.pauseTitle, pauseTitle)
            XCTAssertEqual(state.isPaused, paused)
            XCTAssertEqual(state.isPauseEnabled, pauseEnabled)
        }
    }

    func testProductionMenuUsesNativeHierarchyShortcutsCheckmarkAndAccessibleDisabledReasons() throws {
        let system = AppKitAppShellSystem(
            application: .shared,
            statusBar: .system,
            configuration: AppShellMenuConfiguration(
                openSettings: {},
                toggleSuperModePaused: {},
                isSuperModePaused: { true },
                superModeStatus: { .active },
                accessibilityPermissionStatus: { .granted },
                focusedWindowQuickActionState: { .noFocusedEligibleWindow },
                quickActionRegistry: ActionRegistry(actions: [
                    .init(
                        id: .leftHalf,
                        title: "Left Half",
                        symbolName: "rectangle.lefthalf.filled",
                        availability: .available
                    ),
                ]),
                openSystemSettings: {},
                quit: {}
            )
        )

        let menu = system.makeMenuForTesting()

        XCTAssertEqual(
            menu.items.map { $0.isSeparatorItem ? "separator" : $0.title },
            [
                "Super Mode: Paused — Accessibility: Granted",
                "separator",
                SettingsCopy.quickActionsMenuTitle,
                "separator",
                "Open Settings…",
                "Resume Super Mode",
                "Open System Settings…",
                "separator",
                "Quit My Mac X",
            ]
        )
        let settings = try XCTUnwrap(menu.items.first { $0.title == "Open Settings…" })
        XCTAssertEqual(settings.keyEquivalent, ",")
        XCTAssertEqual(settings.keyEquivalentModifierMask, [.command])
        let pause = try XCTUnwrap(menu.items.first { $0.title == "Resume Super Mode" })
        XCTAssertEqual(pause.state, .on)
        XCTAssertTrue(pause.isEnabled)
        let quit = try XCTUnwrap(menu.items.first { $0.title == "Quit My Mac X" })
        XCTAssertEqual(quit.keyEquivalent, "q")
        XCTAssertEqual(quit.keyEquivalentModifierMask, [.command])

        let quickActions = try XCTUnwrap(
            menu.items.first { $0.title == SettingsCopy.quickActionsMenuTitle }?.submenu
        )
        let disabledAction = try XCTUnwrap(quickActions.items.first)
        XCTAssertFalse(disabledAction.isEnabled)
        XCTAssertEqual(disabledAction.toolTip, SettingsCopy.noFocusedEligibleWindow)
        XCTAssertEqual(disabledAction.accessibilityHelp(), SettingsCopy.noFocusedEligibleWindow)
        XCTAssertFalse(menuContainsRawNumericLabel(menu))
    }

    func testProductionMenuGivesDisabledPauseActionAnAccessibleReason() throws {
        let system = AppKitAppShellSystem(
            application: .shared,
            statusBar: .system,
            configuration: AppShellMenuConfiguration(
                openSettings: {},
                toggleSuperModePaused: {},
                isSuperModePaused: { false },
                superModeStatus: { .unavailable },
                accessibilityPermissionStatus: { .revoked },
                openSystemSettings: {},
                quit: {}
            )
        )

        let menu = system.makeMenuForTesting()
        let pause = try XCTUnwrap(menu.items.first { $0.title == "Pause Super Mode" })

        XCTAssertFalse(pause.isEnabled)
        XCTAssertEqual(pause.toolTip, "Super Mode is not currently available.")
        XCTAssertEqual(pause.accessibilityHelp(), "Super Mode is not currently available.")
    }

    func testProductionMenuBarItemPresentationIsDistinctAndNonCollapsible() {
        let presentation = AppKitAppShellSystem.StatusItemPresentation.standard

        XCTAssertEqual(presentation.length, 54)
        XCTAssertEqual(presentation.symbolName, "rectangle.split.2x2")
        XCTAssertEqual(presentation.title, "MX")
        XCTAssertEqual(presentation.toolTip, "My Mac X")
    }

    func testStartAppliesAccessoryPolicyButDefersMenuBarItemUntilLaunchFinished() {
        let system = AppShellSystemSpy()
        let coordinator = AppLifecycleCoordinator(system: system)

        coordinator.start()

        XCTAssertEqual(
            system.state,
            AppShellSystemState(accessoryPolicyApplications: 1, menuBarItemInstallations: 0)
        )

        coordinator.applicationDidFinishLaunching()

        XCTAssertEqual(
            system.state,
            AppShellSystemState(accessoryPolicyApplications: 1, menuBarItemInstallations: 1)
        )
    }

    func testStartInstallsOnlyOneMenuBarItemWhenCalledRepeatedly() {
        let system = AppShellSystemSpy()
        var hotkeyRuntimeStartCount = 0
        let coordinatorWithHotkeys = AppLifecycleCoordinator(
            system: system,
            startHotkeyRuntime: { hotkeyRuntimeStartCount += 1 }
        )

        coordinatorWithHotkeys.start()
        coordinatorWithHotkeys.start()
        coordinatorWithHotkeys.applicationDidFinishLaunching()
        coordinatorWithHotkeys.applicationDidFinishLaunching()

        XCTAssertEqual(
            system.state,
            AppShellSystemState(accessoryPolicyApplications: 1, menuBarItemInstallations: 1)
        )
        XCTAssertEqual(hotkeyRuntimeStartCount, 1)
    }

    func testEachApplicationActivationRefreshesAccessibilityPermission() {
        let system = AppShellSystemSpy()
        var refreshCount = 0
        let coordinator = AppLifecycleCoordinator(
            system: system,
            refreshAccessibilityPermission: { refreshCount += 1 }
        )

        coordinator.applicationDidBecomeActive()
        coordinator.applicationDidBecomeActive()

        XCTAssertEqual(refreshCount, 2)
    }

    func testMenuControllerRoutesOpenSettingsThroughInjectedConfiguration() {
        var openSettingsCount = 0
        let controller = makeMenuController(
            openSettings: { openSettingsCount += 1 }
        )

        controller.openSettings(nil)

        XCTAssertEqual(openSettingsCount, 1)
    }

    func testMenuControllerRefreshesPauseTitleAndActionFromCurrentState() {
        var isPaused = false
        var toggleCount = 0
        let controller = makeMenuController(
            toggleSuperModePaused: {
                toggleCount += 1
                isPaused.toggle()
            },
            isSuperModePaused: { isPaused }
        )

        XCTAssertEqual(
            controller.currentState(),
            AppShellMenuState(
                statusTitle: "Super Mode: Active — Accessibility: Granted",
                pauseTitle: "Pause Super Mode",
                isPaused: false,
                isPauseEnabled: true
            )
        )

        controller.toggleSuperModePaused(nil)

        XCTAssertEqual(toggleCount, 1)
        XCTAssertEqual(
            controller.currentState(),
            AppShellMenuState(
                statusTitle: "Super Mode: Paused — Accessibility: Granted",
                pauseTitle: "Resume Super Mode",
                isPaused: true,
                isPauseEnabled: true
            )
        )

        controller.toggleSuperModePaused(nil)

        XCTAssertEqual(toggleCount, 2)
        XCTAssertEqual(
            controller.currentState(),
            AppShellMenuState(
                statusTitle: "Super Mode: Active — Accessibility: Granted",
                pauseTitle: "Pause Super Mode",
                isPaused: false,
                isPauseEnabled: true
            )
        )
    }

    func testMenuControllerRefreshesRuntimeAndPermissionStatus() {
        var runtimeStatus = AppShellSuperModeStatus.starting
        var permissionStatus = AccessibilityPermissionState.notRequested
        let controller = makeMenuController(
            superModeStatus: { runtimeStatus },
            accessibilityPermissionStatus: { permissionStatus }
        )

        XCTAssertEqual(
            controller.currentState(),
            AppShellMenuState(
                statusTitle: "Super Mode: Starting — Accessibility: Not Requested",
                pauseTitle: "Pause Super Mode",
                isPaused: false,
                isPauseEnabled: false
            )
        )

        runtimeStatus = .unavailable
        permissionStatus = .revoked

        XCTAssertEqual(
            controller.currentState(),
            AppShellMenuState(
                statusTitle: "Super Mode: Unavailable — Accessibility: Revoked",
                pauseTitle: "Pause Super Mode",
                isPaused: false,
                isPauseEnabled: false
            )
        )
    }

    func testMenuControllerRoutesSystemSettingsAndQuitWithoutGlobalApplicationActions() {
        var openSystemSettingsCount = 0
        var quitCount = 0
        let controller = makeMenuController(
            openSystemSettings: { openSystemSettingsCount += 1 },
            quit: { quitCount += 1 }
        )

        controller.openSystemSettings(nil)
        controller.quit(nil)

        XCTAssertEqual(openSystemSettingsCount, 1)
        XCTAssertEqual(quitCount, 1)
    }

    func testMenuControllerPlansQuickActionsFromCurrentFocusedWindowState() {
        var focusedWindow = FocusedWindowQuickActionState.active
        let controller = makeMenuController(
            focusedWindowQuickActionState: { focusedWindow },
            quickActionRegistry: ActionRegistry(actions: [
                .init(
                    id: .leftHalf,
                    title: "Left Half",
                    symbolName: "rectangle.lefthalf.filled",
                    availability: .available
                ),
            ])
        )

        XCTAssertEqual(controller.currentQuickActions().map(\.isEnabled), [true])

        focusedWindow = .noFocusedEligibleWindow

        XCTAssertEqual(controller.currentQuickActions().map(\.isEnabled), [false])
        XCTAssertEqual(
            controller.currentQuickActions().first?.disabledReason,
            SettingsCopy.noFocusedEligibleWindow
        )
    }

    func testMenuControllerDispatchesSelectedQuickActionThroughInjectedBoundary() {
        var performedActions: [ActionID] = []
        let controller = makeMenuController(
            performQuickAction: { performedActions.append($0) }
        )

        controller.performQuickAction(.rightHalf)

        XCTAssertEqual(performedActions, [.rightHalf])
    }

    func testMenuControllerPublishesQuickActionsOnlyAfterAsyncRefreshCompletes() {
        var pendingCompletion: (@MainActor () -> Void)?
        var published = false
        let controller = AppShellMenuController(
            configuration: AppShellMenuConfiguration(
                openSettings: {},
                toggleSuperModePaused: {},
                isSuperModePaused: { false },
                superModeStatus: { .active },
                accessibilityPermissionStatus: { .granted },
                refreshQuickActionState: { completion in
                    pendingCompletion = completion
                },
                openSystemSettings: {},
                quit: {}
            )
        )

        controller.refreshQuickActionState { published = true }

        XCTAssertFalse(published)
        pendingCompletion?()
        XCTAssertTrue(published)
    }

    private func makeMenuController(
        openSettings: @escaping @MainActor () -> Void = {},
        toggleSuperModePaused: @escaping @MainActor () -> Void = {},
        isSuperModePaused: @escaping @MainActor () -> Bool = { false },
        superModeStatus: @escaping @MainActor () -> AppShellSuperModeStatus = { .active },
        accessibilityPermissionStatus: @escaping @MainActor () -> AccessibilityPermissionState = {
            .granted
        },
        focusedWindowQuickActionState: @escaping @MainActor () -> FocusedWindowQuickActionState = {
            .active
        },
        quickActionRegistry: ActionRegistry = .builtIn,
        performQuickAction: @escaping @MainActor (ActionID) -> Void = { _ in },
        openSystemSettings: @escaping @MainActor () -> Void = {},
        quit: @escaping @MainActor () -> Void = {}
    ) -> AppShellMenuController {
        AppShellMenuController(
            configuration: AppShellMenuConfiguration(
                openSettings: openSettings,
                toggleSuperModePaused: toggleSuperModePaused,
                isSuperModePaused: isSuperModePaused,
                superModeStatus: superModeStatus,
                accessibilityPermissionStatus: accessibilityPermissionStatus,
                focusedWindowQuickActionState: focusedWindowQuickActionState,
                quickActionRegistry: quickActionRegistry,
                performQuickAction: performQuickAction,
                openSystemSettings: openSystemSettings,
                quit: quit
            )
        )
    }
}

@MainActor
private final class AppShellSystemSpy: AppShellSystem {
    private(set) var state = AppShellSystemState()

    func applyAccessoryActivationPolicy() {
        state.accessoryPolicyApplications += 1
    }

    func installMenuBarItem() {
        state.menuBarItemInstallations += 1
    }
}

private struct AppShellSystemState: Equatable {
    var accessoryPolicyApplications = 0
    var menuBarItemInstallations = 0
}

@MainActor
private func menuContainsRawNumericLabel(_ menu: NSMenu) -> Bool {
    menu.items.contains { item in
        item.title.range(of: #"\b[0-9]+\b"#, options: .regularExpression) != nil
            || item.submenu.map(menuContainsRawNumericLabel) == true
    }
}
