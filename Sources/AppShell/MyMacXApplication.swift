import AppKit
import ServiceManagement

@main
@MainActor
enum MyMacXApplication {
    private static let applicationDelegate = ApplicationDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = applicationDelegate
        application.run()
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let permissionManager: AccessibilityPermissionManager
    private let hotkeyRuntime: HotkeyRuntimeCoordinator
    private let lifecycleCoordinator: AppLifecycleCoordinator
    private let crossDisplayComposition: CrossDisplayDragComposition
    private let superModeComposition: SuperModeProductionComposition
    private let settingsWindowController: SettingsShellWindowController
    private let superModeSettingsWindowController: SuperModeSettingsWindowController
    private let globalHotkeySettingsWindowController: GlobalHotkeySettingsWindowController
    private let quickActionWindowState: MenuQuickActionWindowState
    private let onboardingController: FirstLaunchOnboardingController

    override init() {
        let permissionManager = AccessibilityPermissionManager()
        let actionRegistry = ActionRegistry.builtIn
        let performance = ProductionPerformanceInstrumentation(
            system: ProcessPerformanceSystemSampler(observers: { 3 })
        )
        let appRuleRuntime = AppRuleRuntime()
        let profileLayouts = try! DisplayProfileLayoutRuntime(stableDisplays: CoreGraphicsStableDisplayAdapter())
        let windowActions = WindowActionEngine(appRules: appRuleRuntime, profileLayouts: profileLayouts)
        let menuQuickActionDispatcher = MenuQuickActionDispatcher(windowActions: windowActions)
        let hotkeyManager = GlobalHotkeyManager(system: MacOSGlobalHotkeySystem())
        let settingsURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("My Mac X", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
        let settingsStore = SettingsStore(
            documents: LocalSettingsDocumentAdapter(documentURL: settingsURL),
            actionRegistry: actionRegistry
        )
        let hotkeyBindingUpdater = HotkeyRuntimeBindingUpdater(store: settingsStore, manager: hotkeyManager)
        let hotkeyRuntime = HotkeyRuntimeCoordinator(
            manager: hotkeyManager,
            bindingUpdater: hotkeyBindingUpdater,
            dispatcher: HotkeyActionDispatcher(windowActions: windowActions)
        )
        let superModeRuntime = SuperModeRuntimeConfiguration()
        let superModeConfiguration = SuperModeConfigurationModule(
            store: settingsStore,
            runtime: superModeRuntime,
            validator: SuperModeConfigurationValidator(actionRegistry: actionRegistry)
        )
        let inputMonitoringAuthorizer = MacOSInputMonitoringAuthorizer()
        let openSettingsRelay = OpenSettingsRelay()
        let overlay = OverlayCoordinator()
        let chooserKeyboardInput = LayoutChooserKeyboardInputAdapter()
        overlay.installKeyboardInputAdapter(chooserKeyboardInput)
        let superModeComposition = SuperModeProductionComposition(
            configuration: superModeConfiguration,
            runtime: superModeRuntime,
            actionRegistry: actionRegistry,
            windowActions: windowActions,
            chooserKeyboardInput: chooserKeyboardInput,
            appActionPerformer: SuperModeAppActionAdapter(
                openSettings: { openSettingsRelay.present() },
                toggleGaps: { await profileLayouts.toggleGaps(); return true },
                selectProfile: { openSettingsRelay.present(section: .displays); return true }
            )
        )
        let topologyObserver = DisplayTopologyObserver()
        let triggerEngine = try! TriggerDwellEngine(
            configuration: TriggerDwellConfiguration(
                dwellDuration: .milliseconds(150)
            )
        )
        let superModeSettingsWindowController = SuperModeSettingsWindowController(
            actionRegistry: actionRegistry,
            hasInputMonitoringAccess: {
                inputMonitoringAuthorizer.hasAccess()
            },
            requestInputMonitoringAccess: {
                inputMonitoringAuthorizer.requestAccess()
            },
            retrySuperModeRuntime: {
                superModeComposition.start()
            },
            load: {
                await superModeComposition.currentSettings()
            },
            apply: { configuration in
                await superModeComposition.apply(configuration)
            }
        )
        let globalHotkeySettingsRelay = GlobalHotkeySettingsRelay()
        let settingsRuntime = ProductionSettingsRuntime(
            store: settingsStore,
            appRules: appRuleRuntime,
            profileLayouts: profileLayouts,
            accessibilityPermissionStatus: { permissionManager.state },
            inputMonitoringAccess: { inputMonitoringAuthorizer.hasAccess() },
            eventTapStatus: { superModeComposition.diagnosticsEventTapStatus },
            appStatus: { superModeComposition.diagnosticsAppStatus },
            openSystemSettings: {
                permissionManager.recordUserWasDirectedToGrantPermission()
                permissionManager.openSystemSettings()
            },
            openGlobalHotkeySettings: {
                globalHotkeySettingsRelay.present()
            },
            openSuperModeSettings: {
                superModeSettingsWindowController.present()
            },
            applyImportedHotkeys: { settings in
                guard case .applied = await hotkeyBindingUpdater.applyValidated(settings) else {
                    return false
                }
                guard case .applied = await superModeConfiguration.apply(
                    settings.superModeConfiguration,
                    hotkeyBindings: settings.bindings
                ) else {
                    return false
                }
                return true
            },
            setLaunchAtLogin: { enabled in
                ProductionSettingsRuntime.setLaunchAtLogin(enabled)
            }
        )
        let globalHotkeySettingsWindowController = GlobalHotkeySettingsWindowController(
            actionRegistry: actionRegistry,
            load: {
                switch await settingsStore.load() {
                case let .loaded(settings, _): settings
                }
            },
            apply: { settings in
                let result = await hotkeyBindingUpdater.applyValidated(settings)
                if case .applied = result { settingsRuntime.replaceHotkeySettings(settings) }
                return result
            }
        )
        globalHotkeySettingsRelay.controller = globalHotkeySettingsWindowController
        let settingsWindowController = SettingsShellWindowController(runtime: settingsRuntime)
        openSettingsRelay.controller = settingsWindowController
        self.permissionManager = permissionManager
        self.hotkeyRuntime = hotkeyRuntime
        self.superModeComposition = superModeComposition
        self.settingsWindowController = settingsWindowController
        self.superModeSettingsWindowController = superModeSettingsWindowController
        self.globalHotkeySettingsWindowController = globalHotkeySettingsWindowController
        self.onboardingController = FirstLaunchOnboardingController(
            permissionState: { permissionManager.state },
            openAccessibilitySettings: {
                permissionManager.recordUserWasDirectedToGrantPermission()
                permissionManager.openSystemSettings()
            },
            openAppSettings: { settingsWindowController.present() }
        )
        let quickActionWindowState = MenuQuickActionWindowState()
        self.quickActionWindowState = quickActionWindowState
        self.crossDisplayComposition = CrossDisplayDragComposition(
            overlay: overlay,
            topologyObserving: topologyObserver,
            triggerEngine: triggerEngine,
            windowActions: windowActions,
            snappingSettings: ProductionSnappingRuntimeSettingsAdapter {
                let settings = settingsRuntime.currentSettings().snapping
                return SnappingRuntimeSettings(
                    isEnabled: settings.isEnabled,
                    trigger: settings.trigger == .notch ? .notch : .topCenter,
                    dwellMilliseconds: settings.dwellMilliseconds,
                    showsPlacementPreview: settings.showsPlacementPreview,
                    usesReducedEffects: settings.usesReducedEffects
                )
            },
            performance: performance
        )
        lifecycleCoordinator = AppLifecycleCoordinator(
            system: AppKitAppShellSystem(
                configuration: AppShellMenuConfiguration(
                    openSettings: {
                        settingsWindowController.present()
                    },
                    toggleSuperModePaused: {
                        superModeComposition.togglePaused()
                    },
                    isSuperModePaused: {
                        superModeComposition.isPaused
                    },
                    superModeStatus: {
                        superModeComposition.status
                    },
                    accessibilityPermissionStatus: {
                        permissionManager.state
                    },
                    focusedWindowQuickActionState: {
                        quickActionWindowState.state
                    },
                    quickActionRegistry: actionRegistry,
                    performQuickAction: { actionID in
                        let receivedAt = performance.eventTimestamp()
                        quickActionWindowState.performIfEligible(actionID) {
                            performance.recordEventToActionStart(eventReceivedAt: receivedAt)
                            _ = await menuQuickActionDispatcher.perform(actionID)
                            performance.recordCompletedAction()
                        }
                    },
                    refreshQuickActionState: { completion in
                        quickActionWindowState.refresh(completion: completion)
                    },
                    openSystemSettings: {
                        permissionManager.recordUserWasDirectedToGrantPermission()
                        permissionManager.openSystemSettings()
                    },
                    quit: {
                        NSApplication.shared.terminate(nil)
                    }
                )
            ),
            refreshAccessibilityPermission: {
                _ = permissionManager.refresh()
                superModeSettingsWindowController.refreshInputMonitoringState()
                settingsWindowController.modelForTesting.reload()
                quickActionWindowState.refresh()
                superModeComposition.start()
            },
            startHotkeyRuntime: {
                settingsRuntime.start()
                hotkeyRuntime.start()
            },
            startSuperModeRuntime: {
                superModeComposition.start()
            },
            stopSuperModeRuntime: {
                superModeComposition.stop()
            }
        )
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        onboardingController.presentIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        lifecycleCoordinator.applicationDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleCoordinator.applicationWillTerminate()
    }
}

@MainActor
private final class FirstLaunchOnboardingController {
    private static let explanationSeenKey = "onboarding.accessibilityExplanationSeen.v1"

