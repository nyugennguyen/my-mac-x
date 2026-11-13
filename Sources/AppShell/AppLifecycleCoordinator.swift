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

enum FirstLaunchOnboardingPolicy {
    static func shouldPresent(
        hasSeenExplanation: Bool,
        permissionState: AccessibilityPermissionState
    ) -> Bool {
        !hasSeenExplanation && permissionState != .granted
    }
}

@MainActor
protocol AppShellSystem: AnyObject {
    func applyAccessoryActivationPolicy()
    func installMenuBarItem()
}

@MainActor
final class AppLifecycleCoordinator {
    private let system: AppShellSystem
    private let refreshAccessibilityPermission: @MainActor () -> Void
    private let startHotkeyRuntime: @MainActor () -> Void
    private let startSuperModeRuntime: @MainActor () -> Void
    private let stopSuperModeRuntime: @MainActor () -> Void
    private var hasStarted = false
    private var hasFinishedLaunching = false

    init(
        system: AppShellSystem,
        refreshAccessibilityPermission: @escaping @MainActor () -> Void = {},
        startHotkeyRuntime: @escaping @MainActor () -> Void = {},
        startSuperModeRuntime: @escaping @MainActor () -> Void = {},
        stopSuperModeRuntime: @escaping @MainActor () -> Void = {}
    ) {
        self.system = system
        self.refreshAccessibilityPermission = refreshAccessibilityPermission
        self.startHotkeyRuntime = startHotkeyRuntime
        self.startSuperModeRuntime = startSuperModeRuntime
        self.stopSuperModeRuntime = stopSuperModeRuntime
    }

    func start() {
        guard !hasStarted else { return }

        hasStarted = true
        system.applyAccessoryActivationPolicy()
        startHotkeyRuntime()
        startSuperModeRuntime()
    }

    /// Publishes AppKit scene-backed UI only after NSApplication has finished
    /// launching. Installing an NSStatusItem during will-finish can race Control
    /// Center's status-item scene registration on current macOS releases.
    func applicationDidFinishLaunching() {
        guard hasStarted, !hasFinishedLaunching else { return }
        hasFinishedLaunching = true
        system.installMenuBarItem()
    }

    func applicationDidBecomeActive() {
        refreshAccessibilityPermission()
    }

    func applicationWillTerminate() {
        guard hasStarted else { return }

        stopSuperModeRuntime()
        hasStarted = false
    }
}

enum AppShellSuperModeStatus: Equatable, Sendable {
    case starting
    case active
    case unavailable
}

@MainActor
struct AppShellMenuConfiguration {
    let openSettings: @MainActor () -> Void
    let toggleSuperModePaused: @MainActor () -> Void
    let isSuperModePaused: @MainActor () -> Bool
    let superModeStatus: @MainActor () -> AppShellSuperModeStatus
    let accessibilityPermissionStatus: @MainActor () -> AccessibilityPermissionState
    let focusedWindowQuickActionState: @MainActor () -> FocusedWindowQuickActionState
    let quickActionRegistry: ActionRegistry
    let performQuickAction: @MainActor (ActionID) -> Void
    let refreshQuickActionState: @MainActor (@escaping @MainActor () -> Void) -> Void
    let openSystemSettings: @MainActor () -> Void
    let quit: @MainActor () -> Void

    init(
        openSettings: @escaping @MainActor () -> Void,
        toggleSuperModePaused: @escaping @MainActor () -> Void,
        isSuperModePaused: @escaping @MainActor () -> Bool,
        superModeStatus: @escaping @MainActor () -> AppShellSuperModeStatus,
        accessibilityPermissionStatus: @escaping @MainActor () -> AccessibilityPermissionState,
        focusedWindowQuickActionState: @escaping @MainActor () -> FocusedWindowQuickActionState = {
            .noFocusedEligibleWindow
        },
        quickActionRegistry: ActionRegistry = .builtIn,
        performQuickAction: @escaping @MainActor (ActionID) -> Void = { _ in },
        refreshQuickActionState: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { completion in completion() },
        openSystemSettings: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        self.openSettings = openSettings
        self.toggleSuperModePaused = toggleSuperModePaused
        self.isSuperModePaused = isSuperModePaused
        self.superModeStatus = superModeStatus
        self.accessibilityPermissionStatus = accessibilityPermissionStatus
        self.focusedWindowQuickActionState = focusedWindowQuickActionState
        self.quickActionRegistry = quickActionRegistry
        self.performQuickAction = performQuickAction
        self.refreshQuickActionState = refreshQuickActionState
        self.openSystemSettings = openSystemSettings
        self.quit = quit
    }
}

