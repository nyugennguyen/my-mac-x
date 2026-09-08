import AppKit
import Combine
import SwiftUI

struct SettingsHotkeyPresentation: Equatable {
    let visibleLabel: String
    let accessibilityLabel: String
}

private extension HotkeyChordPresentation {
    var settingsPresentation: SettingsHotkeyPresentation {
        let modifierGlyphs = modifierSymbols.map { symbol in
            switch symbol {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }.joined()
        let visibleKey = usedHardwareCodeFallback ? String(localized: "Unknown key") : Self.keyCapLabel(keyLabel)
        let accessibleKey = usedHardwareCodeFallback ? String(localized: "Unknown key") : keyLabel
        let modifierNames = modifierSymbols.map { symbol in
            switch symbol {
            case .control: String(localized: "Control")
            case .option: String(localized: "Option")
            case .shift: String(localized: "Shift")
            case .command: String(localized: "Command")
            }
        }
        return SettingsHotkeyPresentation(
            visibleLabel: modifierGlyphs + (modifierGlyphs.isEmpty || visibleKey.count == 1 ? "" : " ") + visibleKey,
            accessibilityLabel: (modifierNames + [accessibleKey]).joined(separator: " ")
        )
    }

    private static func keyCapLabel(_ label: String) -> String {
        switch label {
        case "Left Arrow": "←"
        case "Right Arrow": "→"
        case "Down Arrow": "↓"
        case "Up Arrow": "↑"
        default: label
        }
    }
}

@MainActor
final class SuperModeSettingsWindowController {
    typealias Load = @MainActor @Sendable () async -> HotkeySettings
    typealias Apply = @MainActor @Sendable (SuperModeConfiguration) async -> SuperModeConfigurationApplyResult
    typealias HasInputMonitoringAccess = @MainActor @Sendable () -> Bool
    typealias RequestInputMonitoringAccess = @MainActor @Sendable () -> Bool
    typealias RetrySuperModeRuntime = @MainActor @Sendable () -> Void

    private let model: SuperModeSettingsModel
    private var window: NSWindow?
    private var hasRequestedInitialLoad = false

    init(
        actionRegistry: ActionRegistry,
        hasInputMonitoringAccess: @escaping HasInputMonitoringAccess = { true },
        requestInputMonitoringAccess: @escaping RequestInputMonitoringAccess = { true },
        retrySuperModeRuntime: @escaping RetrySuperModeRuntime = {},
        presenter: any HotkeyChordPresenting = HotkeyChordPresenter(labelResolver: MacOSHotkeyKeyLabelResolver()),
        load: @escaping Load,
        apply: @escaping Apply,
        recorder: (any HotkeyRecording)? = nil
    ) {
        model = SuperModeSettingsModel(
            actionRegistry: actionRegistry,
            hasInputMonitoringAccess: hasInputMonitoringAccess,
            requestInputMonitoringAccess: requestInputMonitoringAccess,
            retrySuperModeRuntime: retrySuperModeRuntime,
            presenter: presenter,
            load: load,
            apply: apply,
            recorder: recorder
        )
    }

    func present() {
        let settingsWindow = window ?? makeWindow()
        window = settingsWindow
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        guard !hasRequestedInitialLoad else { return }
        hasRequestedInitialLoad = true
        Task { await model.reload() }
    }

    var windowForTesting: NSWindow? { window }
    var modelForTesting: SuperModeSettingsModel { model }

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

    func refreshInputMonitoringState() {
        model.refreshInputMonitoringState()
    }

    private func makeWindow(dynamicTypeSize: DynamicTypeSize? = nil) -> NSWindow {
        let rootView = SuperModeSettingsView(model: model)
        let controller: NSViewController
        if let dynamicTypeSize {
            controller = NSHostingController(rootView: rootView.dynamicTypeSize(dynamicTypeSize))
        } else {
            controller = NSHostingController(rootView: rootView)
        }
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Super Mode Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 520))
        window.minSize = NSSize(width: 640, height: 440)
        window.isReleasedWhenClosed = false
        window.center()
        window.setAccessibilityLabel(String(localized: "Super Mode Settings"))
        return window
    }
}

