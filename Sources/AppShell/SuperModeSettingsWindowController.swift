import AppKit
import Combine
import SwiftUI

struct SettingsHotkeyPresentation: Equatable {
    let visibleLabel: String
    let accessibilityLabel: String
}

extension HotkeyChordPresentation {
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

    static func keyCapLabel(_ label: String) -> String {
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
final class SuperModeSettingsWindowController: NSObject, NSWindowDelegate {
    typealias Load = @MainActor @Sendable () async -> HotkeySettings
    typealias Apply = @MainActor @Sendable (SuperModeConfiguration) async -> SuperModeConfigurationApplyResult
    typealias HasInputMonitoringAccess = @MainActor @Sendable () -> Bool
    typealias RequestInputMonitoringAccess = @MainActor @Sendable () -> Bool
    typealias RetrySuperModeRuntime = @MainActor @Sendable () -> Void
    typealias SuspendHotkeys = @MainActor @Sendable () async -> Void
    typealias ResumeHotkeys = @MainActor @Sendable () async -> Void

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
        recorder: (any HotkeyRecording)? = nil,
        suspendHotkeys: SuspendHotkeys? = nil,
        resumeHotkeys: ResumeHotkeys? = nil
    ) {
        model = SuperModeSettingsModel(
            actionRegistry: actionRegistry,
            hasInputMonitoringAccess: hasInputMonitoringAccess,
            requestInputMonitoringAccess: requestInputMonitoringAccess,
            retrySuperModeRuntime: retrySuperModeRuntime,
            presenter: presenter,
            load: load,
            apply: apply,
            recorder: recorder,
            suspendHotkeys: suspendHotkeys,
            resumeHotkeys: resumeHotkeys
        )
        super.init()
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
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecordingPrefix()
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
    private let suspendHotkeys: SuperModeSettingsWindowController.SuspendHotkeys?
    private let resumeHotkeys: SuperModeSettingsWindowController.ResumeHotkeys?
    private var recorderUpdatesTask: Task<Void, Never>?

    init(
        actionRegistry: ActionRegistry,
        hasInputMonitoringAccess: @escaping SuperModeSettingsWindowController.HasInputMonitoringAccess = { true },
        requestInputMonitoringAccess: @escaping SuperModeSettingsWindowController.RequestInputMonitoringAccess = { true },
        retrySuperModeRuntime: @escaping SuperModeSettingsWindowController.RetrySuperModeRuntime = {},
        presenter: any HotkeyChordPresenting = HotkeyChordPresenter(labelResolver: MacOSHotkeyKeyLabelResolver()),
        load: @escaping Load,
        apply: @escaping Apply,
        recorder: (any HotkeyRecording)? = nil,
        suspendHotkeys: SuperModeSettingsWindowController.SuspendHotkeys? = nil,
        resumeHotkeys: SuperModeSettingsWindowController.ResumeHotkeys? = nil
    ) {
        self.load = load
        self.apply = apply
        self.hasInputMonitoringAccess = hasInputMonitoringAccess
        self.requestInputMonitoringAccess = requestInputMonitoringAccess
        self.retrySuperModeRuntime = retrySuperModeRuntime
        self.presenter = presenter
        self.suspendHotkeys = suspendHotkeys
        self.resumeHotkeys = resumeHotkeys
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
        if isRecordingPrefix {
            cancelRecordingPrefix()
            return
        }
        cancelRecordingPrefix()
        isRecordingPrefix = true
        recorderUpdatesTask = Task { [weak self, recorder] in
            await self?.suspendHotkeys?()
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
                    await self.resumeHotkeys?()
                    return
                case .cancelled, .cleared:
                    isRecordingPrefix = false
                    await self.resumeHotkeys?()
                    return
                case .idle:
                    continue
                }
            }
            await self?.resumeHotkeys?()
        }
    }

