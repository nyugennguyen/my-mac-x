import AppKit
import Combine
import SwiftUI

/// The state the menu needs to decide whether a Window Action can begin.
///
/// The production adapter owns Accessibility inspection. This value deliberately
/// contains no window identity, title, or process data so menu presentation does
/// not retain sensitive application information.
public enum FocusedWindowQuickActionState: Equatable, Sendable {
    case active
    case activeWithUnavailableActions([ActionID: String])
    case noFocusedEligibleWindow
    case unsupportedFocusedWindow
}

extension FocusedWindowQuickActionState {
    func allows(_ actionID: ActionID) -> Bool {
        switch self {
        case .active:
            true
        case let .activeWithUnavailableActions(unavailable):
            unavailable[actionID] == nil
        case .noFocusedEligibleWindow, .unsupportedFocusedWindow:
            false
        }
    }
}

public struct MenuQuickActionItem: Equatable, Identifiable, Sendable {
    public let actionID: ActionID
    public let title: String
    public let symbolName: String
    public let isEnabled: Bool
    public let disabledReason: String?

    public var id: ActionID { actionID }

    public init(
        actionID: ActionID,
        title: String,
        symbolName: String,
        isEnabled: Bool,
        disabledReason: String?
    ) {
        self.actionID = actionID
        self.title = title
        self.symbolName = symbolName
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

/// Pure menu presentation seam. A0 supplies the focused-window state and
/// dispatches selected actions through `WindowActionPerforming`.
public struct MenuQuickActionPlanner {
    public init() {}

    func focusedWindowState(capabilities: WindowCapabilities) -> FocusedWindowQuickActionState {
        guard capabilities.minimized != .active,
              capabilities.nativeFullScreen != .active,
              capabilities.isMovable || capabilities.isResizable
        else { return .unsupportedFocusedWindow }

        var unavailable: [ActionID: String] = [:]
        if !capabilities.isMovable {
            unavailable[.moveDisplayNext] = SettingsCopy.actionRequiresMovableWindow
            unavailable[.moveDisplayPrevious] = SettingsCopy.actionRequiresMovableWindow
        }
        if capabilities.nativeFullScreen == .unavailable {
            unavailable[.nativeFullScreen] = SettingsCopy.nativeFullScreenStateUnavailable
        }
        return unavailable.isEmpty ? .active : .activeWithUnavailableActions(unavailable)
    }

    public func plan(
        focusedWindow: FocusedWindowQuickActionState,
        registry: ActionRegistry
    ) -> [MenuQuickActionItem] {
        registry.actions.map { descriptor in
            let disabledReason = disabledReason(
                for: descriptor.id,
                for: descriptor.availability,
                focusedWindow: focusedWindow
            )
            return MenuQuickActionItem(
                actionID: descriptor.id,
                title: descriptor.title,
                symbolName: descriptor.symbolName,
                isEnabled: disabledReason == nil,
                disabledReason: disabledReason
            )
        }
    }

    private func disabledReason(
        for descriptorID: ActionID,
        for availability: ActionAvailability,
        focusedWindow: FocusedWindowQuickActionState
    ) -> String? {
        switch focusedWindow {
        case .noFocusedEligibleWindow:
            SettingsCopy.noFocusedEligibleWindow
        case .unsupportedFocusedWindow:
            SettingsCopy.unsupportedFocusedWindow
        case .active:
            switch availability {
            case .available:
                nil
            case let .unavailable(reason):
                SettingsCopy.unavailableAction(reason)
            }
        case let .activeWithUnavailableActions(unavailableActions):
            if let reason = unavailableActions[descriptorID] { reason }
            else {
                switch availability {
                case .available: nil
                case let .unavailable(reason): SettingsCopy.unavailableAction(reason)
                }
            }
        }
    }
}

/// Sends menu selection through the same Window Action Module used by every
/// other interaction surface, while preserving the source for diagnostics.
public struct MenuQuickActionDispatcher: Sendable {
    private let windowActions: any WindowActionPerforming

    public init(windowActions: any WindowActionPerforming) {
        self.windowActions = windowActions
    }

    @discardableResult
    public func perform(_ actionID: ActionID) async -> WindowActionResult {
        await windowActions.perform(.commit(action: actionID, source: .menuBar))
    }
}

/// An AppKit adapter that can be attached to the menu bar by the app composition.
/// It does not inspect Accessibility state or execute Window Actions itself.
@MainActor
public final class AppKitQuickActionsMenuController: NSObject {
    public typealias Dispatch = @MainActor (ActionID) -> Void

    private let dispatch: Dispatch
    private var actionsByMenuItem: [ObjectIdentifier: ActionID] = [:]

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
    }

    public func makeMenu(items: [MenuQuickActionItem]) -> NSMenu {
        actionsByMenuItem.removeAll()
        let menu = NSMenu(title: SettingsCopy.quickActionsMenuTitle)
        menu.autoenablesItems = false

        for item in items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(selectAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.image = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.title)
            menuItem.isEnabled = item.isEnabled
            menuItem.toolTip = item.disabledReason
            menuItem.setAccessibilityLabel(item.title)
            if let disabledReason = item.disabledReason {
                menuItem.setAccessibilityHelp(disabledReason)
            }
            actionsByMenuItem[ObjectIdentifier(menuItem)] = item.actionID
            menu.addItem(menuItem)
        }
        return menu
    }

    @objc
    private func selectAction(_ sender: NSMenuItem) {
        guard let actionID = actionsByMenuItem[ObjectIdentifier(sender)] else { return }
        dispatch(actionID)
    }
}

public enum SettingsSection: String, CaseIterable, Equatable, Identifiable, Sendable {
    case general
    case snapping
    case hotkeys
    case layouts
    case displays
    case appRules
    case transfer
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: SettingsCopy.generalSectionTitle
        case .snapping: SettingsCopy.snappingSectionTitle
        case .hotkeys: SettingsCopy.hotkeysSectionTitle
        case .layouts: SettingsCopy.layoutsSectionTitle
        case .displays: SettingsCopy.displaysSectionTitle
        case .appRules: SettingsCopy.appRulesSectionTitle
        case .transfer: SettingsCopy.transferSectionTitle
        case .about: SettingsCopy.aboutSectionTitle
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .snapping: "rectangle.3.group"
        case .hotkeys: "keyboard"
        case .layouts: "rectangle.split.3x1"
        case .displays: "display.2"
        case .appRules: "app.badge.checkmark"
        case .transfer: "square.and.arrow.up.on.square"
        case .about: "info.circle"
        }
    }
}

public struct SettingsLayoutRegionDraft: Equatable, Identifiable, Sendable {
    public let id: String
    public var normalizedFrame: CGRect

    public init(id: String, normalizedFrame: CGRect) {
        self.id = id
        self.normalizedFrame = normalizedFrame
    }
}

public struct SettingsLayoutDraft: Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var regions: [SettingsLayoutRegionDraft]

    public init(id: String, name: String, regions: [SettingsLayoutRegionDraft]) {
        self.id = id
        self.name = name
        self.regions = regions
    }
}

public struct SettingsLayoutPresentation: Equatable, Identifiable, Sendable {
    public let draft: SettingsLayoutDraft
    public let validationMessage: String?
    public var id: String { draft.id }

    public init(draft: SettingsLayoutDraft, validationMessage: String? = nil) {
        self.draft = draft
        self.validationMessage = validationMessage
    }
}

public enum SettingsLayoutSplitDirection: Equatable, Sendable { case columns, rows }

public enum SettingsLayoutEdit: Equatable, Sendable {
    case split(
        regionID: String,
        direction: SettingsLayoutSplitDirection,
        firstFraction: Double,
        firstRegionID: String,
        secondRegionID: String
    )
    case merge(regionIDs: [String], mergedRegionID: String)
}

public struct SettingsDisplayProfileDraft: Equatable, Identifiable, Sendable {
    public let stableDisplayID: String
    public var gap: Double
    public var layoutIDs: [String]
    public var id: String { stableDisplayID }

    public init(stableDisplayID: String, gap: Double, layoutIDs: [String]) {
        self.stableDisplayID = stableDisplayID
        self.gap = gap
        self.layoutIDs = layoutIDs
    }
}

public struct SettingsDisplayProfilePresentation: Equatable, Identifiable, Sendable {
    public let draft: SettingsDisplayProfileDraft
    public let isConnected: Bool
    public let validationMessage: String?
    public var id: String { draft.id }

    public init(draft: SettingsDisplayProfileDraft, isConnected: Bool, validationMessage: String? = nil) {
        self.draft = draft
        self.isConnected = isConnected
        self.validationMessage = validationMessage
    }
}