@MainActor
final class SuperModeSettingsModel: ObservableObject {
    struct BindingDraft: Identifiable, Equatable {
        let id: UUID
        var hardwareKeyCodes: [UInt16]
        var actionID: ActionID

        init(
            id: UUID = UUID(),
            hardwareKeyCodes: [UInt16],
            actionID: ActionID
        ) {
            self.id = id
            self.hardwareKeyCodes = hardwareKeyCodes
            self.actionID = actionID
        }
    }

    struct ActionOption: Identifiable, Equatable {
        let id: ActionID
        let title: String
        let isAvailable: Bool
    }

    enum Status: Equatable {
        case idle
        case loading
        case saving
        case saved
        case error(String)
    }

    enum InputMonitoringState: Equatable {
        case required
        case granted
    }

    typealias Load = SuperModeSettingsWindowController.Load
    typealias Apply = SuperModeSettingsWindowController.Apply

    @Published var prefix = SuperModeConfiguration.default.prefix
    @Published var timeoutMilliseconds = SuperModeConfiguration.defaultTimeoutMilliseconds
    @Published var bindings: [BindingDraft] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var isRecordingPrefix = false
    @Published private(set) var inputMonitoringState: InputMonitoringState

    let actionOptions: [ActionOption]

    private let load: Load
    private let apply: Apply
    private let recorder: any HotkeyRecording
    private let hasInputMonitoringAccess: SuperModeSettingsWindowController.HasInputMonitoringAccess
    private let requestInputMonitoringAccess: SuperModeSettingsWindowController.RequestInputMonitoringAccess
    private let retrySuperModeRuntime: SuperModeSettingsWindowController.RetrySuperModeRuntime
    private let presenter: any HotkeyChordPresenting
    private var recorderUpdatesTask: Task<Void, Never>?

    init(
        actionRegistry: ActionRegistry,
        hasInputMonitoringAccess: @escaping SuperModeSettingsWindowController.HasInputMonitoringAccess = { true },
        requestInputMonitoringAccess: @escaping SuperModeSettingsWindowController.RequestInputMonitoringAccess = { true },
        retrySuperModeRuntime: @escaping SuperModeSettingsWindowController.RetrySuperModeRuntime = {},
        presenter: any HotkeyChordPresenting = HotkeyChordPresenter(labelResolver: MacOSHotkeyKeyLabelResolver()),
        load: @escaping Load,
        apply: @escaping Apply,
        recorder: (any HotkeyRecording)? = nil
    ) {
        self.load = load
        self.apply = apply
        self.hasInputMonitoringAccess = hasInputMonitoringAccess
        self.requestInputMonitoringAccess = requestInputMonitoringAccess
        self.retrySuperModeRuntime = retrySuperModeRuntime
        self.presenter = presenter
        inputMonitoringState = hasInputMonitoringAccess() ? .granted : .required
        self.recorder = recorder ?? HotkeyRecorder(input: AppKitHotkeyRecorderInputAdapter())

        let windowActions = actionRegistry.actions.map {
            ActionOption(
                id: $0.id,
                title: $0.title,
                isAvailable: $0.availability == .available
            )
        }
        let appActions = [
            ActionOption(id: .openSettings, title: String(localized: "Open Settings"), isAvailable: true),
            ActionOption(id: .toggleGaps, title: String(localized: "Toggle Gaps"), isAvailable: true),
            ActionOption(id: .selectProfile, title: String(localized: "Select Profile"), isAvailable: true),
        ]
        actionOptions = windowActions + appActions
    }

    deinit {
        recorderUpdatesTask?.cancel()
    }

    func reload() async {
        guard status != .loading, status != .saving else { return }
        status = .loading
        let settings = await load()
        setDraft(settings.superModeConfiguration)
        refreshInputMonitoringState()
        status = .idle
    }

    func requestInputMonitoring() async {
        let granted = requestInputMonitoringAccess()
        inputMonitoringState = granted || hasInputMonitoringAccess() ? .granted : .required
        if inputMonitoringState == .granted {
            retrySuperModeRuntime()
        }
    }