struct AppShellMenuState: Equatable {
    let statusTitle: String
    let pauseTitle: String
    let isPaused: Bool
    let isPauseEnabled: Bool
}

@MainActor
final class AppShellMenuController: NSObject {
    private let configuration: AppShellMenuConfiguration

    init(configuration: AppShellMenuConfiguration) {
        self.configuration = configuration
    }

    func currentState() -> AppShellMenuState {
        let isPaused = configuration.isSuperModePaused()
        let superModeStatus = configuration.superModeStatus()
        let permissionStatus = configuration.accessibilityPermissionStatus()

        return AppShellMenuState(
            statusTitle: Self.statusTitle(
                superModeStatus: superModeStatus,
                isPaused: isPaused,
                permissionStatus: permissionStatus
            ),
            pauseTitle: isPaused ? String(localized: "Resume Super Mode") : String(localized: "Pause Super Mode"),
            isPaused: isPaused,
            isPauseEnabled: superModeStatus == .active
        )
    }

    func currentQuickActions() -> [MenuQuickActionItem] {
        MenuQuickActionPlanner().plan(
            focusedWindow: configuration.focusedWindowQuickActionState(),
            registry: configuration.quickActionRegistry
        )
    }

    func performQuickAction(_ actionID: ActionID) {
        configuration.performQuickAction(actionID)
    }

    func refreshQuickActionState(completion: @escaping @MainActor () -> Void) {
        configuration.refreshQuickActionState(completion)
    }

    @objc
    func openSettings(_ sender: Any?) {
        configuration.openSettings()
    }

    @objc
    func toggleSuperModePaused(_ sender: Any?) {
        configuration.toggleSuperModePaused()
    }

    @objc
    func openSystemSettings(_ sender: Any?) {
        configuration.openSystemSettings()
    }

    @objc
    func quit(_ sender: Any?) {
        configuration.quit()
    }

    private static func statusTitle(
        superModeStatus: AppShellSuperModeStatus,
        isPaused: Bool,
        permissionStatus: AccessibilityPermissionState
    ) -> String {
        let superModeDescription = switch superModeStatus {
        case .starting:
            String(localized: "Starting")
        case .active:
            isPaused ? String(localized: "Paused") : String(localized: "Active")
        case .unavailable:
            String(localized: "Unavailable")
        }
        let permissionDescription = switch permissionStatus {
        case .notRequested:
            String(localized: "Not Requested")
        case .denied:
            String(localized: "Denied")
        case .granted:
            String(localized: "Granted")
        case .revoked:
            String(localized: "Revoked")
        }

        return String(localized: "Super Mode: \(superModeDescription) — Accessibility: \(permissionDescription)")
    }
}

@MainActor
final class AppKitAppShellSystem: NSObject, AppShellSystem, NSMenuDelegate {
    struct StatusItemPresentation: Equatable {
        let length: CGFloat
        let symbolName: String
        let title: String
        let toolTip: String

        static let standard = StatusItemPresentation(
            length: 54,
            symbolName: "rectangle.split.2x2",
            title: "MX",
            toolTip: "My Mac X"
        )
    }

    private let application: NSApplication
    private let statusBar: NSStatusBar
    private let menuController: AppShellMenuController
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var pauseMenuItem: NSMenuItem?
    private let quickActionsMenuController: AppKitQuickActionsMenuController
    private var quickActionsMenuItem: NSMenuItem?

    convenience init(configuration: AppShellMenuConfiguration) {
        self.init(
            application: .shared,
            statusBar: .system,
            configuration: configuration
        )
    }