public struct SettingsAppRulesPresentation: Equatable, Sendable {
    public var defaultDecision: AppRuleDecision
    public var rules: [AppRule]
    public var validationMessage: String?

    public init(defaultDecision: AppRuleDecision = .included, rules: [AppRule] = [], validationMessage: String? = nil) {
        self.defaultDecision = defaultDecision
        self.rules = rules
        self.validationMessage = validationMessage
    }
}

public struct SettingsTransferPresentation: Equatable, Sendable {
    public let statusMessage: String?
    public let isError: Bool

    public init(statusMessage: String? = nil, isError: Bool = false) {
        self.statusMessage = statusMessage
        self.isError = isError
    }
}

public struct SettingsDiagnosticsPresentation: Equatable, Sendable {
    public let status: DiagnosticsStatusSnapshot
    public let report: String

    public init(status: DiagnosticsStatusSnapshot, report: String) {
        self.status = status
        self.report = report
    }

    public static let unavailable = Self(
        status: .init(
            accessibility: .notRequested,
            inputMonitoring: .notRequested,
            eventTap: .stopped,
            operatingSystem: .init(major: 0, minor: 0, patch: 0),
            appVersion: .init(major: 0, minor: 0, patch: 0),
            appBuild: 0,
            app: .starting
        ),
        report: ""
    )
}

public enum SettingsPermissionPresentation: Equatable, Sendable {
    case notRequested
    case denied
    case granted
    case revoked

    public init(_ state: AccessibilityPermissionState) {
        switch state {
        case .notRequested: self = .notRequested
        case .denied: self = .denied
        case .granted: self = .granted
        case .revoked: self = .revoked
        }
    }

    public var message: String {
        switch self {
        case .notRequested: SettingsCopy.accessibilityNotRequested
        case .denied: SettingsCopy.accessibilityDenied
        case .granted: SettingsCopy.accessibilityGranted
        case .revoked: SettingsCopy.accessibilityRevoked
        }
    }
}

public struct SettingsGeneralSnapshot: Equatable, Sendable {
    public var accessibility: AccessibilityPermissionState
    public var inputMonitoringGranted: Bool
    public var launchesAtLogin: Bool

    public init(
        accessibility: AccessibilityPermissionState,
        inputMonitoringGranted: Bool,
        launchesAtLogin: Bool
    ) {
        self.accessibility = accessibility
        self.inputMonitoringGranted = inputMonitoringGranted
        self.launchesAtLogin = launchesAtLogin
    }
}

public enum SnappingTrigger: String, CaseIterable, Equatable, Identifiable, Sendable {
    case notch
    case topCenter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notch: SettingsCopy.notchTrigger
        case .topCenter: SettingsCopy.topCenterTrigger
        }
    }
}

public enum SnappingTriggerAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

public struct SettingsSnappingSnapshot: Equatable, Sendable {
    public var isEnabled: Bool
    public var trigger: SnappingTrigger
    public var triggerAvailability: SnappingTriggerAvailability
    public var dwellMilliseconds: UInt32
    public var showsPlacementPreview: Bool
    public var usesReducedEffects: Bool

    public init(
        isEnabled: Bool,
        trigger: SnappingTrigger,
        triggerAvailability: SnappingTriggerAvailability,
        dwellMilliseconds: UInt32,
        showsPlacementPreview: Bool,
        usesReducedEffects: Bool
    ) {
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.triggerAvailability = triggerAvailability
        self.dwellMilliseconds = dwellMilliseconds
        self.showsPlacementPreview = showsPlacementPreview
        self.usesReducedEffects = usesReducedEffects
    }

    public static let `default` = Self(
        isEnabled: true,
        trigger: .notch,
        triggerAvailability: .available,
        dwellMilliseconds: 150,
        showsPlacementPreview: true,
        usesReducedEffects: false
    )
}

public enum SettingsHotkeyEditor: Equatable, Sendable {
    case hotkeys
    case superMode

    var title: String {
        switch self {
        case .hotkeys: SettingsCopy.editHotkeys
        case .superMode: SettingsCopy.editSuperMode
        }
    }
}

public enum SettingsShortcutRecorderState: Equatable, Sendable {
    case ready
    case recording
    case unavailable

    var accessibilityLabel: String {
        switch self {
        case .ready: SettingsCopy.recordShortcut
        case .recording: SettingsCopy.recordingShortcut
        case .unavailable: SettingsCopy.shortcutRecorderUnavailable
        }
    }
}

public struct SettingsCommandTreeItem: Equatable, Identifiable, Sendable {
    public let keySequence: String
    public let actionTitle: String
    public let isAvailable: Bool
    public let symbolName: String?
    public let keys: [String]

    public var id: String { "\(keySequence)-\(actionTitle)" }
    public var accessibilityLabel: String { "\(keySequence): \(actionTitle)" }

    public init(
        keySequence: String,
        actionTitle: String,
        isAvailable: Bool,
        symbolName: String? = nil,
        keys: [String] = []
    ) {
        self.keySequence = keySequence
        self.actionTitle = actionTitle
        self.isAvailable = isAvailable
        self.symbolName = symbolName
        self.keys = keys.isEmpty ? Self.parseKeys(from: keySequence) : keys
    }

    private static func parseKeys(from sequence: String) -> [String] {
        if sequence.contains(",") {
            return sequence.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else if sequence.contains(" ") {
            return sequence.split(separator: " ").map(String.init)
        } else if !sequence.isEmpty {
            return [sequence]
        }
        return []
    }
}

public struct SettingsHotkeysSnapshot: Equatable, Sendable {
    public var editor: SettingsHotkeyEditor
    public var recorder: SettingsShortcutRecorderState
    public var validationMessage: String?
    public var commandTree: [SettingsCommandTreeItem]
    public var prefixPresentation: String?
    public var globalHotkeys: [SettingsCommandTreeItem]

    public init(
        editor: SettingsHotkeyEditor,
        recorder: SettingsShortcutRecorderState,
        validationMessage: String? = nil,
        commandTree: [SettingsCommandTreeItem],
        prefixPresentation: String? = nil,
        globalHotkeys: [SettingsCommandTreeItem] = []
    ) {
        self.editor = editor
        self.recorder = recorder
        self.validationMessage = validationMessage
        self.commandTree = commandTree
        self.prefixPresentation = prefixPresentation
        self.globalHotkeys = globalHotkeys
    }

    public static let empty = Self(
        editor: .hotkeys,
        recorder: .ready,
        validationMessage: nil,
        commandTree: [],
        prefixPresentation: nil,
        globalHotkeys: []
    )

    public var recorderAccessibilityLabel: String { recorder.accessibilityLabel }
    public var commandTreeAccessibilityLabel: String {
        String(
            localized: "\(editor == .superMode ? "Super Mode" : "Hotkey") commands, \(commandTree.count) bindings.",
            comment: "VoiceOver summary of configured commands"
        )
    }
}

public struct SettingsRuntimeSnapshot: Equatable, Sendable {
    public var general: SettingsGeneralSnapshot
    public var snapping: SettingsSnappingSnapshot
    public var hotkeys: SettingsHotkeysSnapshot
    public var layouts: [SettingsLayoutPresentation]
    public var displayProfiles: [SettingsDisplayProfilePresentation]
    public var appRules: SettingsAppRulesPresentation
    public var transfer: SettingsTransferPresentation
    public var diagnostics: SettingsDiagnosticsPresentation
    public var edgeSnap: EdgeSnapZoneConfigurationSnapshot