    func refreshInputMonitoringState() {
        inputMonitoringState = hasInputMonitoringAccess() ? .granted : .required
    }

    func save() async {
        guard status != .saving else { return }
        status = .saving
        let result = await apply(configuration)
        switch result {
        case .applied:
            status = .saved
        case let .rejected(failure):
            status = .error(Self.copy(for: failure))
        case let .persistenceFailed(failure):
            status = .error(Self.copy(for: failure))
        }
    }

    func loadTestPreset() {
        prefix = HotkeyChord(hardwareKeyCode: 49, modifiers: [.control])
        timeoutMilliseconds = 1_000
        bindings = [
            BindingDraft(hardwareKeyCodes: [4], actionID: .leftHalf),
            BindingDraft(hardwareKeyCodes: [37], actionID: .rightHalf),
            BindingDraft(hardwareKeyCodes: [46], actionID: .maximize),
            BindingDraft(hardwareKeyCodes: [15], actionID: .restore),
            BindingDraft(hardwareKeyCodes: [2, 45], actionID: .moveDisplayNext),
            BindingDraft(hardwareKeyCodes: [2, 35], actionID: .moveDisplayPrevious),
            BindingDraft(hardwareKeyCodes: [8, 37], actionID: .cycleLeftEdge),
            BindingDraft(hardwareKeyCodes: [1], actionID: .openSettings),
        ]
        status = .idle
    }

    func addBinding() {
        bindings.append(
            BindingDraft(
                hardwareKeyCodes: [0],
                actionID: actionOptions.first(where: \.isAvailable)?.id ?? .maximize
            )
        )
    }

    func deleteBinding(id: UUID) {
        bindings.removeAll { $0.id == id }
    }

    func setBindingKeyCode(id: UUID, level: Int, keyCode: UInt16) {
        guard let index = bindings.firstIndex(where: { $0.id == id }),
              bindings[index].hardwareKeyCodes.indices.contains(level) else { return }
        bindings[index].hardwareKeyCodes[level] = keyCode
    }