    private let defaults: UserDefaults
    private let permissionState: () -> AccessibilityPermissionState
    private let openAccessibilitySettings: () -> Void
    private let openAppSettings: () -> Void

    init(
        defaults: UserDefaults = .standard,
        permissionState: @escaping () -> AccessibilityPermissionState,
        openAccessibilitySettings: @escaping () -> Void,
        openAppSettings: @escaping () -> Void
    ) {
        self.defaults = defaults
        self.permissionState = permissionState
        self.openAccessibilitySettings = openAccessibilitySettings
        self.openAppSettings = openAppSettings
    }

    func presentIfNeeded() {
        guard FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: defaults.bool(forKey: Self.explanationSeenKey),
            permissionState: permissionState()
        ) else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        alert.messageText = String(localized: "Welcome to My Mac X")
        alert.informativeText = String(localized: "My Mac X needs Accessibility permission to move and resize windows. It does not read what you type, window titles, clipboard contents, or screenshots. You can review this before enabling it.")
        alert.addButton(withTitle: String(localized: "Open Accessibility Settings"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.addButton(withTitle: String(localized: "Review App Settings"))
        defaults.set(true, forKey: Self.explanationSeenKey)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openAccessibilitySettings()
        case .alertThirdButtonReturn:
            openAppSettings()
        default:
            break
        }
    }
}

@MainActor
private final class SuperModeProductionComposition {
    private let configuration: SuperModeConfigurationModule
    private let runtime: SuperModeRuntimeConfiguration
    private let actionRegistry: ActionRegistry
    private let dispatcher: SuperModeAdvancedActionDispatcher
    private let hud: SuperHUDCoordinator
    private let chooserKeyboardInput: LayoutChooserKeyboardInputAdapter
    private let transitionContinuation:
        AsyncStream<SuperModeInputSafetyTransition>.Continuation
    private var transitionTask: Task<Void, Never>?
    private var inputSafety: SuperModeInputSafetyController?
    private var eventTap: EventTapManager?
    private var startupTask: Task<Void, Never>?
    private var currentHotkeySettings: HotkeySettings?
    private var latestRuntimeSnapshot: SuperModeRuntimeSnapshot?
    private var desiredEnabled = true
    private(set) var status = AppShellSuperModeStatus.starting