    public init(
        general: SettingsGeneralSnapshot,
        snapping: SettingsSnappingSnapshot,
        hotkeys: SettingsHotkeysSnapshot,
        layouts: [SettingsLayoutPresentation] = [],
        displayProfiles: [SettingsDisplayProfilePresentation] = [],
        appRules: SettingsAppRulesPresentation = .init(),
        transfer: SettingsTransferPresentation = .init(),
        diagnostics: SettingsDiagnosticsPresentation = .unavailable,
        edgeSnap: EdgeSnapZoneConfigurationSnapshot = EdgeSnapZoneConfigurationSnapshot()
    ) {
        self.general = general
        self.snapping = snapping
        self.hotkeys = hotkeys
        self.layouts = layouts
        self.displayProfiles = displayProfiles
        self.appRules = appRules
        self.transfer = transfer
        self.diagnostics = diagnostics
        self.edgeSnap = edgeSnap
    }
}

public enum SettingsRuntimeChange: Equatable, Sendable {
    case launchAtLoginEnabled(Bool)
    case snappingEnabled(Bool)
    case snappingTrigger(SnappingTrigger)
    case snappingDwellMilliseconds(UInt32)
    case placementPreviewEnabled(Bool)
    case reducedEffectsEnabled(Bool)
    case saveLayout(SettingsLayoutDraft)
    case editLayout(id: String, edit: SettingsLayoutEdit)
    case deleteLayout(id: String)
    case saveDisplayProfile(SettingsDisplayProfileDraft)
    case createDisplayProfilesForConnectedDisplays
    case deleteDisplayProfile(stableDisplayID: String)
    case replaceAppRules(defaultDecision: AppRuleDecision, rules: [AppRule])
    case updateEdgeSnapZoneConfiguration(EdgeSnapZoneConfigurationSnapshot)
}

/// Composition boundary for the Settings UI. A production adapter applies each
/// change to the runtime and persists it; test adapters can observe the same
/// contract without AppKit or Accessibility access.
@MainActor
public protocol SettingsRuntimeProviding: AnyObject {
    func currentSettings() -> SettingsRuntimeSnapshot
    func apply(_ change: SettingsRuntimeChange)
    func openSystemSettings()
    func openHotkeyEditor(_ editor: SettingsHotkeyEditor)
    func importConfiguration(completion: @escaping @MainActor () -> Void)
    func exportConfiguration()
    func copyDiagnosticsReport()
}

public extension SettingsRuntimeProviding {
    func importConfiguration(completion: @escaping @MainActor () -> Void) { completion() }
    func exportConfiguration() {}
    func copyDiagnosticsReport() {}
}

@MainActor
public final class SettingsShellModel: ObservableObject {
    @Published public private(set) var selectedSection: SettingsSection
    @Published public private(set) var snapshot: SettingsRuntimeSnapshot

    private let runtime: any SettingsRuntimeProviding

    public init(
        runtime: any SettingsRuntimeProviding,
        selectedSection: SettingsSection = .general
    ) {
        self.runtime = runtime
        self.selectedSection = selectedSection
        snapshot = runtime.currentSettings()
    }

    public var accessibilityPresentation: SettingsPermissionPresentation {
        SettingsPermissionPresentation(snapshot.general.accessibility)
    }

    public var generalPermissionMessage: String { accessibilityPresentation.message }

    public var hotkeyEditorPresentation: SettingsHotkeysSnapshot? {
        selectedSection == .hotkeys ? snapshot.hotkeys : nil
    }

    public func select(_ section: SettingsSection) {
        selectedSection = section
    }

    public func reload() {
        snapshot = runtime.currentSettings()
    }

    public func openSystemSettings() {
        runtime.openSystemSettings()
    }

    public func openHotkeyEditor(_ editor: SettingsHotkeyEditor? = nil) {
        runtime.openHotkeyEditor(editor ?? snapshot.hotkeys.editor)
    }

    public func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        apply(.launchAtLoginEnabled(isEnabled))
    }

    public func setSnappingEnabled(_ isEnabled: Bool) {
        apply(.snappingEnabled(isEnabled))
    }

    public func setSnappingTrigger(_ trigger: SnappingTrigger) {
        apply(.snappingTrigger(trigger))
    }

    public func setSnappingDwellMilliseconds(_ milliseconds: UInt32) {
        apply(.snappingDwellMilliseconds(milliseconds))
    }

    public func setPlacementPreviewEnabled(_ isEnabled: Bool) {
        apply(.placementPreviewEnabled(isEnabled))
    }

    public func setReducedEffectsEnabled(_ isEnabled: Bool) {
        apply(.reducedEffectsEnabled(isEnabled))
    }

    public func saveLayout(_ draft: SettingsLayoutDraft) { apply(.saveLayout(draft)) }
    public func editLayout(id: String, edit: SettingsLayoutEdit) { apply(.editLayout(id: id, edit: edit)) }
    public func deleteLayout(id: String) { apply(.deleteLayout(id: id)) }
    public func saveDisplayProfile(_ draft: SettingsDisplayProfileDraft) { apply(.saveDisplayProfile(draft)) }
    public func createDisplayProfilesForConnectedDisplays() { apply(.createDisplayProfilesForConnectedDisplays) }
    public func deleteDisplayProfile(stableDisplayID: String) { apply(.deleteDisplayProfile(stableDisplayID: stableDisplayID)) }
    public func replaceAppRules(defaultDecision: AppRuleDecision, rules: [AppRule]) {
        apply(.replaceAppRules(defaultDecision: defaultDecision, rules: rules))
    }
    public func updateEdgeSnapZoneConfiguration(_ snapshot: EdgeSnapZoneConfigurationSnapshot) {
        apply(.updateEdgeSnapZoneConfiguration(snapshot))
    }
    public func importConfiguration() {
        runtime.importConfiguration { [weak self] in self?.reload() }
    }
    public func exportConfiguration() { runtime.exportConfiguration(); reload() }
    public func copyDiagnosticsReport() { runtime.copyDiagnosticsReport() }

    private func apply(_ change: SettingsRuntimeChange) {
        runtime.apply(change)
        snapshot = runtime.currentSettings()
    }
}

@MainActor
public final class SettingsShellWindowController {
    private let model: SettingsShellModel
    private var window: NSWindow?

    public init(runtime: any SettingsRuntimeProviding) {
        model = SettingsShellModel(runtime: runtime)
    }

    public func present() {
        let settingsWindow = window ?? makeWindow()
        window = settingsWindow
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        model.reload()
    }

    public func select(_ section: SettingsSection) {
        model.select(section)
    }

    public var modelForTesting: SettingsShellModel { model }
    public var windowForTesting: NSWindow? { window }

    /// Builds the same production view hierarchy without ordering the window on
    /// screen, allowing deterministic compact-size render verification.
    func windowForTesting(
        contentSize: NSSize,
        dynamicTypeSize: DynamicTypeSize? = nil
    ) -> NSWindow {
        let settingsWindow = makeWindow(dynamicTypeSize: dynamicTypeSize)
        window = settingsWindow
        settingsWindow.setContentSize(contentSize)
        settingsWindow.contentView?.layoutSubtreeIfNeeded()
        return settingsWindow
    }

    private func makeWindow(dynamicTypeSize: DynamicTypeSize? = nil) -> NSWindow {
        let controller: NSViewController
        if let dynamicTypeSize {
            controller = NSHostingController(
                rootView: SettingsShellView(model: model)
                    .dynamicTypeSize(dynamicTypeSize)
            )
        } else {
            controller = NSHostingController(rootView: SettingsShellView(model: model))
        }
        let window = NSWindow(contentViewController: controller)
        window.title = SettingsCopy.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 880, height: 620))
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.setAccessibilityLabel(SettingsCopy.windowTitle)
        return window
    }
}