    func setBindingLevelCount(id: UUID, count: Int) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        if count == 1 {
            bindings[index].hardwareKeyCodes = [bindings[index].hardwareKeyCodes.first ?? 0]
        } else if count == 2, bindings[index].hardwareKeyCodes.count == 1 {
            bindings[index].hardwareKeyCodes.append(0)
        }
    }

    func setBindingAction(id: UUID, actionID: ActionID) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[index].actionID = actionID
    }

    func setPrefixModifier(_ modifier: HotkeyModifiers, enabled: Bool) {
        var modifiers = prefix.modifiers
        if enabled {
            modifiers.insert(modifier)
        } else {
            modifiers.remove(modifier)
        }
        prefix = HotkeyChord(hardwareKeyCode: prefix.hardwareKeyCode, modifiers: modifiers)
    }

    var prefixPresentation: SettingsHotkeyPresentation {
        presenter.present(prefix).settingsPresentation
    }

    func bindingKeyPresentation(for binding: BindingDraft, level: Int) -> SettingsHotkeyPresentation {
        guard binding.hardwareKeyCodes.indices.contains(level) else {
            return SettingsHotkeyPresentation(
                visibleLabel: String(localized: "Unknown key"),
                accessibilityLabel: String(localized: "Unknown key")
            )
        }
        return presenter.present(
            HotkeyChord(hardwareKeyCode: binding.hardwareKeyCodes[level], modifiers: [])
        ).settingsPresentation
    }

    func keyPresentation(for hardwareKeyCode: UInt16) -> SettingsHotkeyPresentation {
        presenter.present(HotkeyChord(hardwareKeyCode: hardwareKeyCode, modifiers: [])).settingsPresentation
    }

    func recordPrefix() {
        recorderUpdatesTask?.cancel()
        recorderUpdatesTask = Task { [weak self, recorder] in
            let updates = await recorder.updates
            await recorder.begin()
            for await update in updates {
                guard let self else { return }
                switch update {
                case .recording:
                    isRecordingPrefix = true
                case let .captured(chord):
                    prefix = chord
                    isRecordingPrefix = false
                    return
                case .cancelled, .cleared, .idle:
                    isRecordingPrefix = false
                    if update != .idle { return }
                }
            }
        }
    }

    var configuration: SuperModeConfiguration {
        SuperModeConfiguration(
            prefix: prefix,
            timeoutMilliseconds: timeoutMilliseconds,
            commandBindings: bindings.map {
                SuperModeCommandBinding(
                    hardwareKeyCodes: $0.hardwareKeyCodes,
                    actionID: $0.actionID
                )
            }
        )
    }

    private func setDraft(_ configuration: SuperModeConfiguration) {
        prefix = configuration.prefix
        timeoutMilliseconds = configuration.timeoutMilliseconds
        bindings = configuration.commandBindings.map {
            BindingDraft(hardwareKeyCodes: $0.hardwareKeyCodes, actionID: $0.actionID)
        }
    }

    private static func copy(for failure: SuperModeConfigurationFailure) -> String {
        switch failure {
        case .invalidTimeout:
            return String(localized: "Timeout must be between 250 and 5,000 milliseconds.")
        case .invalidPrefix:
            return String(localized: "Prefix must include a supported key and at least one modifier.")
        case .reservedPrefix:
            return String(localized: "That prefix is reserved by macOS. Choose another shortcut.")
        case .hotkeyConflict:
            return String(localized: "That prefix is already assigned to another hotkey.")
        case let .invalidPath(index, _):
            return String(localized: "Binding \(index + 1) must contain one or two keys.")
        case let .invalidHardwareKeyCode(index, _):
            return String(localized: "Binding \(index + 1) contains an unsupported key.")
        case let .reservedSequenceKey(index, _):
            return String(localized: "Binding \(index + 1) cannot use Escape.")
        case let .invalidAction(index, _):
            return String(localized: "Binding \(index + 1) has an unavailable action.")
        case .duplicatePath:
            return String(localized: "Two bindings use the same key sequence.")
        case .ambiguousRoot:
            return String(localized: "A one-key binding cannot share its first key with a two-key binding.")
        }
    }

    private static func copy(for failure: SettingsSaveFailure) -> String {
        switch failure {
        case .structurallyInvalid:
            return String(localized: "Settings could not be saved because the document is invalid.")
        case .documentNotWritable:
            return String(localized: "Settings could not be written. Check file permissions and try again.")
        case .atomicReplacementFailed:
            return String(localized: "Settings could not be replaced safely. Try again.")
        case .recoveryRequired:
            return String(localized: "Settings need recovery before changes can be saved.")
        }
    }
}

private struct SuperModeSettingsView: View {
    @ObservedObject var model: SuperModeSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Super Mode")
                .font(.title2.weight(.semibold))
            Text("Hold the prefix, then type a one- or two-key command sequence.")
                .foregroundStyle(.secondary)