    var diagnosticsEventTapStatus: EventTapDiagnosticsStatus {
        switch status {
        case .starting: .stopped
        case .active: .active
        case .unavailable: .unavailable
        }
    }

    var diagnosticsAppStatus: AppDiagnosticsStatus {
        switch status {
        case .starting: .starting
        case .active: .ready
        case .unavailable: .limited
        }
    }

    var isPaused: Bool {
        !desiredEnabled
    }

    init(
        configuration: SuperModeConfigurationModule,
        runtime: SuperModeRuntimeConfiguration,
        actionRegistry: ActionRegistry,
        windowActions: any WindowActionPerforming,
        chooserKeyboardInput: LayoutChooserKeyboardInputAdapter,
        appActionPerformer: any SuperModeAppActionPerforming
    ) {
        let transitionChannel = AsyncStream<SuperModeInputSafetyTransition>.makeStream()
        self.configuration = configuration
        self.runtime = runtime
        self.actionRegistry = actionRegistry
        self.chooserKeyboardInput = chooserKeyboardInput
        transitionContinuation = transitionChannel.continuation
        dispatcher = SuperModeAdvancedActionDispatcher(
            actionRegistry: actionRegistry,
            windowActions: windowActions,
            appActionPerformer: appActionPerformer
        )
        hud = SuperHUDCoordinator()
        transitionTask = Task { [weak self, stream = transitionChannel.stream] in
            for await transition in stream {
                guard let self else { return }
                await receive(transition)
            }
        }
    }

    func start() {
        guard startupTask == nil, eventTap == nil else { return }

        status = .starting
        startupTask = Task { [weak self] in
            guard let self else { return }

            let startResult = await configuration.start()
            guard !Task.isCancelled else { return }
            guard case let .active(settings, _, snapshot) = startResult else {
                status = .unavailable
                startupTask = nil
                return
            }

            record(settings: settings, snapshot: snapshot)
            let transitionContinuation = self.transitionContinuation
            let inputSafety = SuperModeInputSafetyController(
                snapshot: latestRuntimeSnapshot ?? snapshot,
                scheduler: DispatchSuperModeTimeoutScheduler(),
                onTransition: { transition in
                    transitionContinuation.yield(transition)
                }
            )
            inputSafety.setEnabled(desiredEnabled)
            let eventTap = EventTapManager(
                system: MacOSEventTapSystem(),
                handler: { [chooserKeyboardInput] signal in
                    if chooserKeyboardInput.isAcceptingInput {
                        return chooserKeyboardInput.handle(signal)
                    }
                    return inputSafety.handle(signal)
                }
            )
            self.inputSafety = inputSafety
            self.eventTap = eventTap

            guard await eventTap.start() == .active, !Task.isCancelled else {
                inputSafety.stop()
                await eventTap.stop()
                self.inputSafety = nil
                self.eventTap = nil
                self.status = .unavailable
                self.startupTask = nil
                return
            }

            status = .active
            startupTask = nil
        }
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        inputSafety?.stop()
        inputSafety = nil
        let eventTap = eventTap
        self.eventTap = nil
        status = .unavailable
        hud.dismiss(.explicit)
        Task {
            await eventTap?.stop()
        }
    }

