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
    private let systemTilingModel: SystemTilingCoexistenceModel
    private let edgeSnapCoordinator: EdgeSnapCoordinator
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
        var settingsRuntimeRef: ProductionSettingsRuntime?
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
            apply: { [weak superModeComposition] configuration in
                guard let superModeComposition else {
                    return .rejected(.invalidTimeout(milliseconds: configuration.timeoutMilliseconds))
                }
                let result = await superModeComposition.apply(configuration)
                if case .applied = result {
                    let current = await superModeComposition.currentSettings()
                    settingsRuntimeRef?.replaceHotkeySettings(current)
                }
                return result
            },
            suspendHotkeys: { [weak hotkeyManager] in
                _ = await hotkeyManager?.reconcile([])
            },
            resumeHotkeys: { [weak hotkeyManager, weak settingsStore] in
                guard let hotkeyManager, let settingsStore else { return }
                if case let .loaded(settings, _) = await settingsStore.load() {
                    _ = await hotkeyManager.reconcile(settings.bindings)
                }
            }
        )
        let globalHotkeySettingsRelay = GlobalHotkeySettingsRelay()
        let systemTilingModel = SystemTilingCoexistenceModel()
        self.systemTilingModel = systemTilingModel
        let settingsRuntime = ProductionSettingsRuntime(
            store: settingsStore,
            appRules: appRuleRuntime,
            profileLayouts: profileLayouts,
            actionRegistry: actionRegistry,
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
            },
            systemTilingStatus: { [systemTilingModel] in
                systemTilingModel.status
            }
        )
        settingsRuntimeRef = settingsRuntime
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
            },
            suspendHotkeys: { [weak hotkeyManager] in
                _ = await hotkeyManager?.reconcile([])
            },
            resumeHotkeys: { [weak hotkeyManager, weak settingsStore] in
                guard let hotkeyManager, let settingsStore else { return }
                if case let .loaded(settings, _) = await settingsStore.load() {
                    _ = await hotkeyManager.reconcile(settings.bindings)
                }
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

        let edgeSnapTargetResolver = EdgeSnapTargetResolver(
            sampler: MacOSWindowServerSampler(),
            accessibility: SystemWindowAdapter.shared,
            appRules: appRuleRuntime
        )
        let edgeSnapStateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        self.edgeSnapCoordinator = EdgeSnapCoordinator(
            overlayPresenter: overlay,
            stateMachine: edgeSnapStateMachine,
            windowSampler: MacOSWindowServerSampler(),
            targetResolver: edgeSnapTargetResolver,
            topologyObserving: topologyObserver,
            systemTilingStateProvider: { [systemTilingModel] in
                systemTilingModel.state
            },
            zoneConfigurationProvider: { [settingsRuntime] in
                settingsRuntime.currentEdgeSnapConfiguration()
            },
            isEnabledProvider: { [settingsRuntime] in
                settingsRuntime.currentSettings().snapping.isEnabled
            }
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
        let coordinator = edgeSnapCoordinator
        Task {
            await coordinator.start()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.applicationDidFinishLaunching()
        onboardingController.presentIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        lifecycleCoordinator.applicationDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleCoordinator.applicationWillTerminate()
        let coordinator = edgeSnapCoordinator
        Task {
            await coordinator.stop()
        }
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
    private let actionRegistry: ActionRegistry
    private let keyLabelResolver: any HotkeyKeyLabelResolving
    private let hotkeyPresenter: any HotkeyChordPresenting
    private let accessibilityPermissionStatus: () -> AccessibilityPermissionState
    private let inputMonitoringAccess: () -> Bool
    private let eventTapStatus: () -> EventTapDiagnosticsStatus
    private let appStatus: () -> AppDiagnosticsStatus
    private let openSystemSettingsAction: () -> Void
    private let openGlobalHotkeySettings: () -> Void
    private let openSuperModeSettings: () -> Void
    private let applyImportedHotkeys: @Sendable (HotkeySettings) async -> Bool
    private let setLaunchAtLoginAction: @MainActor (Bool) -> Bool
    private let systemTilingStatus: (@MainActor @Sendable () -> SystemTilingCoexistenceStatus)?
    private var configuration = ConfigurationSnapshot(
        hotkeySettings: HotkeySettings(bindings: []),
        layouts: [],
        displayProfiles: []
    )
    private var persistenceTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    /// Counts runtime state changes. A `start()` load that began before a change completed must
    /// not assign its now-stale snapshot over the newer state.
    private var settingsChangeGeneration = 0
    /// Counts whole-document writes. A write superseded by a newer one (or by an import) must
    /// not land after it and resurrect stale values.
    private var documentWriteGeneration = 0
    private var transfer = SettingsTransferPresentation()
    private var layoutValidationMessages: [String: String] = [:]

    init(
        store: SettingsStore,
        appRules: AppRuleRuntime,
        profileLayouts: DisplayProfileLayoutRuntime,
        actionRegistry: ActionRegistry = .builtIn,
        keyLabelResolver: (any HotkeyKeyLabelResolving)? = nil,
        accessibilityPermissionStatus: @escaping () -> AccessibilityPermissionState,
        inputMonitoringAccess: @escaping () -> Bool,
        eventTapStatus: @escaping () -> EventTapDiagnosticsStatus = { .stopped },
        appStatus: @escaping () -> AppDiagnosticsStatus = { .starting },
        openSystemSettings: @escaping () -> Void,
        openGlobalHotkeySettings: @escaping () -> Void,
        openSuperModeSettings: @escaping () -> Void,
        applyImportedHotkeys: @escaping @Sendable (HotkeySettings) async -> Bool = { _ in true },
        setLaunchAtLogin: @escaping @MainActor (Bool) -> Bool = { _ in true },
        systemTilingStatus: (@MainActor @Sendable () -> SystemTilingCoexistenceStatus)? = nil
    ) {
        self.store = store
        self.appRules = appRules
        self.profileLayouts = profileLayouts
        self.actionRegistry = actionRegistry
        let resolver = keyLabelResolver ?? MacOSHotkeyKeyLabelResolver()
        self.keyLabelResolver = resolver
        self.hotkeyPresenter = HotkeyChordPresenter(labelResolver: resolver)
        self.accessibilityPermissionStatus = accessibilityPermissionStatus
        self.inputMonitoringAccess = inputMonitoringAccess
        self.eventTapStatus = eventTapStatus
        self.appStatus = appStatus
        openSystemSettingsAction = openSystemSettings
        self.openGlobalHotkeySettings = openGlobalHotkeySettings
        self.openSuperModeSettings = openSuperModeSettings
        self.applyImportedHotkeys = applyImportedHotkeys
        setLaunchAtLoginAction = setLaunchAtLogin
        self.systemTilingStatus = systemTilingStatus
    }

    deinit {
        persistenceTask?.cancel()
        loadTask?.cancel()
    }

    /// Loads the complete schema-v3 document before replacing runtime policy.
    /// Repeated starts are harmless and the latest completed load wins.
    ///
    /// The load runs on its own task so a pending write is never cancelled by a start, and a
    /// load that began before a user change is discarded rather than reverting newer state.
    func start() {
        loadTask?.cancel()
        let generation = settingsChangeGeneration
        // Let any in-flight write land first, so this load cannot read a document that is one
        // change behind the runtime's in-memory state.
        let pendingWrite = persistenceTask
        loadTask = Task { [weak self, store, appRules, profileLayouts] in
            _ = await pendingWrite?.value
            let result = await store.loadConfiguration()
            guard !Task.isCancelled else { return }
            // A user change completed after this load began, so the state that change produced
            // is newer than the document this load read. Discard the whole result instead of
            // reverting the runtime or the shared app-rule/profile policy to it.
            guard let self, self.settingsChangeGeneration == generation else { return }
            switch result {
            case let .loaded(snapshot, _):
                await appRules.replace(with: snapshot.appRulePolicy)
                try? await profileLayouts.replaceProfiles(snapshot.displayProfiles)
                guard !Task.isCancelled else { return }
                self.configuration = snapshot
            }
        }
    }

    func currentSettings() -> SettingsRuntimeSnapshot {
        let edgeSnapDiagnostics: EdgeSnapDiagnosticsStatus
        if !configuration.snapping.isEnabled {
            edgeSnapDiagnostics = .disabled
        } else if let status = systemTilingStatus?(), case .stoodDown = status {
            edgeSnapDiagnostics = .stoodDownSystemTiling
        } else {
            edgeSnapDiagnostics = .active
        }

        return SettingsRuntimeSnapshot(
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
            hotkeys: {
                let resolver = keyLabelResolver
                let presenter = hotkeyPresenter
                let registry = actionRegistry
                let superMode = configuration.hotkeySettings.superModeConfiguration
                let prefixPresentation = presenter.present(superMode.prefix).settingsPresentation.visibleLabel
                let commandTree = superMode.commandBindings.map { binding in
                    let keyLabels = binding.hardwareKeyCodes.map { code in
                        Self.keyLabel(for: code, resolver: resolver)
                    }
                    let sequenceText = keyLabels.joined(separator: ", ")
                    let title = Self.actionTitle(for: binding.actionID, registry: registry)
                    let symbol = Self.actionSymbol(for: binding.actionID, registry: registry)
                    return SettingsCommandTreeItem(
                        keySequence: sequenceText,
                        actionTitle: title,
                        isAvailable: true,
                        symbolName: symbol,
                        keys: keyLabels
                    )
                }
                let globalHotkeys = configuration.hotkeySettings.bindings.map { binding in
                    let chord = HotkeyChord(hardwareKeyCode: binding.hardwareKeyCode, modifiers: binding.modifiers)
                    let presentation = presenter.present(chord).settingsPresentation
                    let title = Self.actionTitle(for: binding.actionID, registry: registry)
                    let symbol = Self.actionSymbol(for: binding.actionID, registry: registry)
                    return SettingsCommandTreeItem(
                        keySequence: presentation.visibleLabel,
                        actionTitle: title,
                        isAvailable: true,
                        symbolName: symbol,
                        keys: [presentation.visibleLabel]
                    )
                }
                return SettingsHotkeysSnapshot(
                    editor: .superMode,
                    recorder: inputMonitoringAccess() ? .ready : .unavailable,
                    validationMessage: nil,
                    commandTree: commandTree,
                    prefixPresentation: prefixPresentation,
                    globalHotkeys: globalHotkeys
                )
            }(),
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
                app: appStatus(),
                edgeSnap: edgeSnapDiagnostics
            ),
            edgeSnap: configuration.edgeSnap
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
        case let .updateEdgeSnapZoneConfiguration(snapshot):
            replaceConfiguration(general: general, snapping: snapping, edgeSnap: snapshot)
            return
        }
        // This change only touches general/snapping policy; layouts and display profiles keep
        // whatever the runtime (or the document) already holds.
        let baseline = configuration
        configuration = ConfigurationSnapshot(
            general: general,
            snapping: snapping,
            hotkeySettings: configuration.hotkeySettings,
            layouts: configuration.layouts,
            displayProfiles: configuration.displayProfiles,
            appRulePolicy: configuration.appRulePolicy,
            edgeSnap: configuration.edgeSnap
        )
        persist(configuration, baseline: baseline)
    }

    private func replaceConfiguration(
        general: GeneralSettings,
        snapping: SnappingSettings,
        layouts: [LayoutDraft]? = nil,
        displayProfiles: [DisplayProfile]? = nil,
        appRulePolicy: AppRulePolicy? = nil,
        edgeSnap: EdgeSnapZoneConfigurationSnapshot? = nil
    ) {
        let baseline = configuration
        configuration = ConfigurationSnapshot(
            general: general,
            snapping: snapping,
            hotkeySettings: configuration.hotkeySettings,
            layouts: layouts ?? configuration.layouts,
            displayProfiles: displayProfiles ?? configuration.displayProfiles,
            appRulePolicy: appRulePolicy ?? configuration.appRulePolicy,
            edgeSnap: edgeSnap ?? configuration.edgeSnap
        )
        persist(configuration, baseline: baseline)
    }

    /// Persists `snapshot` (the post-change configuration), taking untouched sections from the
    /// document instead of from possibly-empty in-memory state.
    ///
    /// - Parameter baseline: the configuration this change was built on, captured before the
    ///   mutation. A section the change did not touch still equals `baseline` and must come from
    ///   the document; a section that differs from `baseline` was edited by this change and wins.
    private func persist(_ snapshot: ConfigurationSnapshot, baseline: ConfigurationSnapshot) {
        markNewerSettingsState()
        let settingsGeneration = settingsChangeGeneration
        documentWriteGeneration &+= 1
        let writeGeneration = documentWriteGeneration
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self, store, profileLayouts] in
            // The document is authoritative for sections this change did not touch: global
            // hotkeys, layouts and display profiles. Their in-memory copies can be stale or
            // still empty when a change races the initial load; writing them verbatim would
            // erase live hotkeys (while the runtime keeps firing the old registrations from
            // memory) or wipe persisted layouts and profiles. Only the values this change
            // actually modified are taken from the snapshot.
            for attempt in 0..<2 {
                let persisted = await Self.persistedSections(store)
                guard !Task.isCancelled, let self else { return }
                // A newer write or an import owns the document now; this snapshot is stale.
                guard self.documentWriteGeneration == writeGeneration else { return }
                // A section this change did not touch is taken from the document. A section the
                // change did touch, or one edited again after this snapshot was built, keeps
                // the newer in-memory value.
                let hotkeySettings = self.configuration.hotkeySettings == snapshot.hotkeySettings
                    ? persisted.hotkeySettings
                    : self.configuration.hotkeySettings
                let layouts = Self.persistedOrCurrent(
                    baseline: baseline.layouts,
                    current: self.configuration.layouts,
                    persisted: persisted.layouts
                )
                let displayProfiles = Self.persistedOrCurrent(
                    baseline: baseline.displayProfiles,
                    current: self.configuration.displayProfiles,
                    persisted: persisted.displayProfiles
                )
                let merged = ConfigurationSnapshot(
                    general: snapshot.general,
                    snapping: snapshot.snapping,
                    hotkeySettings: hotkeySettings,
                    layouts: layouts,
                    displayProfiles: displayProfiles,
                    appRulePolicy: snapshot.appRulePolicy,
                    edgeSnap: snapshot.edgeSnap
                )
                guard case .saved = await store.saveConfiguration(merged) else { return }
                guard !Task.isCancelled else { return }
                // A hotkey replacement landed while this save was in flight, so the document
                // now holds the value this attempt read. Rewrite it once with the newer value
                // rather than leaving the user's hotkeys overwritten on disk. (Layout and
                // profile edits always start a newer write, so they are caught above.)
                if attempt == 0,
                   self.configuration.hotkeySettings != merged.hotkeySettings,
                   self.documentWriteGeneration == writeGeneration {
                    continue
                }
                // Keep the in-memory presentation in step with what was written, so the
                // Settings GUI (which reads currentSettings()) and the document agree.
                guard self.settingsChangeGeneration == settingsGeneration else { return }
                self.configuration = ConfigurationSnapshot(
                    general: self.configuration.general,
                    snapping: self.configuration.snapping,
                    hotkeySettings: merged.hotkeySettings,
                    layouts: merged.layouts,
                    displayProfiles: merged.displayProfiles,
                    appRulePolicy: self.configuration.appRulePolicy,
                    edgeSnap: self.configuration.edgeSnap
                )
                try? await profileLayouts.replaceProfiles(merged.displayProfiles)
                return
            }
        }
    }

    /// Records that runtime state changed, so any load or write that began earlier is stale.
    private func markNewerSettingsState() {
        settingsChangeGeneration &+= 1
    }

    /// Picks a section's value for the document write.
    ///
    /// The document is authoritative for a section this change did not touch (`current` still
    /// equals the pre-change `baseline`), which is what stops a routine change that races the
    /// initial load from writing an empty in-memory list. A newer in-memory edit (`current` no
    /// longer equals `baseline`) wins, so an in-flight layout/profile/hotkey save is not
    /// reverted by an older write landing after it.
    nonisolated private static func persistedOrCurrent<T: Equatable>(
        baseline: T,
        current: T,
        persisted: T
    ) -> T {
        current == baseline ? persisted : current
    }

    /// Reads the sections the document is authoritative for (hotkeys, layouts, display
    /// profiles) in a single load, so a whole-document write never erases what it did not edit.
    nonisolated private static func persistedSections(_ store: SettingsStore) async -> ConfigurationSnapshot {
        switch await store.loadConfiguration() {
        case let .loaded(snapshot, _):
            snapshot
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
        markNewerSettingsState()
        configuration = ConfigurationSnapshot(
            general: configuration.general,
            snapping: configuration.snapping,
            hotkeySettings: settings,
            layouts: configuration.layouts,
            displayProfiles: configuration.displayProfiles,
            appRulePolicy: configuration.appRulePolicy,
            edgeSnap: configuration.edgeSnap
        )
    }

    func currentEdgeSnapConfiguration() -> EdgeSnapZoneConfiguration {
        configuration.edgeSnap.toZoneConfiguration()
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
        // An import rewrites the whole document on purpose; invalidate any earlier load/write.
        markNewerSettingsState()
        documentWriteGeneration &+= 1
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

    static func actionTitle(for actionID: ActionID, registry: ActionRegistry) -> String {
        if let action = registry.action(for: actionID) {
            return action.title
        }
        switch actionID {
        case .openSettings:
            return String(localized: "Open Settings")
        case .toggleGaps:
            return String(localized: "Toggle Gaps")
        case .selectProfile:
            return String(localized: "Select Profile")
        default:
            return actionID.rawValue
        }
    }

    static func actionSymbol(for actionID: ActionID, registry: ActionRegistry) -> String? {
        if let action = registry.action(for: actionID) {
            return action.symbolName
        }
        switch actionID {
        case .openSettings:
            return "gearshape"
        case .toggleGaps:
            return "square.split.2x1"
        case .selectProfile:
            return "display.2"
        default:
            return nil
        }
    }

    static func keyLabel(for hardwareKeyCode: UInt16, resolver: any HotkeyKeyLabelResolving) -> String {
        if let label = resolver.label(for: hardwareKeyCode) {
            return label
        }
        if let fallback = fallbackAnsiKeyLabel(for: hardwareKeyCode) {
            return fallback
        }
        return String(format: "Key %d", hardwareKeyCode)
    }

    static func fallbackAnsiKeyLabel(for hardwareKeyCode: UInt16) -> String? {
        switch hardwareKeyCode {
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x16: return "6"
        case 0x17: return "5"
        case 0x18: return "="
        case 0x19: return "9"
        case 0x1A: return "7"
        case 0x1B: return "-"
        case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x1E: return "]"
        case 0x1F: return "O"
        case 0x20: return "U"
        case 0x21: return "["
        case 0x22: return "I"
        case 0x23: return "P"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x27: return "'"
        case 0x28: return "K"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2D: return "N"
        case 0x2E: return "M"
        case 0x2F: return "."
        case 0x32: return "`"
        default: return nil
        }
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
        app: AppDiagnosticsStatus,
        edgeSnap: EdgeSnapDiagnosticsStatus? = nil
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
            app: app,
            edgeSnap: edgeSnap
        )
        return SettingsDiagnosticsPresentation(status: status, report: DiagnosticsReportBuilder().makeReport(from: status).text)
    }
}