            Form {
                Section("Input Monitoring") {
                    if model.inputMonitoringState == .granted {
                        Label("Granted — Super Mode can receive the Prefix.", systemImage: "checkmark.circle")
                    } else {
                        Text("Super Mode needs Input Monitoring to receive and safely consume Prefix sequences while you use other apps.")
                        Button("Enable Input Monitoring") {
                            Task { await model.requestInputMonitoring() }
                        }
                        .accessibilityHint("Requests macOS Input Monitoring access, then retries Super Mode.")
                    }
                }

                Section("Prefix") {
                    HStack {
                        Text("Shortcut")
                        Text(model.prefixPresentation.visibleLabel)
                            .font(.body.monospaced())
                            .accessibilityLabel(model.prefixPresentation.accessibilityLabel)
                        Spacer()
                        Button(model.isRecordingPrefix ? "Recording…" : "Record Prefix") {
                            model.recordPrefix()
                        }
                        .disabled(model.isRecordingPrefix)
                        .accessibilityHint("Press the complete prefix shortcut after recording starts.")
                    }
                    HStack {
                        modifierToggle("Control", modifier: .control)
                        modifierToggle("Option", modifier: .option)
                        modifierToggle("Shift", modifier: .shift)
                        modifierToggle("Command", modifier: .command)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Prefix modifiers")

                    Stepper(
                        "Sequence timeout: \(model.timeoutMilliseconds) ms",
                        value: $model.timeoutMilliseconds,
                        in: SuperModeConfiguration.minimumTimeoutMilliseconds...SuperModeConfiguration.maximumTimeoutMilliseconds,
                        step: 50
                    )
                    .accessibilityLabel("Sequence timeout in milliseconds")
                }

                Section("Commands") {
                    if model.bindings.isEmpty {
                        Text("No commands yet. Add a binding or load the test preset.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.bindings) { binding in
                        BindingRow(model: model, binding: binding)
                    }
                    HStack {
                        Button("Add Binding") { model.addBinding() }
                        Button("Load Test Preset") { model.loadTestPreset() }
                            .accessibilityHint("Replaces the unsaved draft with the Sprint 5 test bindings.")
                    }
                }
            }
            .formStyle(.grouped)

            statusView

            HStack {
                Button("Reload") { Task { await model.reload() } }
                    .disabled(isBusy)
                    .accessibilityHint("Discards unsaved changes and reloads persisted settings.")
                Spacer()
                Button("Save") { Task { await model.save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 400)
    }

    private var isBusy: Bool {
        model.status == .loading || model.status == .saving
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Loading settings…")
                .accessibilityLabel("Loading settings")
        case .saving:
            ProgressView("Saving settings…")
                .accessibilityLabel("Saving settings")
        case .saved:
            Label("Settings saved.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Settings saved")
        case let .error(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .accessibilityLabel("Settings error: \(message)")
        }
    }

    private func modifierToggle(_ title: String, modifier: HotkeyModifiers) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { model.prefix.modifiers.contains(modifier) },
                set: { model.setPrefixModifier(modifier, enabled: $0) }
            )
        )
        .toggleStyle(.checkbox)
    }
}

private struct BindingRow: View {
    @ObservedObject var model: SuperModeSettingsModel
    let binding: SuperModeSettingsModel.BindingDraft

    var body: some View {
        HStack(spacing: 10) {
            Picker("Keys", selection: levelCount) {
                Text("1 key").tag(1)
                Text("2 keys").tag(2)
            }
            .labelsHidden()
            .frame(width: 80)
            .accessibilityLabel("Sequence length")

            ForEach(binding.hardwareKeyCodes.indices, id: \.self) { level in
                Picker("Key \(level + 1)", selection: keyCode(level)) {
                    ForEach(UInt16(0)..<UInt16(127), id: \.self) { keyCode in
                        Text(model.keyPresentation(for: keyCode).visibleLabel).tag(keyCode)
                    }
                }
                .frame(width: 104)
                .accessibilityLabel("Command key \(level + 1)")
                .accessibilityValue(model.bindingKeyPresentation(for: binding, level: level).accessibilityLabel)
            }

            Picker("Action", selection: actionID) {
                ForEach(model.actionOptions) { option in
                    Text(option.isAvailable ? option.title : "\(option.title) — Unavailable")
                        .tag(option.id)
                        .disabled(!option.isAvailable)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Action")

            Button("Delete", systemImage: "minus.circle", role: .destructive) {
                model.deleteBinding(id: binding.id)
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Delete binding")
        }
    }

    private var levelCount: Binding<Int> {
        Binding(
            get: { binding.hardwareKeyCodes.count },
            set: { model.setBindingLevelCount(id: binding.id, count: $0) }
        )
    }

    private func keyCode(_ level: Int) -> Binding<UInt16> {
        Binding(
            get: { binding.hardwareKeyCodes[level] },
            set: { model.setBindingKeyCode(id: binding.id, level: level, keyCode: $0) }
        )
    }
    private var actionID: Binding<ActionID> {
        Binding(
            get: { binding.actionID },
            set: { model.setBindingAction(id: binding.id, actionID: $0) }
        )
    }
}

@MainActor
final class GlobalHotkeySettingsWindowController {
    typealias Load = @MainActor @Sendable () async -> HotkeySettings
    typealias Apply = @MainActor @Sendable (HotkeySettings) async -> HotkeyRuntimeUpdateResult
    private let model: GlobalHotkeySettingsModel
    private var window: NSWindow?

    init(
        actionRegistry: ActionRegistry,
        load: @escaping Load,
        apply: @escaping Apply,
        recorder: (any HotkeyRecording)? = nil,
        presenter: any HotkeyChordPresenting = HotkeyChordPresenter(labelResolver: MacOSHotkeyKeyLabelResolver())
    ) {
        model = GlobalHotkeySettingsModel(
            actionRegistry: actionRegistry,
            load: load,
            apply: apply,
            recorder: recorder,
            presenter: presenter
        )
    }

    func present() {
        let window = window ?? makeWindow()
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Task { await model.reload() }
    }

    var modelForTesting: GlobalHotkeySettingsModel { model }
    var windowForTesting: NSWindow? { window }

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
        let rootView = GlobalHotkeySettingsView(model: model)
        let controller: NSViewController
        if let dynamicTypeSize {
            controller = NSHostingController(rootView: rootView.dynamicTypeSize(dynamicTypeSize))
        } else {
            controller = NSHostingController(rootView: rootView)
        }
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Global Hotkey Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 520))
        window.minSize = NSSize(width: 640, height: 440)
        window.isReleasedWhenClosed = false
        window.center()
        window.setAccessibilityLabel(String(localized: "Global Hotkey Settings"))
        return window
    }
}