    func currentSettings() async -> HotkeySettings {
        if let startupTask {
            await startupTask.value
        }

        let result = await configuration.currentSettings()
        switch result {
        case let .loaded(settings, _):
            currentHotkeySettings = settings
            return settings
        }
    }

    func apply(
        _ desiredConfiguration: SuperModeConfiguration
    ) async -> SuperModeConfigurationApplyResult {
        if let startupTask {
            await startupTask.value
        }
        let settingsForApply: HotkeySettings
        if let currentHotkeySettings {
            settingsForApply = currentHotkeySettings
        } else {
            settingsForApply = await currentSettings()
        }
        let result = await configuration.apply(
            desiredConfiguration,
            hotkeyBindings: settingsForApply.bindings
        )
        guard case let .applied(settings, runtimeSnapshot) = result else {
            return result
        }

        guard record(settings: settings, snapshot: runtimeSnapshot) else {
            return result
        }
        inputSafety?.update(snapshot: runtimeSnapshot)
        if inputSafety == nil, startupTask == nil {
            start()
        }
        return result
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        desiredEnabled = !paused
        inputSafety?.setEnabled(desiredEnabled)
    }

    @discardableResult
    private func record(
        settings: HotkeySettings,
        snapshot: SuperModeRuntimeSnapshot
    ) -> Bool {
        guard (latestRuntimeSnapshot?.revision.rawValue ?? 0)
            <= snapshot.revision.rawValue else {
            return false
        }
        currentHotkeySettings = settings
        latestRuntimeSnapshot = snapshot
        return true
    }

    private func receive(_ inputSafetyTransition: SuperModeInputSafetyTransition) async {
        let transition = inputSafetyTransition.transition
        guard await runtime.freshness(of: inputSafetyTransition.revision) == .current else {
            return
        }

        switch transition.outcome {
        case .armed:
            guard case let .armed(sessionID) = transition.current,
                  await runtime.activate(
                      SuperModeRuntimeSession(
                          revision: inputSafetyTransition.revision,
                          sessionID: sessionID
                      )
                  ) == .current
            else { return }
            present(transition)

        case .submenuEntered:
            guard let sessionID = Self.session(from: transition.current),
                  await isCurrent(sessionID, revision: inputSafetyTransition.revision)
            else { return }
            present(transition)

        case let .execute(actionID):
            guard let sessionID = Self.session(from: transition.previous),
                  await isCurrent(sessionID, revision: inputSafetyTransition.revision)
            else { return }
            present(transition, actionID: actionID)
            let result = await dispatcher.dispatch(actionID)
            hud.present(
                dispatchResult: Self.hudResult(from: result),
                session: sessionID
            )

        case .cancelled:
            guard let sessionID = Self.session(from: transition.previous),
                  await isCurrent(sessionID, revision: inputSafetyTransition.revision)
            else { return }
            present(transition)

        case .none:
            break
        }
    }

    private func isCurrent(
        _ sessionID: SuperModeSessionID,
        revision: SuperModeConfigurationRevision
    ) async -> Bool {
        await runtime.freshness(
            of: SuperModeRuntimeSession(revision: revision, sessionID: sessionID)
        ) == .current
    }

    private func present(_ transition: SuperModeTransition, actionID: ActionID? = nil) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let workspace = NSWorkspace.shared
        hud.updateAccessibilityPreferences(.init(
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        ))

        let size = CGSize(width: 360, height: 104)
        let visibleFrame = screen.visibleFrame
        let frame = CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 48,
            width: size.width,
            height: size.height
        )
        hud.present(
            transition: transition,
            presentation: SuperHUDPresentation(
                panelFrame: frame,
                actionTitle: actionID.flatMap { actionRegistry.action(for: $0)?.title }
            )
        )
    }

    private static func session(
        from state: SuperModePresentationState
    ) -> SuperModeSessionID? {
        switch state {
        case let .armed(session), let .submenu(session, _):
            session
        case .idle:
            nil
        }
    }

    private static func hudResult(
        from result: SuperModeAdvancedDispatchResult
    ) -> SuperModeDispatchResult {
        switch result {
        case let .dispatched(windowResult):
            .dispatched(windowResult)
        case .dispatchedAppAction:
            .dispatchedAppAction
        case let .unavailable(.windowAction(reason)):
            .unavailable(.action(reason))
        case .unavailable(.notRegistered),
             .unavailable(.productionAdapterUnavailable):
            .unavailable(.notRegistered)
        }
    }
}