    init(
        application: NSApplication,
        statusBar: NSStatusBar,
        configuration: AppShellMenuConfiguration
    ) {
        self.application = application
        self.statusBar = statusBar
        menuController = AppShellMenuController(configuration: configuration)
        quickActionsMenuController = AppKitQuickActionsMenuController { actionID in
            configuration.performQuickAction(actionID)
        }
        super.init()
    }

    func applyAccessoryActivationPolicy() {
        application.setActivationPolicy(.accessory)
    }

    func installMenuBarItem() {
        guard statusItem == nil else { return }

        let presentation = StatusItemPresentation.standard
        // A fixed slot prevents AppKit from collapsing an image-only item during
        // accessory-app startup. The short monogram makes the app distinguishable
        // from other window-shaped menu-bar glyphs.
        let item = statusBar.statusItem(withLength: presentation.length)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: presentation.toolTip
        )?.withSymbolConfiguration(config) {
            image.isTemplate = true
            item.button?.image = image
            item.button?.imagePosition = .imageLeading
            item.button?.title = presentation.title
        } else {
            item.button?.title = presentation.title
        }
        item.button?.toolTip = presentation.toolTip
        item.button?.setAccessibilityLabel(presentation.toolTip)

        item.menu = makeMenu()
        item.isVisible = true
        statusItem = item
    }

    /// Exercises the production AppKit presentation without installing a persistent status item.
    func makeMenuForTesting() -> NSMenu {
        makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "My Mac X")
        menu.autoenablesItems = false
        menu.delegate = self

        let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let quickActionsMenuItem = NSMenuItem(
            title: SettingsCopy.quickActionsMenuTitle,
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(quickActionsMenuItem)
        menu.addItem(.separator())

        let settingsMenuItem = NSMenuItem(
            title: String(localized: "Open Settings…"),
            action: #selector(AppShellMenuController.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsMenuItem.target = menuController
        settingsMenuItem.keyEquivalentModifierMask = [.command]
        settingsMenuItem.isEnabled = true
        menu.addItem(settingsMenuItem)

        let pauseMenuItem = NSMenuItem(
            title: "",
            action: #selector(AppShellMenuController.toggleSuperModePaused(_:)),
            keyEquivalent: ""
        )
        pauseMenuItem.target = menuController
        menu.addItem(pauseMenuItem)

        let systemSettingsMenuItem = NSMenuItem(
            title: String(localized: "Open System Settings…"),
            action: #selector(AppShellMenuController.openSystemSettings(_:)),
            keyEquivalent: ""
        )
        systemSettingsMenuItem.target = menuController
        systemSettingsMenuItem.isEnabled = true
        menu.addItem(systemSettingsMenuItem)

        menu.addItem(.separator())

        let quitMenuItem = NSMenuItem(
            title: String(localized: "Quit My Mac X"),
            action: #selector(AppShellMenuController.quit(_:)),
            keyEquivalent: "q"
        )
        quitMenuItem.target = menuController
        quitMenuItem.keyEquivalentModifierMask = [.command]
        quitMenuItem.isEnabled = true
        menu.addItem(quitMenuItem)

        self.statusMenuItem = statusMenuItem
        self.pauseMenuItem = pauseMenuItem
        self.quickActionsMenuItem = quickActionsMenuItem
        refreshMenu()
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
        menuController.refreshQuickActionState { [weak self] in
            self?.refreshMenu()
        }
    }

    private func refreshMenu() {
        let state = menuController.currentState()
        statusMenuItem?.title = state.statusTitle
        statusMenuItem?.setAccessibilityLabel(state.statusTitle)
        pauseMenuItem?.title = state.pauseTitle
        pauseMenuItem?.state = state.isPaused ? .on : .off
        pauseMenuItem?.isEnabled = state.isPauseEnabled
        let pauseDisabledReason = state.isPauseEnabled
            ? nil
            : String(localized: "Super Mode is not currently available.")
        pauseMenuItem?.toolTip = pauseDisabledReason
        pauseMenuItem?.setAccessibilityHelp(pauseDisabledReason)
        quickActionsMenuItem?.submenu = quickActionsMenuController.makeMenu(
            items: menuController.currentQuickActions()
        )
    }
}