@MainActor
final class GlobalHotkeySettingsModel: ObservableObject {
    enum Status: Equatable { case idle, loading, saving, saved, error(String) }
    @Published private(set) var settings = HotkeySettings(bindings: [])
    @Published private(set) var status: Status = .idle
    @Published private(set) var recordingBindingID: UUID?
    let actions: [ActionDescriptor]
    private let load: GlobalHotkeySettingsWindowController.Load
    private let apply: GlobalHotkeySettingsWindowController.Apply
    private let validator: any HotkeyConflictValidating
    private let recorder: any HotkeyRecording
    private let presenter: any HotkeyChordPresenting
    private var recorderTask: Task<Void, Never>?

    init(actionRegistry: ActionRegistry, load: @escaping GlobalHotkeySettingsWindowController.Load, apply: @escaping GlobalHotkeySettingsWindowController.Apply, validator: any HotkeyConflictValidating = HotkeyConflictDetector(), recorder: (any HotkeyRecording)? = nil, presenter: any HotkeyChordPresenting = HotkeyChordPresenter(labelResolver: MacOSHotkeyKeyLabelResolver())) {
        actions = actionRegistry.actions
        self.load = load
        self.apply = apply
        self.validator = validator
        self.recorder = recorder ?? HotkeyRecorder(input: AppKitHotkeyRecorderInputAdapter())
        self.presenter = presenter
    }

    deinit { recorderTask?.cancel() }

    func reload() async {
        guard status != .saving else { return }
        status = .loading
        settings = await load()
        status = .idle
    }

    func addBinding() {
        replaceBindings(settings.bindings + [HotkeyBinding(id: UUID(), hardwareKeyCode: 0, modifiers: [.control], actionID: actions.first(where: { $0.availability == .available })?.id ?? .maximize)])
    }

    func deleteBinding(_ id: UUID) { replaceBindings(settings.bindings.filter { $0.id != id }) }

    func setAction(_ actionID: ActionID, for id: UUID) {
        replaceBinding(id) { HotkeyBinding(id: $0.id, hardwareKeyCode: $0.hardwareKeyCode, modifiers: $0.modifiers, actionID: actionID) }
    }