@MainActor
private final class OpenSettingsRelay {
    weak var controller: SettingsShellWindowController?

    func present() {
        controller?.present()
    }

    func present(section: SettingsSection) {
        controller?.select(section)
        controller?.present()
    }
}

@MainActor
private final class GlobalHotkeySettingsRelay {
    weak var controller: GlobalHotkeySettingsWindowController?
    func present() { controller?.present() }
}

@MainActor
private final class MenuQuickActionWindowState {
    private(set) var state = FocusedWindowQuickActionState.noFocusedEligibleWindow
    private var refreshTask: Task<Void, Never>?

    func refresh(completion: (@MainActor () -> Void)? = nil) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let capture = await SystemWindowAdapter.shared.captureFocusedWindow()
            guard !Task.isCancelled, let self else { return }
            state = Self.map(capture)
            completion?()
        }
    }

    /// Re-captures immediately before dispatch so a stale menu cannot retarget
    /// an action after focus or eligibility changed.
    func performIfEligible(
        _ actionID: ActionID,
        perform: @escaping @Sendable () async -> Void
    ) {
        Task {
            let capture = await SystemWindowAdapter.shared.captureFocusedWindow()
            let state = Self.map(capture)
            guard state.allows(actionID) else { return }
            await perform()
        }
    }

    private static func map(
        _ capture: AccessibilityWindowCapture
    ) -> FocusedWindowQuickActionState {
        switch capture {
        case let .candidate(candidate):
            return MenuQuickActionPlanner().focusedWindowState(capabilities: candidate.capabilities)
        case .unsupported:
            return .unsupportedFocusedWindow
        case .failure(.noEligibleWindow):
            return .noFocusedEligibleWindow
        case .failure:
            return .unsupportedFocusedWindow
        }
    }
}

@MainActor
final class ProductionSettingsRuntime: SettingsRuntimeProviding {
    private let store: SettingsStore
    private let appRules: AppRuleRuntime
    private let profileLayouts: DisplayProfileLayoutRuntime
    private let accessibilityPermissionStatus: () -> AccessibilityPermissionState
    private let inputMonitoringAccess: () -> Bool
    private let eventTapStatus: () -> EventTapDiagnosticsStatus
    private let appStatus: () -> AppDiagnosticsStatus
    private let openSystemSettingsAction: () -> Void
    private let openGlobalHotkeySettings: () -> Void
    private let openSuperModeSettings: () -> Void
    private let applyImportedHotkeys: @Sendable (HotkeySettings) async -> Bool
    private let setLaunchAtLoginAction: @MainActor (Bool) -> Bool
    private var configuration = ConfigurationSnapshot(
        hotkeySettings: HotkeySettings(bindings: []),
        layouts: [],
        displayProfiles: []
    )
    private var persistenceTask: Task<Void, Never>?
    private var transfer = SettingsTransferPresentation()
    private var layoutValidationMessages: [String: String] = [:]

    init(
        store: SettingsStore,
        appRules: AppRuleRuntime,
        profileLayouts: DisplayProfileLayoutRuntime,
        accessibilityPermissionStatus: @escaping () -> AccessibilityPermissionState,
        inputMonitoringAccess: @escaping () -> Bool,
        eventTapStatus: @escaping () -> EventTapDiagnosticsStatus = { .stopped },
        appStatus: @escaping () -> AppDiagnosticsStatus = { .starting },
        openSystemSettings: @escaping () -> Void,
        openGlobalHotkeySettings: @escaping () -> Void,
        openSuperModeSettings: @escaping () -> Void,
        applyImportedHotkeys: @escaping @Sendable (HotkeySettings) async -> Bool = { _ in true },
        setLaunchAtLogin: @escaping @MainActor (Bool) -> Bool = { _ in true }
    ) {
        self.store = store
        self.appRules = appRules
        self.profileLayouts = profileLayouts
        self.accessibilityPermissionStatus = accessibilityPermissionStatus
        self.inputMonitoringAccess = inputMonitoringAccess
        self.eventTapStatus = eventTapStatus
        self.appStatus = appStatus
        openSystemSettingsAction = openSystemSettings
        self.openGlobalHotkeySettings = openGlobalHotkeySettings
        self.openSuperModeSettings = openSuperModeSettings
        self.applyImportedHotkeys = applyImportedHotkeys
        setLaunchAtLoginAction = setLaunchAtLogin
    }

    deinit {
        persistenceTask?.cancel()
    }