    func cancelRecordingPrefix() {
        guard isRecordingPrefix || recorderUpdatesTask != nil else { return }
        isRecordingPrefix = false
        recorderUpdatesTask?.cancel()
        recorderUpdatesTask = nil
        Task { [weak self, recorder] in
            await recorder.cancel()
            await self?.resumeHotkeys?()
        }
    }

    struct RecordingKeyTarget: Equatable {
        let bindingID: UUID
        let level: Int
    }
    @Published private(set) var recordingKeyTarget: RecordingKeyTarget?

    func recordKey(bindingID: UUID, level: Int) {
        let target = RecordingKeyTarget(bindingID: bindingID, level: level)
        if recordingKeyTarget == target {
            cancelRecordingKey()
            return
        }
        cancelRecordingKey()
        cancelRecordingPrefix()
        recordingKeyTarget = target
        recorderUpdatesTask = Task { [weak self, recorder] in
            await self?.suspendHotkeys?()
            let updates = await recorder.updates
            await recorder.begin()
            for await update in updates {
                guard let self else { return }
                switch update {
                case .recording:
                    break
                case let .captured(chord):
                    setBindingKeyCode(id: bindingID, level: level, keyCode: chord.hardwareKeyCode)
                    recordingKeyTarget = nil
                    await self.resumeHotkeys?()
                    return
                case .cancelled, .cleared:
                    recordingKeyTarget = nil
                    await self.resumeHotkeys?()
                    return
                case .idle:
                    continue
                }
            }
            await self?.resumeHotkeys?()
        }
    }

    func cancelRecordingKey() {
        guard recordingKeyTarget != nil || recorderUpdatesTask != nil else { return }
        recordingKeyTarget = nil
        recorderUpdatesTask?.cancel()
        recorderUpdatesTask = nil
        Task { [weak self, recorder] in
            await recorder.cancel()
            await self?.resumeHotkeys?()
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Super Mode")
                .font(.title2.weight(.semibold))
            Text("Hold the prefix, then type a one- or two-key command sequence.")
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    inputMonitoringCard
                    prefixCard
                    commandsCard
                }
                .padding(.vertical, 4)
            }

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

    private var inputMonitoringCard: some View {
        SettingsCard(label: "Input Monitoring") {
            SettingsRow(
                icon: IconTile(
                    systemName: model.inputMonitoringState == .granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                    tint: model.inputMonitoringState == .granted ? .green : .orange
                ),
                title: "Input Monitoring",
                caption: model.inputMonitoringState == .granted
                    ? "Granted — Super Mode can receive the Prefix."
                    : "Super Mode needs Input Monitoring to receive and safely consume Prefix sequences while you use other apps."
            ) {
                if model.inputMonitoringState == .granted {
                    StatusDot(state: .active)
                } else {
                    Button("Enable Input Monitoring") {
                        Task { await model.requestInputMonitoring() }
                    }
                    .accessibilityHint("Requests macOS Input Monitoring access, then retries Super Mode.")
                }
            }
        }
    }