    func record(_ id: UUID) {
        recorderTask?.cancel()
        recordingBindingID = id
        recorderTask = Task { [weak self, recorder] in
            let updates = await recorder.updates
            await recorder.begin()
            for await update in updates {
                guard let self else { return }
                switch update {
                case let .captured(chord): self.applyRecorded(chord, to: id); self.recordingBindingID = nil; return
                case .cancelled, .cleared: self.recordingBindingID = nil; return
                case .idle, .recording: continue
                }
            }
        }
    }

    func presentation(for chord: HotkeyChord) -> SettingsHotkeyPresentation {
        presenter.present(chord).settingsPresentation
    }

    func save() async {
        for binding in settings.bindings {
            let result = validator.validate(HotkeyValidationRequest(editedBindingID: binding.id, actionID: binding.actionID, candidate: binding.chord, existingBindings: settings.bindings))
            guard result == .valid else { status = .error(Self.validationCopy(result)); return }
        }
        status = .saving
        switch await apply(settings) {
        case .applied: status = .saved
        case .saveFailed: status = .error("The Hotkey settings could not be saved.")
        case .rolledBackAfterRegistrationFailure: status = .error("A shortcut is unavailable, so the previous Hotkeys were restored.")
        case .recoveryRequired: status = .error("Hotkey recovery is required before saving again.")
        }
    }

    private func applyRecorded(_ chord: HotkeyChord, to id: UUID) {
        guard let binding = settings.bindings.first(where: { $0.id == id }) else { return }
        let result = validator.validate(HotkeyValidationRequest(editedBindingID: id, actionID: binding.actionID, candidate: chord, existingBindings: settings.bindings))
        guard result == .valid else { status = .error(Self.validationCopy(result)); return }
        replaceBinding(id) { HotkeyBinding(id: $0.id, hardwareKeyCode: chord.hardwareKeyCode, modifiers: chord.modifiers, actionID: $0.actionID) }
        status = .idle
    }

    private func replaceBinding(_ id: UUID, transform: (HotkeyBinding) -> HotkeyBinding) { replaceBindings(settings.bindings.map { $0.id == id ? transform($0) : $0 }) }
    private func replaceBindings(_ bindings: [HotkeyBinding]) { settings = HotkeySettings(bindings: bindings, superModeConfiguration: settings.superModeConfiguration) }
    private static func validationCopy(_ result: HotkeyValidationResult) -> String {
        switch result {
        case .valid: ""
        case .duplicate: "Two bindings use the same shortcut."
        case .reserved: "This shortcut is reserved by macOS."
        case .invalid(.requiresModifier): "Add Command, Option, Control, or Shift."
        case .invalid: "This shortcut cannot be used."
        }
    }
}

private struct GlobalHotkeySettingsView: View {
    @ObservedObject var model: GlobalHotkeySettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Hotkeys").font(.title2).bold()
            Text("Record keyboard shortcuts for Window Actions.").foregroundStyle(.secondary)
            List(model.settings.bindings) { binding in
                HStack {
                    Button(model.recordingBindingID == binding.id ? "Recording…" : "Record shortcut") { model.record(binding.id) }
                        .accessibilityLabel(model.recordingBindingID == binding.id ? "Recording shortcut" : "Record shortcut")
                    let presentation = model.presentation(for: binding.chord)
                    Text(presentation.visibleLabel)
                        .font(.body.monospaced())
                        .accessibilityLabel(presentation.accessibilityLabel)
                    Picker("Action", selection: Binding(get: { binding.actionID }, set: { model.setAction($0, for: binding.id) })) {
                        ForEach(model.actions, id: \.id) { action in Text(action.title).tag(action.id).disabled(action.availability != .available) }
                    }
                    Button("Delete", systemImage: "minus.circle", role: .destructive) { model.deleteBinding(binding.id) }.labelStyle(.iconOnly).accessibilityLabel("Delete binding")
                }
            }
            if case let .error(message) = model.status { Text(message).foregroundStyle(.red).accessibilityLabel("Hotkey error: \(message)") }
            HStack { Button("Add Hotkey", systemImage: "plus") { model.addBinding() }; Spacer(); Button("Save") { Task { await model.save() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(minWidth: 640, minHeight: 440)
    }

}