    /// Loads the complete schema-v3 document before replacing runtime policy.
    /// Repeated starts are harmless and the latest completed load wins.
    func start() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self, store, appRules, profileLayouts] in
            let result = await store.loadConfiguration()
            guard !Task.isCancelled else { return }
            switch result {
            case let .loaded(snapshot, _):
                await appRules.replace(with: snapshot.appRulePolicy)
                try? await profileLayouts.replaceProfiles(snapshot.displayProfiles)
                guard !Task.isCancelled else { return }
                self?.configuration = snapshot
            }
        }
    }

    func currentSettings() -> SettingsRuntimeSnapshot {
        SettingsRuntimeSnapshot(
            general: SettingsGeneralSnapshot(
                accessibility: accessibilityPermissionStatus(),
                inputMonitoringGranted: inputMonitoringAccess(),
                launchesAtLogin: configuration.general.launchesAtLogin
            ),
            snapping: SettingsSnappingSnapshot(
                isEnabled: configuration.snapping.isEnabled,
                trigger: configuration.snapping.trigger == .notch ? .notch : .topCenter,
                triggerAvailability: .available,
                dwellMilliseconds: configuration.snapping.dwellMilliseconds,
                showsPlacementPreview: configuration.snapping.showsPlacementPreview,
                usesReducedEffects: configuration.snapping.usesReducedEffects
            ),
            hotkeys: SettingsHotkeysSnapshot(
                editor: .superMode,
                recorder: inputMonitoringAccess() ? .ready : .unavailable,
                validationMessage: nil,
                commandTree: configuration.hotkeySettings.superModeConfiguration.commandBindings.map {
                    SettingsCommandTreeItem(
                        keySequence: $0.hardwareKeyCodes.map(String.init).joined(separator: " "),
                        actionTitle: $0.actionID.rawValue,
                        isAvailable: true
                    )
                }
            ),
            layouts: configuration.layouts.map {
                SettingsLayoutPresentation(
                    draft: Self.presentation($0),
                    validationMessage: layoutValidationMessages[$0.id]
                )
            },
            displayProfiles: configuration.displayProfiles.map {
                SettingsDisplayProfilePresentation(
                    draft: SettingsDisplayProfileDraft(
                        stableDisplayID: $0.stableDisplayID.rawValue,
                        gap: $0.gap,
                        layoutIDs: $0.layoutIDs
                    ),
                    isConnected: Self.connectedStableDisplayIDs.contains($0.stableDisplayID)
                )
            },
            appRules: SettingsAppRulesPresentation(
                defaultDecision: configuration.appRulePolicy.unmatched,
                rules: configuration.appRulePolicy.rules
            ),
            transfer: transfer,
            diagnostics: Self.diagnostics(
                accessibility: accessibilityPermissionStatus(),
                inputMonitoring: inputMonitoringAccess(),
                eventTap: eventTapStatus(),
                app: appStatus()
            )
        )
    }

    func apply(_ change: SettingsRuntimeChange) {
        var general = configuration.general
        var snapping = configuration.snapping
        switch change {
        case let .launchAtLoginEnabled(isEnabled):
            guard Self.setLaunchAtLogin(isEnabled) else { return }
            general.launchesAtLogin = isEnabled
        case let .snappingEnabled(isEnabled):
            snapping.isEnabled = isEnabled
        case let .snappingTrigger(trigger):
            snapping.trigger = trigger == .notch ? .notch : .topCenter
        case let .snappingDwellMilliseconds(milliseconds):
            snapping.dwellMilliseconds = milliseconds
        case let .placementPreviewEnabled(isEnabled):
            snapping.showsPlacementPreview = isEnabled
        case let .reducedEffectsEnabled(isEnabled):
            snapping.usesReducedEffects = isEnabled
        case let .saveLayout(draft):
            guard let validated = Self.validatedLayout(draft) else {
                layoutValidationMessages[draft.id] = "Layout regions must stay within bounds and cannot overlap."
                return
            }
            layoutValidationMessages[draft.id] = nil
            var layouts = configuration.layouts.filter { $0.id != validated.id }
            layouts.append(validated)
            replaceConfiguration(general: general, snapping: snapping, layouts: layouts)
            return
        case let .editLayout(id, edit):
            guard let current = configuration.layouts.first(where: { $0.id == id }) else { return }
            let domainEdit: LayoutEdit
            switch edit {
            case let .split(regionID, direction, firstFraction, firstRegionID, secondRegionID):
                domainEdit = .split(
                    regionID: LayoutRegionID(rawValue: regionID),
                    direction: direction == .columns ? .columns : .rows,
                    firstFraction: firstFraction,
                    firstRegionID: LayoutRegionID(rawValue: firstRegionID),
                    secondRegionID: LayoutRegionID(rawValue: secondRegionID)
                )
            case let .merge(regionIDs, mergedRegionID):
                domainEdit = .merge(
                    regionIDs: regionIDs.map { LayoutRegionID(rawValue: $0) },
                    mergedRegionID: LayoutRegionID(rawValue: mergedRegionID)
                )
            }
            switch LayoutEditor().apply(domainEdit, to: current) {
            case let .success(edited):
                layoutValidationMessages[id] = nil
                var layouts = configuration.layouts.filter { $0.id != id }
                layouts.append(edited)
                replaceConfiguration(general: general, snapping: snapping, layouts: layouts)
            case .failure:
                layoutValidationMessages[id] = "This split or merge would create an invalid Layout."
            }
            return
        case let .deleteLayout(id):
            guard !configuration.displayProfiles.contains(where: { $0.layoutIDs.contains(id) }) else { return }
            replaceConfiguration(
                general: general,
                snapping: snapping,
                layouts: configuration.layouts.filter { $0.id != id }
            )
            return
        case let .saveDisplayProfile(draft):
            let availableLayoutIDs = Set(configuration.layouts.map(\.id)).union([Layout.builtIn.id])
            guard let profile = Self.validatedProfile(draft),
                  Set(profile.layoutIDs).isSubset(of: availableLayoutIDs) else { return }
            var profiles = configuration.displayProfiles.filter { $0.stableDisplayID != profile.stableDisplayID }
            profiles.append(profile)
            replaceConfiguration(general: general, snapping: snapping, displayProfiles: profiles)
            Task { [profileLayouts] in try? await profileLayouts.replaceProfiles(profiles) }
            return
        case .createDisplayProfilesForConnectedDisplays:
            let existing = Set(configuration.displayProfiles.map(\.stableDisplayID))
            let additions = Self.connectedStableDisplayIDs
                .filter { !existing.contains($0) }
                .compactMap {
                    try? DisplayProfile(
                        stableDisplayID: $0,
                        gap: 0,
                        layoutIDs: [Layout.builtIn.id]
                    )
                }
            guard !additions.isEmpty else { return }
            let profiles = configuration.displayProfiles + additions
            replaceConfiguration(
                general: general,
                snapping: snapping,
                displayProfiles: profiles
            )
            return
        case let .deleteDisplayProfile(stableDisplayID):
            replaceConfiguration(
                general: general,
                snapping: snapping,
                displayProfiles: configuration.displayProfiles.filter { $0.stableDisplayID.rawValue != stableDisplayID }
            )
            return
        case let .replaceAppRules(defaultDecision, rules):
            let policy = AppRulePolicy(unmatched: defaultDecision, rules: rules)
            replaceConfiguration(general: general, snapping: snapping, appRulePolicy: policy)
            Task { [appRules] in await appRules.replace(with: policy) }
            return
        }
        configuration = ConfigurationSnapshot(
            general: general,
            snapping: snapping,
            hotkeySettings: configuration.hotkeySettings,
            layouts: configuration.layouts,
            displayProfiles: configuration.displayProfiles,
            appRulePolicy: configuration.appRulePolicy
        )
        persist(configuration)
    }

    private func replaceConfiguration(
        general: GeneralSettings,
        snapping: SnappingSettings,
        layouts: [LayoutDraft]? = nil,
        displayProfiles: [DisplayProfile]? = nil,
        appRulePolicy: AppRulePolicy? = nil
    ) {
        configuration = ConfigurationSnapshot(
            general: general,
            snapping: snapping,
            hotkeySettings: configuration.hotkeySettings,
            layouts: layouts ?? configuration.layouts,
            displayProfiles: displayProfiles ?? configuration.displayProfiles,
            appRulePolicy: appRulePolicy ?? configuration.appRulePolicy
        )
        persist(configuration)
    }

    private func persist(_ snapshot: ConfigurationSnapshot) {
        persistenceTask?.cancel()
        persistenceTask = Task { [store, profileLayouts] in
            _ = await store.saveConfiguration(snapshot)
            try? await profileLayouts.replaceProfiles(snapshot.displayProfiles)
        }
    }

    func openSystemSettings() {
        openSystemSettingsAction()
    }

    func openHotkeyEditor(_ editor: SettingsHotkeyEditor) {
        switch editor {
        case .hotkeys: openGlobalHotkeySettings()
        case .superMode: openSuperModeSettings()
        }
    }

    func replaceHotkeySettings(_ settings: HotkeySettings) {
        configuration = ConfigurationSnapshot(
            general: configuration.general,
            snapping: configuration.snapping,
            hotkeySettings: settings,
            layouts: configuration.layouts,
            displayProfiles: configuration.displayProfiles,
            appRulePolicy: configuration.appRulePolicy
        )
    }

    func importConfiguration(completion: @escaping @MainActor () -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                completion()
                return
            }
            do {
                let data = try Data(contentsOf: url)
                switch ConfigurationArchive(actionRegistry: .builtIn).import(data) {
                case let .imported(snapshot, _):
                    restoreImported(snapshot, completion: completion)
                case .rejected:
                    transfer = SettingsTransferPresentation(statusMessage: "Configuration could not be imported.", isError: true)
                    completion()
                }
            } catch {
                transfer = SettingsTransferPresentation(statusMessage: "Configuration could not be read.", isError: true)
                completion()
            }
        }
    }

    func restoreImported(
        _ snapshot: ConfigurationSnapshot,
        completion: @escaping @MainActor () -> Void
    ) {
        persistenceTask?.cancel()
        let previous = configuration
        persistenceTask = Task { [weak self, store, appRules, profileLayouts, applyImportedHotkeys, setLaunchAtLoginAction] in
            guard let self else { return }
            let launchAtLoginChanged = previous.general.launchesAtLogin
                != snapshot.general.launchesAtLogin
            guard (!launchAtLoginChanged || setLaunchAtLoginAction(snapshot.general.launchesAtLogin)),
                  await applyImportedHotkeys(snapshot.hotkeySettings),
                  case .saved = await store.saveConfiguration(snapshot) else {
                if launchAtLoginChanged {
                    _ = setLaunchAtLoginAction(previous.general.launchesAtLogin)
                }
                _ = await applyImportedHotkeys(previous.hotkeySettings)
                _ = await store.saveConfiguration(previous)
                guard !Task.isCancelled else { return }
                transfer = SettingsTransferPresentation(
                    statusMessage: "Configuration could not be applied.",
                    isError: true
                )
                completion()
                return
            }
            await appRules.replace(with: snapshot.appRulePolicy)
            try? await profileLayouts.replaceProfiles(snapshot.displayProfiles)
            guard !Task.isCancelled else { return }
            configuration = snapshot
            transfer = SettingsTransferPresentation(statusMessage: "Configuration imported.")
            completion()
        }
    }

    func exportConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "My Mac X Configuration.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let data = try ConfigurationArchive(actionRegistry: .builtIn).export(configuration)
                try data.write(to: url, options: .atomic)
                transfer = SettingsTransferPresentation(statusMessage: "Configuration exported.")
            } catch {
                transfer = SettingsTransferPresentation(statusMessage: "Configuration could not be exported.", isError: true)
            }
        }
    }

    func copyDiagnosticsReport() {
        let report = currentSettings().diagnostics.report
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    private static func presentation(_ draft: LayoutDraft) -> SettingsLayoutDraft {
        SettingsLayoutDraft(
            id: draft.id,
            name: draft.name,
            regions: draft.regions.map {
                SettingsLayoutRegionDraft(id: $0.id.rawValue, normalizedFrame: $0.normalizedFrame)
            }
        )
    }

    private static func validatedLayout(_ draft: SettingsLayoutDraft) -> LayoutDraft? {
        let candidate = LayoutDraft(
            id: draft.id,
            name: draft.name,
            regions: draft.regions.map {
                LayoutRegionDraft(id: LayoutRegionID(rawValue: $0.id), normalizedFrame: $0.normalizedFrame)
            }
        )
        var library = LayoutLibrary()
        guard case .success = library.save(candidate) else { return nil }
        return candidate
    }

    private static func validatedProfile(_ draft: SettingsDisplayProfileDraft) -> DisplayProfile? {
        guard let stableID = try? StableDisplayID(rawValue: draft.stableDisplayID) else { return nil }
        return try? DisplayProfile(stableDisplayID: stableID, gap: draft.gap, layoutIDs: draft.layoutIDs)
    }

    private static var connectedStableDisplayIDs: Set<StableDisplayID> {
        Set(NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
            else { return nil }
            return try? StableDisplayID(rawValue: CFUUIDCreateString(nil, uuid) as String)
        })
    }

    static func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }

    private static func diagnostics(
        accessibility: AccessibilityPermissionState,
        inputMonitoring: Bool,
        eventTap: EventTapDiagnosticsStatus,
        app: AppDiagnosticsStatus
    ) -> SettingsDiagnosticsPresentation {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let info = Bundle.main.infoDictionary ?? [:]
        let versionParts = (info["CFBundleShortVersionString"] as? String ?? "0.0.0")
            .split(separator: ".").compactMap { UInt($0) }
        let status = DiagnosticsStatusSnapshot(
            accessibility: accessibility == .granted ? .granted : (accessibility == .notRequested ? .notRequested : .denied),
            inputMonitoring: inputMonitoring ? .granted : .denied,
            eventTap: eventTap,
            operatingSystem: DiagnosticsVersion(major: UInt(os.majorVersion), minor: UInt(os.minorVersion), patch: UInt(os.patchVersion)),
            appVersion: DiagnosticsVersion(major: versionParts.first ?? 0, minor: versionParts.dropFirst().first ?? 0, patch: versionParts.dropFirst(2).first ?? 0),
            appBuild: UInt(info["CFBundleVersion"] as? String ?? "0") ?? 0,
            app: app
        )
        return SettingsDiagnosticsPresentation(status: status, report: DiagnosticsReportBuilder().makeReport(from: status).text)
    }
}