    private var prefixCard: some View {
        SettingsCard(label: "Prefix") {
            SettingsRow(
                icon: IconTile(systemName: "command", tint: Color.accentColor),
                title: "Shortcut",
                caption: "Press the complete prefix shortcut after recording starts."
            ) {
                HStack(spacing: 8) {
                    KeycapChip(label: model.prefixPresentation.visibleLabel)
                        .accessibilityLabel(model.prefixPresentation.accessibilityLabel)

                    Button(model.isRecordingPrefix ? "Recording…" : "Record Prefix") {
                        model.recordPrefix()
                    }
                    .disabled(model.isRecordingPrefix)
                    .accessibilityHint("Press the complete prefix shortcut after recording starts.")
                }
            }

            SettingsDivider()

            SettingsRow(
                title: "Modifiers",
                caption: "Active modifier keys"
            ) {
                HStack(spacing: 8) {
                    modifierToggle("Control", modifier: .control)
                    modifierToggle("Option", modifier: .option)
                    modifierToggle("Shift", modifier: .shift)
                    modifierToggle("Command", modifier: .command)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Prefix modifiers")
            }

            SettingsDivider()

            SettingsRow(
                title: "Sequence timeout",
                caption: "\(model.timeoutMilliseconds) ms between keystrokes"
            ) {
                Stepper(
                    "Sequence timeout: \(model.timeoutMilliseconds) ms",
                    value: $model.timeoutMilliseconds,
                    in: SuperModeConfiguration.minimumTimeoutMilliseconds...SuperModeConfiguration.maximumTimeoutMilliseconds,
                    step: 50
                )
                .accessibilityLabel("Sequence timeout in milliseconds")
            }
        }
    }

    private var commandsCard: some View {
        SettingsCard(label: "Commands") {
            if model.bindings.isEmpty {
                Text("No commands yet. Add a binding or load the test preset.")
                    .font(SettingsTypography.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(model.bindings.enumerated()), id: \.element.id) { index, binding in
                    if index > 0 {
                        SettingsDivider()
                    }
                    BindingRow(model: model, binding: binding)
                        .padding(.vertical, 4)
                }
            }

            SettingsDivider()

            HStack {
                Button("Add Binding") { model.addBinding() }
                Button("Load Test Preset") { model.loadTestPreset() }
                    .accessibilityHint("Replaces the unsaved draft with the Sprint 5 test bindings.")
            }
            .padding(.top, 8)
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    sequenceControls
                    Spacer(minLength: 8)
                    deleteButton
                }
                LabeledContent("Action") {
                    actionPicker.frame(maxWidth: 360)
                }
            }
        } else {
            HStack(spacing: 10) {
                sequenceControls
                actionPicker
                deleteButton
            }
        }
    }

    @ViewBuilder
    private var sequenceControls: some View {
        Picker("Keys", selection: levelCount) {
            Text("1 key").tag(1)
            Text("2 keys").tag(2)
        }
        .labelsHidden()
        .frame(width: 80)
        .accessibilityLabel("Sequence length")

        ForEach(binding.hardwareKeyCodes.indices, id: \.self) { level in
            commandKeyRecorder(level)
        }
    }

    private func commandKeyRecorder(_ level: Int) -> some View {
        let target = SuperModeSettingsModel.RecordingKeyTarget(bindingID: binding.id, level: level)
        let isListening = model.recordingKeyTarget == target
        let presentation = model.bindingKeyPresentation(for: binding, level: level)
        let keyChord = KeyChord(modifiers: [], key: presentation.visibleLabel)

        let recorderBinding = Binding<ShortcutRecorderModel>(
            get: {
                let currentListening = model.recordingKeyTarget == target
                return ShortcutRecorderModel(
                    state: currentListening ? .listening : .idle(chord: keyChord),
                    defaultChord: nil
                )
            },
            set: { updated in
                if updated.isListening {
                    model.recordKey(bindingID: binding.id, level: level)
                } else if model.recordingKeyTarget == target {
                    model.cancelRecordingKey()
                }
            }
        )

        return ShortcutRecorderButton(model: recorderBinding)
            .accessibilityLabel("Command key \(level + 1)")
            .accessibilityValue(presentation.accessibilityLabel)
    }

    private var actionPicker: some View {
        Picker("Action", selection: actionID) {
            ForEach(model.actionOptions) { option in
                Text(option.isAvailable ? option.title : "\(option.title) — Unavailable")
                    .tag(option.id)
                    .disabled(!option.isAvailable)
            }
        }
        .labelsHidden()
        .accessibilityLabel("Action")
    }

    private var deleteButton: some View {
        Button("Delete", systemImage: "minus.circle", role: .destructive) {
            model.deleteBinding(id: binding.id)
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Delete binding")
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
final class GlobalHotkeySettingsWindowController: NSObject, NSWindowDelegate {
    typealias Load = @MainActor @Sendable () async -> HotkeySettings
    typealias Apply = @MainActor @Sendable (HotkeySettings) async -> HotkeyRuntimeUpdateResult
    typealias SuspendHotkeys = @MainActor @Sendable () async -> Void
    typealias ResumeHotkeys = @MainActor @Sendable () async -> Void
    private let model: GlobalHotkeySettingsModel
    private var window: NSWindow?

    init(
        actionRegistry: ActionRegistry,
        load: @escaping Load,
        apply: @escaping Apply,
        recorder: (any HotkeyRecording)? = nil,
        presenter: any HotkeyChordPresenting = HotkeyChordPresenter(labelResolver: MacOSHotkeyKeyLabelResolver()),
        suspendHotkeys: SuspendHotkeys? = nil,
        resumeHotkeys: ResumeHotkeys? = nil
    ) {
        model = GlobalHotkeySettingsModel(
            actionRegistry: actionRegistry,
            load: load,
            apply: apply,
            validator: HotkeyConflictDetector(),
            recorder: recorder,
            presenter: presenter,
            suspendHotkeys: suspendHotkeys,
            resumeHotkeys: resumeHotkeys
        )
        super.init()
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
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
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
    private let suspendHotkeys: GlobalHotkeySettingsWindowController.SuspendHotkeys?
    private let resumeHotkeys: GlobalHotkeySettingsWindowController.ResumeHotkeys?
    private let validator: any HotkeyConflictValidating
    private let recorder: any HotkeyRecording
    private let presenter: any HotkeyChordPresenting
    private var recorderTask: Task<Void, Never>?

    init(
        actionRegistry: ActionRegistry,
        load: @escaping GlobalHotkeySettingsWindowController.Load,
        apply: @escaping GlobalHotkeySettingsWindowController.Apply,
        validator: any HotkeyConflictValidating = HotkeyConflictDetector(),
        recorder: (any HotkeyRecording)? = nil,
        presenter: any HotkeyChordPresenting = HotkeyChordPresenter(labelResolver: MacOSHotkeyKeyLabelResolver()),
        suspendHotkeys: GlobalHotkeySettingsWindowController.SuspendHotkeys? = nil,
        resumeHotkeys: GlobalHotkeySettingsWindowController.ResumeHotkeys? = nil
    ) {
        actions = actionRegistry.actions
        self.load = load
        self.apply = apply
        self.suspendHotkeys = suspendHotkeys
        self.resumeHotkeys = resumeHotkeys
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
        cancelRecording()
        replaceBindings(settings.bindings + [HotkeyBinding(id: UUID(), hardwareKeyCode: 0, modifiers: [.control], actionID: actions.first(where: { $0.availability == .available })?.id ?? .maximize)])
    }

    func deleteBinding(_ id: UUID) {
        if recordingBindingID == id {
            cancelRecording()
        }
        replaceBindings(settings.bindings.filter { $0.id != id })
    }

    func setAction(_ actionID: ActionID, for id: UUID) {
        replaceBinding(id) { HotkeyBinding(id: $0.id, hardwareKeyCode: $0.hardwareKeyCode, modifiers: $0.modifiers, actionID: actionID) }
    }

    func record(_ id: UUID) {
        if recordingBindingID == id {
            cancelRecording()
            return
        }
        cancelRecording()
        recordingBindingID = id
        recorderTask = Task { [weak self, recorder] in
            await self?.suspendHotkeys?()
            let updates = await recorder.updates
            await recorder.begin()
            for await update in updates {
                guard let self else { return }
                switch update {
                case let .captured(chord):
                    self.applyRecorded(chord, to: id)
                    self.recordingBindingID = nil
                    await self.resumeHotkeys?()
                    return
                case .cancelled, .cleared:
                    self.recordingBindingID = nil
                    await self.resumeHotkeys?()
                    return
                case .idle, .recording:
                    continue
                }
            }
            await self?.resumeHotkeys?()
        }
    }

    func cancelRecording() {
        guard recordingBindingID != nil || recorderTask != nil else { return }
        recordingBindingID = nil
        recorderTask?.cancel()
        recorderTask = nil
        Task { [weak self, recorder] in
            await recorder.cancel()
            await self?.resumeHotkeys?()
        }
    }

    func presentation(for chord: HotkeyChord) -> SettingsHotkeyPresentation {
        presenter.present(chord).settingsPresentation
    }

    func keyChord(for chord: HotkeyChord) -> KeyChord {
        let pres = presenter.present(chord)
        return KeyChord(presentation: pres)
    }

    func save() async {
        cancelRecording()
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global Hotkeys")
                .font(.title2.weight(.semibold))
            Text("Record keyboard shortcuts for Window Actions.")
                .font(SettingsTypography.body)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsCard(label: "Shortcuts") {
                        if model.settings.bindings.isEmpty {
                            Text("No global hotkeys configured.")
                                .font(SettingsTypography.body)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(model.settings.bindings.enumerated()), id: \.element.id) { index, binding in
                                if index > 0 {
                                    SettingsDivider()
                                }
                                hotkeyRow(binding)
                                    .padding(.vertical, 4)
                            }
                        }

                        SettingsDivider()

                        HStack {
                            Button("Add Hotkey", systemImage: "plus") {
                                model.addBinding()
                            }
                            .disabled(isBusy)
                            Spacer()
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            }

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
        .frame(minWidth: 640, minHeight: 440)
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

    private func hotkeyRow(_ binding: HotkeyBinding) -> some View {
        let action = model.actions.first { $0.id == binding.actionID }
        let iconName = action?.symbolName ?? "command"
        let isListening = model.recordingBindingID == binding.id
        let keyChord = model.keyChord(for: binding.chord)

        let recorderBinding = Binding<ShortcutRecorderModel>(
            get: {
                let currentListening = model.recordingBindingID == binding.id
                return ShortcutRecorderModel(
                    state: currentListening ? .listening : .idle(chord: keyChord),
                    defaultChord: nil
                )
            },
            set: { updated in
                if updated.isListening {
                    model.record(binding.id)
                } else if model.recordingBindingID == binding.id {
                    model.cancelRecording()
                }
            }
        )

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        IconTile(systemName: iconName, tint: Color.accentColor)
                        ShortcutRecorderButton(model: recorderBinding)
                            .accessibilityLabel(isListening ? "Recording shortcut" : "Record shortcut")
                        Spacer()
                        Button("Delete", systemImage: "minus.circle", role: .destructive) {
                            model.deleteBinding(binding.id)
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Delete binding")
                    }
                    Picker("Action", selection: Binding(get: { binding.actionID }, set: { model.setAction($0, for: binding.id) })) {
                        ForEach(model.actions, id: \.id) { act in
                            Text(act.title).tag(act.id).disabled(act.availability != .available)
                        }
                    }
                    .accessibilityLabel("Action")
                }
            } else {
                HStack(spacing: 12) {
                    IconTile(systemName: iconName, tint: Color.accentColor)
                    ShortcutRecorderButton(model: recorderBinding)
                        .accessibilityLabel(isListening ? "Recording shortcut" : "Record shortcut")
                    Picker("Action", selection: Binding(get: { binding.actionID }, set: { model.setAction($0, for: binding.id) })) {
                        ForEach(model.actions, id: \.id) { act in
                            Text(act.title).tag(act.id).disabled(act.availability != .available)
                        }
                    }
                    .accessibilityLabel("Action")
                    Spacer()
                    Button("Delete", systemImage: "minus.circle", role: .destructive) {
                        model.deleteBinding(binding.id)
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Delete binding")
                }
            }
        }
    }
}