private struct SettingsShellView: View {
    @ObservedObject var model: SettingsShellModel
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator()
    @State private var searchQuery: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let searchIndex = SettingsSearchIndex()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                searchField
                sidebarList
            }
            .navigationTitle(SettingsCopy.windowTitle)
            .accessibilityLabel(SettingsCopy.settingsSections)
        } detail: {
            ScrollViewReader { proxy in
                detailContent
                    .environmentObject(highlightCoordinator)
                    .onChange(of: highlightCoordinator.activeAnchor) { newAnchor in
                        guard let newAnchor else { return }
                        withAnimation(SettingsMotion.animation(reduceMotion: reduceMotion)) {
                            proxy.scrollTo(newAnchor, anchor: .center)
                        }
                    }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11, weight: .medium))
            TextField(SettingsCopy.searchPlaceholder, text: $searchQuery)
                .textFieldStyle(.plain)
                .font(SettingsTypography.supporting)
                .accessibilityIdentifier("settings.sidebar.search")
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SettingsCopy.clearSearch)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: SettingsRadius.control, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsRadius.control, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var sidebarList: some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            List(selection: selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                        .accessibilityIdentifier(SettingsAccessibilityID.section(section))
                }
            }
        } else {
            let groups = searchIndex.search(query: trimmed)
            if groups.isEmpty {
                VStack(spacing: 8) {
                    Text(SettingsCopy.noSearchResults)
                        .font(SettingsTypography.supporting)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.section.title) {
                            ForEach(group.items) { item in
                                Button {
                                    model.select(item.section)
                                    highlightCoordinator.land(on: item.anchor, reduceMotion: reduceMotion)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(SettingsTypography.rowTitle)
                                            .foregroundStyle(.primary)
                                        Text(item.caption)
                                            .font(SettingsTypography.rowCaption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.selectedSection {
        case .general:
            GeneralSettingsView(model: model)
        case .snapping:
            SnappingSettingsView(model: model)
        case .hotkeys:
            HotkeySettingsSummaryView(model: model)
        case .layouts:
            LayoutLibrarySettingsView(model: model)
        case .displays:
            DisplayProfilesSettingsView(model: model)
        case .appRules:
            AppRulesSettingsView(model: model)
        case .transfer:
            ConfigurationTransferSettingsView(model: model)
        case .about:
            AboutDiagnosticsSettingsView(model: model)
        }
    }

    private var selectedSection: Binding<SettingsSection?> {
        Binding(
            get: { model.selectedSection },
            set: { section in
                if let section { model.select(section) }
            }
        )
    }
}

struct LayoutLibrarySettingsView: View {
    @ObservedObject var model: SettingsShellModel
    @State private var selectedLayoutID: String = "preset-halves"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presets: [LayoutDraft] {
        LayoutDraft.standardPresets
    }

    private var customLayouts: [SettingsLayoutPresentation] {
        model.snapshot.layouts
    }

    private var allLayoutItems: [(id: String, name: String, regions: [CGRect], isCustom: Bool, presentation: SettingsLayoutPresentation?)] {
        var items: [(id: String, name: String, regions: [CGRect], isCustom: Bool, presentation: SettingsLayoutPresentation?)] = []
        for preset in presets {
            items.append((
                id: preset.id,
                name: preset.name,
                regions: preset.regions.map(\.normalizedFrame),
                isCustom: false,
                presentation: nil
            ))
        }
        for custom in customLayouts {
            items.append((
                id: custom.id,
                name: custom.draft.name,
                regions: custom.draft.regions.map(\.normalizedFrame),
                isCustom: true,
                presentation: custom
            ))
        }
        return items
    }

    private var activeSelectedItem: (id: String, name: String, regions: [CGRect], isCustom: Bool, presentation: SettingsLayoutPresentation?)? {
        if let match = allLayoutItems.first(where: { $0.id == selectedLayoutID }) {
            return match
        }
        return customLayouts.first.map {
            (id: $0.id, name: $0.draft.name, regions: $0.draft.regions.map(\.normalizedFrame), isCustom: true, presentation: $0)
        } ?? allLayoutItems.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsSpacing.cardStackGap) {
                // Section 1: Presets & Custom Layouts Grid
                VStack(alignment: .leading, spacing: SettingsSpacing.small) {
                    Text(SettingsCopy.layoutLibraryTitle)
                        .font(SettingsTypography.sectionTitle)
                        .foregroundStyle(.primary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 120, maximum: 140), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(allLayoutItems, id: \.id) { item in
                            let isSelected = (item.id == (activeSelectedItem?.id ?? selectedLayoutID))
                            Button {
                                withAnimation(SettingsMotion.animation(reduceMotion: reduceMotion)) {
                                    selectedLayoutID = item.id
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    LayoutThumbnailView(
                                        regions: item.regions,
                                        isSelected: isSelected,
                                        size: CGSize(width: 80, height: 52)
                                    )

                                    Text(item.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)

                                    CapsuleBadge(
                                        item.isCustom ? "Custom" : "Preset",
                                        tint: item.isCustom ? .systemIndigo : .secondaryLabelColor
                                    )
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(item.name), \(item.isCustom ? "Custom" : "Preset")")
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        }
                    }
                }
                .settingsSectionAnchor(.layoutsLibrary)

                // Section 2: Edit Layout Card
                if let active = activeSelectedItem {
                    SettingsCard(label: "Edit Layout") {
                        SettingsRow(
                            icon: IconTile(systemName: "rectangle.split.3x1", tint: .green),
                            title: active.name,
                            caption: "Select a layout above, then use the actions below to modify its regions."
                        ) {
                            Text(SettingsCopy.regionCount(active.regions.count))
                                .font(SettingsTypography.code)
                                .foregroundStyle(.secondary)
                        }

                        SettingsDivider()

                        SettingsRow(
                            title: "Modify Regions",
                            caption: "Divide or join Layout Regions within this layout"
                        ) {
                            HStack(spacing: 8) {
                                Button(SettingsCopy.splitColumns) {
                                    splitActive(active, direction: .columns)
                                }
                                Button(SettingsCopy.splitRows) {
                                    splitActive(active, direction: .rows)
                                }
                                Button(SettingsCopy.mergeRegions) {
                                    mergeActive(active)
                                }
                                .disabled(active.regions.count < 2)
                            }
                        }

                        if let validation = active.presentation?.validationMessage {
                            SettingsDivider()
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(validation)
                                    .font(SettingsTypography.rowCaption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                        }

                        if active.isCustom, let presentation = active.presentation {
                            SettingsDivider()
                            HStack {
                                Spacer()
                                Button(SettingsCopy.delete) {
                                    model.deleteLayout(id: presentation.id)
                                    selectedLayoutID = presets.first?.id ?? "preset-halves"
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                // Section 3: Add Custom Layout
                SettingsCard(label: "Add Layout") {
                    HStack(spacing: 8) {
                        Button("Add Coding Layout") {
                            let coding = LayoutDraft.coding
                            model.saveLayout(.init(
                                id: coding.id,
                                name: coding.name,
                                regions: coding.regions.map {
                                    .init(id: $0.id.rawValue, normalizedFrame: $0.normalizedFrame)
                                }
                            ))
                            selectedLayoutID = coding.id
                        }
                        .buttonStyle(.bordered)

                        Button(SettingsCopy.addLayout) {
                            let suffix = UUID().uuidString.prefix(8)
                            let newID = "layout-\(suffix)"
                            model.saveLayout(.init(
                                id: newID,
                                name: SettingsCopy.newLayoutName,
                                regions: [.init(id: "main", normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 1))]
                            ))
                            selectedLayoutID = newID
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(SettingsSpacing.large)
            .frame(maxWidth: SettingsSpacing.maxContentWidth, alignment: .leading)
        }
        .navigationTitle(SettingsCopy.layoutsSectionTitle)
        .accessibilityIdentifier(SettingsAccessibilityID.layoutLibrary)
    }

    private func splitActive(
        _ item: (id: String, name: String, regions: [CGRect], isCustom: Bool, presentation: SettingsLayoutPresentation?),
        direction: SettingsLayoutSplitDirection
    ) {
        if let presentation = item.presentation {
            guard let region = presentation.draft.regions.first else { return }
            let suffix = UUID().uuidString.prefix(8)
            model.editLayout(id: presentation.id, edit: .split(
                regionID: region.id,
                direction: direction,
                firstFraction: 0.5,
                firstRegionID: "\(region.id)-a-\(suffix)",
                secondRegionID: "\(region.id)-b-\(suffix)"
            ))
        } else {
            let suffix = UUID().uuidString.prefix(8)
            let newID = "custom-\(item.name.lowercased())-\(suffix)"
            var draftRegions = item.regions.enumerated().map { (index, frame) in
                SettingsLayoutRegionDraft(id: "region-\(index)", normalizedFrame: frame)
            }
            guard !draftRegions.isEmpty else { return }
            let target = draftRegions.removeFirst()
            let firstFrame: CGRect
            let secondFrame: CGRect
            if direction == .columns {
                let halfW = target.normalizedFrame.width * 0.5
                firstFrame = CGRect(x: target.normalizedFrame.minX, y: target.normalizedFrame.minY, width: halfW, height: target.normalizedFrame.height)
                secondFrame = CGRect(x: target.normalizedFrame.minX + halfW, y: target.normalizedFrame.minY, width: target.normalizedFrame.width - halfW, height: target.normalizedFrame.height)
            } else {
                let halfH = target.normalizedFrame.height * 0.5
                firstFrame = CGRect(x: target.normalizedFrame.minX, y: target.normalizedFrame.minY, width: target.normalizedFrame.width, height: halfH)
                secondFrame = CGRect(x: target.normalizedFrame.minX, y: target.normalizedFrame.minY + halfH, width: target.normalizedFrame.width, height: target.normalizedFrame.height - halfH)
            }
            draftRegions.insert(SettingsLayoutRegionDraft(id: "\(target.id)-a", normalizedFrame: firstFrame), at: 0)
            draftRegions.insert(SettingsLayoutRegionDraft(id: "\(target.id)-b", normalizedFrame: secondFrame), at: 1)

            model.saveLayout(.init(
                id: newID,
                name: "\(item.name) Custom",
                regions: draftRegions
            ))
            selectedLayoutID = newID
        }
    }

    private func mergeActive(
        _ item: (id: String, name: String, regions: [CGRect], isCustom: Bool, presentation: SettingsLayoutPresentation?)
    ) {
        if let presentation = item.presentation {
            model.editLayout(
                id: presentation.id,
                edit: .merge(regionIDs: presentation.draft.regions.map(\.id), mergedRegionID: "merged")
            )
        }
    }
}

struct DisplayProfilesSettingsView: View {
    @ObservedObject var model: SettingsShellModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsSpacing.cardStackGap) {
                if model.snapshot.displayProfiles.isEmpty {
                    SettingsCard {
                        SettingsRow(
                            icon: IconTile(systemName: "display.trianglebadge.exclamationmark", tint: .orange),
                            title: SettingsCopy.displayProfilesTitle,
                            caption: SettingsCopy.displayProfilesEmptyState
                        ) {
                            Button(SettingsCopy.addConnectedDisplays) {
                                model.createDisplayProfilesForConnectedDisplays()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ForEach(model.snapshot.displayProfiles) { profile in
                        SettingsCard {
                            // Header
                            HStack(spacing: SettingsSpacing.rowGap) {
                                IconTile(
                                    systemName: "display",
                                    tint: profile.isConnected ? Color(nsColor: .controlAccentColor) : .secondary
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: profile))
                                        .font(SettingsTypography.rowTitle)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)

                                    Text("Stable Display ID: \(profile.draft.stableDisplayID)")
                                        .font(SettingsTypography.code)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    StatusDot(state: profile.isConnected ? .active : .inactive)
                                    Text(profile.isConnected ? SettingsCopy.displayConnected : "Disconnected")
                                        .font(SettingsTypography.supporting)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)

                            if !profile.isConnected {
                                SettingsDivider()
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 11))
                                    Text("This display is currently disconnected. Settings will apply when reconnected.")
                                        .font(SettingsTypography.rowCaption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 4)
                            }

                            SettingsDivider()

                            // Gap Stepper
                            SettingsRow(
                                title: SettingsCopy.gap,
                                caption: "Spacing between tiled windows in points"
                            ) {
                                HStack(spacing: 8) {
                                    Button("−") {
                                        let newGap = DisplayProfile.clampedGap(profile.draft.gap - 1)
                                        updateGap(newGap, for: profile)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(profile.draft.gap <= 0)

                                    Text("\(Int(profile.draft.gap)) pt")
                                        .font(SettingsTypography.stepper)
                                        .frame(minWidth: 44, alignment: .center)

                                    Button("+") {
                                        let newGap = DisplayProfile.clampedGap(profile.draft.gap + 1)
                                        updateGap(newGap, for: profile)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(profile.draft.gap >= 200)
                                }
                            }

                            SettingsDivider()

                            // Layout Assignments
                            SettingsRow(
                                title: SettingsCopy.assignedLayouts,
                                caption: "Layouts enabled for window placement on this display"
                            ) {
                                EmptyView()
                            } subcontent: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(model.snapshot.layouts) { layout in
                                        Toggle(
                                            layout.draft.name,
                                            isOn: layoutAssignmentBinding(layoutID: layout.id, profile: profile)
                                        )
                                        .accessibilityLabel("\(layout.draft.name), \(SettingsCopy.assignedLayouts)")
                                    }
                                }
                                .padding(.top, 4)
                            }

                            if let message = profile.validationMessage {
                                SettingsDivider()
                                Label(message, systemImage: "exclamationmark.triangle")
                                    .font(SettingsTypography.rowCaption)
                                    .foregroundStyle(.red)
                                    .padding(.vertical, 4)
                            }

                            SettingsDivider()

                            HStack {
                                Spacer()
                                Button(SettingsCopy.delete) {
                                    model.deleteDisplayProfile(stableDisplayID: profile.draft.stableDisplayID)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(SettingsSpacing.large)
            .frame(maxWidth: SettingsSpacing.maxContentWidth, alignment: .leading)
            .settingsSectionAnchor(.displayProfiles)
        }
        .navigationTitle(SettingsCopy.displaysSectionTitle)
        .accessibilityIdentifier(SettingsAccessibilityID.displayProfiles)
    }

    private func displayName(for profile: SettingsDisplayProfilePresentation) -> String {
        if profile.draft.stableDisplayID.lowercased().contains("builtin") || profile.draft.stableDisplayID.contains("4280A3F1") {
            return "Built-in Retina Display"
        }
        return "Display (\(profile.draft.stableDisplayID.prefix(8)))"
    }

    private func updateGap(_ gap: Double, for profile: SettingsDisplayProfilePresentation) {
        var draft = profile.draft
        draft.gap = gap
        model.saveDisplayProfile(draft)
    }

    private func layoutAssignmentBinding(
        layoutID: String,
        profile: SettingsDisplayProfilePresentation
    ) -> Binding<Bool> {
        Binding(get: { profile.draft.layoutIDs.contains(layoutID) }, set: { isAssigned in
            var draft = profile.draft
            if isAssigned {
                if !draft.layoutIDs.contains(layoutID) { draft.layoutIDs.append(layoutID) }
            } else if draft.layoutIDs.count > 1 {
                draft.layoutIDs.removeAll { $0 == layoutID }
            }
            model.saveDisplayProfile(draft)
        })
    }
}

struct AppRulesSettingsView: View {
    @ObservedObject var model: SettingsShellModel
    @State private var bundleIdentifier: String = ""
    @State private var newRuleDecision: AppRuleDecision = .included
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsSpacing.cardStackGap) {
                // Section 1: Default Behavior Card
                SettingsCard(label: SettingsCopy.defaultAppBehavior) {
                    SettingsRow(
                        icon: IconTile(systemName: "app.badge.checkmark", tint: .blue),
                        title: "Default Management",
                        caption: model.snapshot.appRules.defaultDecision == .included
                            ? "New applications are managed by MyMacX unless explicitly excluded."
                            : "New applications are excluded from window management unless explicitly included."
                    ) {
                        Picker("", selection: defaultDecision) {
                            Text(SettingsCopy.included).tag(AppRuleDecision.included)
                            Text(SettingsCopy.excluded).tag(AppRuleDecision.excluded)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }

                    SettingsDivider()

                    HStack(spacing: 8) {
                        Image(systemName: "shield.checkered")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        Text("Applications with missing or invalid bundle identities fail closed and are always excluded from window placement.")
                            .font(SettingsTypography.rowCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }

                // Section 2: Rules List Card
                SettingsCard(label: "Rules") {
                    if model.snapshot.appRules.rules.isEmpty {
                        Text("No application rules configured. Default management behavior applies to all applications.")
                            .font(SettingsTypography.rowCaption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(model.snapshot.appRules.rules.enumerated()), id: \.element.bundleIdentifier) { index, rule in
                            if index > 0 {
                                SettingsDivider()
                            }
                            HStack(spacing: SettingsSpacing.rowGap) {
                                AppRuleIconView(
                                    bundleIdentifier: rule.bundleIdentifier.value,
                                    decision: rule.decision
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appDisplayName(for: rule.bundleIdentifier.value))
                                        .font(SettingsTypography.rowTitle)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)

                                    Text(rule.bundleIdentifier.value)
                                        .font(SettingsTypography.code)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                CapsuleBadge(
                                    rule.decision == .included ? "Included" : "Excluded",
                                    tint: rule.decision == .included ? .systemGreen : .systemOrange
                                )

                                Picker("", selection: decisionBinding(for: rule)) {
                                    Text(SettingsCopy.included).tag(AppRuleDecision.included)
                                    Text(SettingsCopy.excluded).tag(AppRuleDecision.excluded)
                                }
                                .labelsHidden()
                                .frame(width: 110)

                                Button {
                                    remove(rule)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(SettingsCopy.delete) \(rule.bundleIdentifier.value)")
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .contain)
                        }
                    }
                }

                // Section 3: Add Rule Card
                SettingsCard(label: "Add Rule") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField(SettingsCopy.bundleIdentifier, text: $bundleIdentifier)
                                .textFieldStyle(.roundedBorder)
                                .font(SettingsTypography.code)
                                .accessibilityIdentifier(SettingsAccessibilityID.appRuleBundleIdentifier)

                            Picker("", selection: $newRuleDecision) {
                                Text(SettingsCopy.included).tag(AppRuleDecision.included)
                                Text(SettingsCopy.excluded).tag(AppRuleDecision.excluded)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)

                            Button("Add") {
                                addRule(newRuleDecision)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(errorMessage)
                                    .font(SettingsTypography.rowCaption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
            .padding(SettingsSpacing.large)
            .frame(maxWidth: SettingsSpacing.maxContentWidth, alignment: .leading)
            .settingsSectionAnchor(.appRules)
        }
        .navigationTitle(SettingsCopy.appRulesSectionTitle)
        .padding(0)
    }

    private var defaultDecision: Binding<AppRuleDecision> {
        Binding(get: { model.snapshot.appRules.defaultDecision }, set: {
            model.replaceAppRules(defaultDecision: $0, rules: model.snapshot.appRules.rules)
        })
    }

    private func decisionBinding(for rule: AppRule) -> Binding<AppRuleDecision> {
        Binding(get: { rule.decision }, set: { decision in
            let rules = model.snapshot.appRules.rules.map {
                $0.bundleIdentifier == rule.bundleIdentifier
                    ? AppRule(bundleIdentifier: $0.bundleIdentifier, decision: decision) : $0
            }
            model.replaceAppRules(defaultDecision: model.snapshot.appRules.defaultDecision, rules: rules)
        })
    }

    private func addRule(_ decision: AppRuleDecision) {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = ApplicationBundleIdentifier.validationError(for: trimmed) {
            errorMessage = error
            return
        }
        guard let id = ApplicationBundleIdentifier(trimmed) else {
            errorMessage = "Invalid bundle identifier. Missing or malformed identities fail closed and are excluded."
            return
        }
        errorMessage = nil
        let rule = AppRule(bundleIdentifier: id, decision: decision)
        let rules = model.snapshot.appRules.rules.filter { $0.bundleIdentifier != id } + [rule]
        model.replaceAppRules(defaultDecision: model.snapshot.appRules.defaultDecision, rules: rules)
        bundleIdentifier = ""
    }

    private func remove(_ rule: AppRule) {
        model.replaceAppRules(
            defaultDecision: model.snapshot.appRules.defaultDecision,
            rules: model.snapshot.appRules.rules.filter { $0.bundleIdentifier != rule.bundleIdentifier }
        )
    }

    private func appDisplayName(for bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let name = url.deletingPathExtension().lastPathComponent
            if !name.isEmpty { return name }
        }
        let components = bundleIdentifier.split(separator: ".")
        if let last = components.last, !last.isEmpty {
            return last.prefix(1).uppercased() + last.dropFirst()
        }
        return bundleIdentifier
    }
}

struct AppRuleIconView: View {
    let bundleIdentifier: String
    let decision: AppRuleDecision

    var body: some View {
        if let icon = iconImage() {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 26, height: 26)
                .cornerRadius(SettingsRadius.iconTile)
        } else {
            IconTile(
                systemName: "app.fill",
                tint: decision == .included ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
            )
        }
    }

    private func iconImage() -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct ConfigurationTransferSettingsView: View {
    @ObservedObject var model: SettingsShellModel
    var body: some View {
        Form {
            Section(SettingsCopy.configurationBackupTitle) {
                Text(SettingsCopy.configurationBackupExplanation).foregroundStyle(.secondary)
                HStack {
                    Button(SettingsCopy.importConfiguration) { model.importConfiguration() }
                        .keyboardShortcut("i", modifiers: [.command, .shift])
                    Button(SettingsCopy.exportConfiguration) { model.exportConfiguration() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                }
                if let message = model.snapshot.transfer.statusMessage {
                    Label(message, systemImage: model.snapshot.transfer.isError ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(model.snapshot.transfer.isError ? .red : .secondary)
                        .accessibilityLabel(message)
                }
            }
            .settingsSectionAnchor(.transferBackup)
        }
        .formStyle(.grouped).navigationTitle(SettingsCopy.transferSectionTitle).padding()
    }
}

private struct AboutDiagnosticsSettingsView: View {
    @ObservedObject var model: SettingsShellModel
    var body: some View {
        let status = model.snapshot.diagnostics.status
        Form {
            Section(SettingsCopy.aboutSectionTitle) {
                LabeledContent(SettingsCopy.appVersion, value: "\(status.appVersion.major).\(status.appVersion.minor).\(status.appVersion.patch) (\(status.appBuild))")
                LabeledContent(SettingsCopy.operatingSystem, value: "\(status.operatingSystem.major).\(status.operatingSystem.minor).\(status.operatingSystem.patch)")
            }
            Section(SettingsCopy.diagnosticsTitle) {
                LabeledContent(SettingsCopy.accessibilityPermission, value: status.accessibility.rawValue)
                LabeledContent(SettingsCopy.inputMonitoringPermission, value: status.inputMonitoring.rawValue)
                LabeledContent(SettingsCopy.eventTap, value: status.eventTap.rawValue)
                TextEditor(text: .constant(model.snapshot.diagnostics.report))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .accessibilityLabel(SettingsCopy.redactedDiagnosticsReport)
                Button(SettingsCopy.copyDiagnostics) { model.copyDiagnosticsReport() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .settingsSectionAnchor(.aboutDiagnostics)
        }
        .formStyle(.grouped).navigationTitle(SettingsCopy.aboutSectionTitle).padding()
        .accessibilityIdentifier(SettingsAccessibilityID.diagnostics)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsShellModel

    var body: some View {
        Form {
            Section(SettingsCopy.permissionsSectionTitle) {
                LabeledContent(SettingsCopy.accessibilityPermission) {
                    Text(model.generalPermissionMessage)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(SettingsCopy.accessibilityPermission): \(model.generalPermissionMessage)")

                Button(SettingsCopy.openSystemSettings) {
                    model.openSystemSettings()
                }
                .accessibilityHint(SettingsCopy.openSystemSettingsHint)

                LabeledContent(SettingsCopy.inputMonitoringPermission) {
                    Text(model.snapshot.general.inputMonitoringGranted ? SettingsCopy.permissionGranted : SettingsCopy.permissionRequired)
                }
                .accessibilityElement(children: .combine)
            }
            .settingsSectionAnchor(.generalPermissions)

            Section(SettingsCopy.startupSectionTitle) {
                Toggle(
                    SettingsCopy.launchAtLogin,
                    isOn: Binding(
                        get: { model.snapshot.general.launchesAtLogin },
                        set: { model.setLaunchAtLoginEnabled($0) }
                    )
                )
                .accessibilityIdentifier(SettingsAccessibilityID.launchAtLogin)
            }
            .settingsSectionAnchor(.generalStartup)
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsCopy.generalSectionTitle)
        .padding()
    }
}

private struct SnappingSettingsView: View {
    @ObservedObject var model: SettingsShellModel
    @StateObject private var tilingModel: SystemTilingCoexistenceModel
    @StateObject private var zoneStore: EdgeSnapZoneConfigurationStore
    @StateObject private var pickerViewModel: ZoneMapPickerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(model: SettingsShellModel) {
        self.model = model
        let store = EdgeSnapZoneConfigurationStore(snapshot: model.snapshot.edgeSnap)
        _zoneStore = StateObject(wrappedValue: store)
        _tilingModel = StateObject(wrappedValue: SystemTilingCoexistenceModel())
        _pickerViewModel = StateObject(wrappedValue: ZoneMapPickerViewModel(
            store: store,
            onSave: { [weak model] snapshot in
                model?.updateEdgeSnapZoneConfiguration(snapshot)
            }
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsSpacing.cardStackGap) {
                // ADR-0002 Fail-Visible System Tiling Stand-Down Banner
                if case let .stoodDown(reason) = tilingModel.status {
                    SystemTilingStandDownBanner(reason: reason)
                }

                // General Snapping Settings Card
                SettingsCard(label: SettingsCopy.snappingSectionTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            SettingsCopy.enableSnapping,
                            isOn: Binding(
                                get: { model.snapshot.snapping.isEnabled },
                                set: { model.setSnappingEnabled($0) }
                            )
                        )
                        .accessibilityIdentifier(SettingsAccessibilityID.snappingEnabled)
                        .settingsSectionAnchor(.snappingMaster)

                        Picker(
                            SettingsCopy.trigger,
                            selection: Binding(
                                get: { model.snapshot.snapping.trigger },
                                set: { model.setSnappingTrigger($0) }
                            )
                        ) {
                            ForEach(SnappingTrigger.allCases) { trigger in
                                Text(trigger.title).tag(trigger)
                            }
                        }
                        .disabled(!model.snapshot.snapping.isEnabled || triggerIsUnavailable)
                        .accessibilityIdentifier(SettingsAccessibilityID.snappingTrigger)
                        .settingsSectionAnchor(.snappingTrigger)

                        if case let .unavailable(message) = model.snapshot.snapping.triggerAvailability {
                            Text(message)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(message)
                        }

                        Stepper(
                            "\(SettingsCopy.activationDelay): \(model.snapshot.snapping.dwellMilliseconds) ms",
                            value: Binding(
                                get: { model.snapshot.snapping.dwellMilliseconds },
                                set: { model.setSnappingDwellMilliseconds($0) }
                            ),
                            in: 50...1_000,
                            step: 50
                        )
                        .disabled(!model.snapshot.snapping.isEnabled)
                        .accessibilityIdentifier(SettingsAccessibilityID.snappingDwell)
                        .settingsSectionAnchor(.snappingTrigger)

                        Toggle(
                            SettingsCopy.showPlacementPreview,
                            isOn: Binding(
                                get: { model.snapshot.snapping.showsPlacementPreview },
                                set: { model.setPlacementPreviewEnabled($0) }
                            )
                        )
                        .disabled(!model.snapshot.snapping.isEnabled)
                        .settingsSectionAnchor(.snappingPreview)

                        Toggle(
                            SettingsCopy.reduceVisualEffects,
                            isOn: Binding(
                                get: { model.snapshot.snapping.usesReducedEffects },
                                set: { model.setReducedEffectsEnabled($0) }
                            )
                        )
                        .accessibilityIdentifier(SettingsAccessibilityID.reducedEffects)
                        .settingsSectionAnchor(.snappingReducedEffects)

                        if reduceMotion || reduceTransparency {
                            Text(SettingsCopy.systemReducedEffectsNotice)
                                .font(SettingsTypography.rowCaption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(SettingsCopy.systemReducedEffectsNotice)
                        }
                    }
                }

                // Zone-Map Picker Card (Shared Component)
                SettingsCard(label: SettingsCopy.edgeSnapSectionTitle) {
                    ZoneMapPickerView(model: pickerViewModel)
                }
                .settingsSectionAnchor(.snappingZoneMap)

                // Multi-Display Seam Gating Card
                SettingsCard(label: SettingsCopy.seamGatingTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(SettingsCopy.seamGatingExplanation)
                            .font(SettingsTypography.rowCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(
                            SettingsCopy.seamGatingTitle,
                            isOn: Binding(
                                get: { zoneStore.seamGateSettings().isEnabled },
                                set: { zoneStore.setSeamGatingEnabled($0) }
                            )
                        )

                        HStack {
                            Text("\(SettingsCopy.seamCrossingSpeedThreshold): \(Int(zoneStore.seamGateSettings().crossingSpeedThreshold)) pt/s")
                                .font(SettingsTypography.rowCaption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Stepper("", value: Binding(
                                get: { zoneStore.seamGateSettings().crossingSpeedThreshold },
                                set: { zoneStore.setCrossingSpeedThreshold($0) }
                            ), in: 100...1_200, step: 50)
                            .disabled(!zoneStore.seamGateSettings().isEnabled)
                        }
                    }
                }
                .settingsSectionAnchor(.snappingSeamGating)
            }
            .padding()
            .frame(maxWidth: SettingsCardLayout.maxContentWidth)
        }
        .navigationTitle(SettingsCopy.snappingSectionTitle)
        .onChange(of: model.snapshot.edgeSnap) { newSnapshot in
            zoneStore.load(from: newSnapshot)
        }
        .onDisappear {
            pickerViewModel.flushSave()
        }
    }

    private var triggerIsUnavailable: Bool {
        if case .unavailable = model.snapshot.snapping.triggerAvailability { return true }
        return false
    }
}

public struct KeycapBadgeView: View {
    public let label: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(label: String) {
        self.label = label
    }

    public var body: some View {
        KeycapChip(label: label)
    }
}

public struct KeySequenceBadgeView: View {
    public let item: SettingsCommandTreeItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(item: SettingsCommandTreeItem) {
        self.item = item
    }

    public var body: some View {
        let keyList = item.keys.isEmpty ? [item.keySequence] : item.keys
        KeycapSequenceView(keys: keyList)
    }
}

private struct HotkeySettingsSummaryView: View {
    @ObservedObject var model: SettingsShellModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let presentation = model.snapshot.hotkeys
        Form {
            if let message = presentation.validationMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityLabel("\(SettingsCopy.hotkeyValidationError): \(message)")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Super Mode")
                                .font(.headline)
                            Text("Fast window placement via short sequential key sequences.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button(SettingsCopy.editSuperMode) {
                                model.openHotkeyEditor(.superMode)
                            }
                            .accessibilityHint(SettingsCopy.hotkeyEditorHint)
                        }
                    } else {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Super Mode")
                                    .font(.headline)
                                Text("Fast window placement via short sequential key sequences.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(SettingsCopy.editSuperMode) {
                                model.openHotkeyEditor(.superMode)
                            }
                            .accessibilityHint(SettingsCopy.hotkeyEditorHint)
                        }
                    }

                    if let prefix = presentation.prefixPresentation {
                        HStack(spacing: 8) {
                            Text("Prefix Shortcut:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            KeycapBadgeView(label: prefix)
                            Text("then press action key(s)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(SettingsCopy.hotkeysSectionTitle)
            }
            .settingsSectionAnchor(.hotkeysSuperMode)

            Section {
                if presentation.commandTree.isEmpty {
                    Text(SettingsCopy.hotkeyEmptyState)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(presentation.commandTree) { item in
                        row(for: item)
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(item.accessibilityLabel)
                    }
                }
            } header: {
                Text(SettingsCopy.commandTreeTitle)
            }
            .accessibilityIdentifier(SettingsAccessibilityID.hotkeyCommandTree)
            .accessibilityLabel(presentation.commandTreeAccessibilityLabel)
            .settingsSectionAnchor(.hotkeysCommandTree)

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Global Hotkeys")
                                .font(.headline)
                            Text("Instant keyboard shortcuts available from any application.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button(SettingsCopy.editHotkeys) {
                                model.openHotkeyEditor(.hotkeys)
                            }
                            .accessibilityHint(SettingsCopy.hotkeyEditorHint)
                        }
                    } else {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Global Hotkeys")
                                    .font(.headline)
                                Text("Instant keyboard shortcuts available from any application.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(SettingsCopy.editHotkeys) {
                                model.openHotkeyEditor(.hotkeys)
                            }
                            .accessibilityHint(SettingsCopy.hotkeyEditorHint)
                        }
                    }

                    if !presentation.globalHotkeys.isEmpty {
                        Divider()
                            .padding(.vertical, 2)
                        ForEach(presentation.globalHotkeys) { item in
                            row(for: item)
                                .padding(.vertical, 2)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(item.accessibilityLabel)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Global Hotkeys")
            }
            .settingsSectionAnchor(.hotkeysGlobal)

            if presentation.recorder != .ready {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: presentation.recorder == .recording ? "record.circle" : "exclamationmark.circle")
                            .foregroundStyle(presentation.recorder == .recording ? Color.accentColor : Color.orange)
                        Text(presentation.recorderAccessibilityLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(presentation.recorderAccessibilityLabel)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsCopy.hotkeysSectionTitle)
        .padding()
    }

    @ViewBuilder
    private func row(for item: SettingsCommandTreeItem) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let symbol = item.symbolName {
                        Image(systemName: symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                    }
                    Text(item.actionTitle)
                        .foregroundStyle(item.isAvailable ? .primary : .secondary)
                    if !item.isAvailable {
                        Text("(\(SettingsCopy.unavailable))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                KeySequenceBadgeView(item: item)
            }
        } else {
            HStack(spacing: 10) {
                if let symbol = item.symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)
                }
                Text(item.actionTitle)
                    .foregroundStyle(item.isAvailable ? .primary : .secondary)
                if !item.isAvailable {
                    Text("(\(SettingsCopy.unavailable))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                KeySequenceBadgeView(item: item)
            }
        }
    }
}

/// Centralizes user-visible text so a strings catalog can replace the default
/// development-language values without changing view or state-machine logic.
public enum SettingsCopy {
    public static let windowTitle = localized("My Mac X Settings")
    public static let settingsSections = localized("Settings sections")
    public static let searchPlaceholder = localized("Search Settings")
    public static let clearSearch = localized("Clear search")
    public static let noSearchResults = localized("No results found")
    public static let quickActionsMenuTitle = localized("Quick Actions")
    public static let noFocusedEligibleWindow = localized("No focused eligible window.")
    public static let unsupportedFocusedWindow = localized("The focused window does not support this action.")
    public static let experimentalActionUnavailable = localized("This action is experimental and unavailable.")
    public static let disabledActionUnavailable = localized("This action is disabled.")
    public static let unsupportedSystemActionUnavailable = localized("This action is unavailable on this version of macOS.")
    public static let actionRequiresMovableWindow = localized("This action requires a movable window.")
    public static let nativeFullScreenStateUnavailable = localized("Native Full Screen state is unavailable for this window.")

    public static let generalSectionTitle = localized("General")
    public static let snappingSectionTitle = localized("Snapping")
    public static let hotkeysSectionTitle = localized("Hotkeys & Super Mode")
    public static let layoutsSectionTitle = localized("Layout Library")
    public static let displaysSectionTitle = localized("Display Profiles")
    public static let appRulesSectionTitle = localized("App Rules")
    public static let transferSectionTitle = localized("Import & Export")
    public static let aboutSectionTitle = localized("About & Diagnostics")
    public static let permissionsSectionTitle = localized("Permissions")
    public static let startupSectionTitle = localized("Startup")
    public static let accessibilityPermission = localized("Accessibility")
    public static let inputMonitoringPermission = localized("Input Monitoring")
    public static let permissionGranted = localized("Granted")
    public static let permissionRequired = localized("Required")
    public static let accessibilityNotRequested = localized("Accessibility permission has not been requested.")
    public static let accessibilityDenied = localized("Accessibility permission was denied. Enable it in System Settings to place windows.")
    public static let accessibilityGranted = localized("Accessibility permission is granted.")
    public static let accessibilityRevoked = localized("Accessibility permission was removed. Re-enable it in System Settings to place windows.")
    public static let openSystemSettings = localized("Open System Settings…")
    public static let openSystemSettingsHint = localized("Opens System Settings so you can grant or restore Accessibility permission.")
    public static let launchAtLogin = localized("Launch My Mac X at login")
    public static let enableSnapping = localized("Enable Snapping")
    public static let trigger = localized("Trigger")
    public static let notchTrigger = localized("Notch Trigger")
    public static let topCenterTrigger = localized("Top-center Trigger")
    public static let activationDelay = localized("Activation delay")
    public static let showPlacementPreview = localized("Show Placement Preview")
    public static let reduceVisualEffects = localized("Reduce visual effects")
    public static let systemReducedEffectsNotice = localized("Your Mac accessibility settings are also reducing visual effects.")
    public static let editHotkeys = localized("Edit Hotkeys…")
    public static let editSuperMode = localized("Edit Super Mode…")
    public static let recordShortcut = localized("Record shortcut")
    public static let recordingShortcut = localized("Recording shortcut. Press Escape to cancel.")
    public static let shortcutRecorderUnavailable = localized("Shortcut recording is unavailable until Input Monitoring is granted.")
    public static let hotkeyEditorHint = localized("Opens the accessible shortcut recorder and command-tree editor.")
    public static let hotkeyValidationError = localized("Shortcut conflict")
    public static let commandTreeTitle = localized("Command Tree")
    public static let hotkeyEmptyState = localized("No Super Mode commands are configured.")
    public static let unavailable = localized("Unavailable")
    public static let layoutLibraryTitle = localized("Custom Layouts")
    public static let addLayout = localized("Add Layout")
    public static let newLayoutName = localized("New Layout")
    public static let layoutsEmptyState = localized("No custom layouts. Built-in layouts remain available.")
    public static let splitColumns = localized("Split into Columns")
    public static let splitRows = localized("Split into Rows")
    public static let mergeRegions = localized("Merge All Regions")
    public static let delete = localized("Delete")
    public static let layoutValidationError = localized("Layout validation error")
    public static let displayProfilesTitle = localized("Per-display Layouts")
    public static let addConnectedDisplays = localized("Add Connected Displays")
    public static let displayProfilesEmptyState = localized("No display profiles. Default layouts and gaps apply.")
    public static let displayIdentifier = localized("Stable Display ID")
    public static let stableDisplayID = localized("Stable Display ID")
    public static let layoutRegion = localized("Layout Region")
    public static let layoutRegions = localized("Layout Regions")
    public static let nativeFullScreen = localized("Native Full Screen")
    public static let gap = localized("Gap")
    public static let assignedLayouts = localized("Assigned layouts")
    public static let displayConnected = localized("Connected")
    public static let displayDisconnected = localized("Disconnected — profile will be restored on reconnect")
    public static let defaultAppBehavior = localized("Default Behavior")
    public static let unmatchedApplications = localized("Applications without a rule")
    public static let included = localized("Included")
    public static let excluded = localized("Excluded")
    public static let bundleIdentifier = localized("Bundle identifier, for example com.example.App")
    public static let addIncludedRule = localized("Add Included")
    public static let addExcludedRule = localized("Add Excluded")
    public static let configurationBackupTitle = localized("Configuration Backup")
    public static let configurationBackupExplanation = localized("Export a portable backup or import a validated configuration. Permissions and machine-specific data are never included.")
    public static let importConfiguration = localized("Import…")
    public static let exportConfiguration = localized("Export…")
    public static let appVersion = localized("App version")
    public static let operatingSystem = localized("macOS")
    public static let diagnosticsTitle = localized("Diagnostics")
    public static let eventTap = localized("Event Tap")
    public static let redactedDiagnosticsReport = localized("Redacted diagnostics report")
    public static let copyDiagnostics = localized("Copy Diagnostics Report")

    public static let edgeSnapSectionTitle = localized("Edge Snap Zones")
    public static let edgeSnapZoneMapTitle = localized("Perimeter Zone Map")
    public static let resetAllZonesToDefaults = localized("Reset All Zones to Defaults")
    public static let resetZoneToDefault = localized("Reset to Default")
    public static let seamGatingTitle = localized("Multi-Display Seam Gating")
    public static let seamGatingExplanation = localized("Prevent accidental docking across connected screens by gating fast pointer movement across shared boundaries.")
    public static let seamCrossingSpeedThreshold = localized("Seam Crossing Speed Threshold")
    public static let enableEdgeSnapZone = localized("Enable Zone")
    public static let disableEdgeSnapZone = localized("Disable Zone")
    public static let systemTilingStandDownNotice = localized("macOS System Tiling is active. Edge snapping stands down on perimeter edges.")
    public static let systemTilingStandDownBannerTitle = localized("macOS System Tiling Active")
    public static let systemTilingStandDownBannerMessage = localized("macOS system tiling owns screen edges — Edge Snap stands down on outer edges. Shared display seams remain active.")
    public static let edgeSnapZoneMapCaption = localized("Drag a window to an edge or corner to trigger the assigned Window Action.")
    public static let partitionCountTitle = localized("Partitions")
    public static let selectZonePrompt = localized("Select a perimeter zone to configure its assigned actions.")

    public static func partitionAreaLabel(index: Int, total: Int) -> String {
        localized("Area \(index + 1) of \(total)")
    }

    public static func zoneTitle(_ zone: EdgeSnapZone) -> String {
        switch zone {
        case .topLeft: localized("Top-Left Corner")
        case .top: localized("Top Edge")
        case .topRight: localized("Top-Right Corner")
        case .left: localized("Left Edge")
        case .right: localized("Right Edge")
        case .bottomLeft: localized("Bottom-Left Corner")
        case .bottom: localized("Bottom Edge")
        case .bottomRight: localized("Bottom-Right Corner")
        }
    }

    public static func regionCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 Layout Region", comment: "Single Layout Region in custom layout")
        }
        return String(localized: "\(count) Layout Regions", comment: "Number of Layout Regions in custom layout")
    }

    public static func unavailableAction(_ reason: ActionUnavailability) -> String {
        switch reason {
        case .disabled: disabledActionUnavailable
        case .experimental: experimentalActionUnavailable
        case .unsupportedOnCurrentSystem: unsupportedSystemActionUnavailable
        }
    }

    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .main, comment: "Settings UI")
    }
}

public enum SettingsAccessibilityID {
    public static let snappingEnabled = "settings.snapping.enabled"
    public static let snappingTrigger = "settings.snapping.trigger"
    public static let snappingDwell = "settings.snapping.dwell"
    public static let reducedEffects = "settings.snapping.reduced-effects"
    public static let launchAtLogin = "settings.general.launch-at-login"
    public static let hotkeyCommandTree = "settings.hotkeys.command-tree"
    public static let layoutLibrary = "settings.layouts.library"
    public static let displayProfiles = "settings.displays.profiles"
    public static let appRuleBundleIdentifier = "settings.app-rules.bundle-identifier"
    public static let diagnostics = "settings.about.diagnostics"

    public static let zoneMapPicker = "settings.snapping.zone-map"
    public static let zoneMapResetAll = "settings.snapping.zone-map.reset-all"
    public static let zoneMapResetZone = "settings.snapping.zone-map.reset-zone"
    public static let zoneMapPartitionPicker = "settings.snapping.zone-map.partition-picker"
    public static let systemTilingBanner = "settings.snapping.system-tiling-banner"

    public static func zoneCell(_ zone: EdgeSnapZone) -> String {
        "settings.snapping.zone-cell.\(zone.rawValue)"
    }

    public static func section(_ section: SettingsSection) -> String {
        "settings.section.\(section.rawValue)"
    }
}
