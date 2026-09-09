import Foundation

struct SuperModeCommandBinding: Equatable, Sendable {
    let hardwareKeyCodes: [UInt16]
    let actionID: ActionID

    init(hardwareKeyCodes: [UInt16], actionID: ActionID) {
        self.hardwareKeyCodes = hardwareKeyCodes
        self.actionID = actionID
    }
}

struct SuperModeConfiguration: Equatable, Sendable {
    static let defaultTimeoutMilliseconds: UInt32 = 1_000
    static let minimumTimeoutMilliseconds: UInt32 = 250
    static let maximumTimeoutMilliseconds: UInt32 = 5_000

    static let `default` = SuperModeConfiguration(
        prefix: HotkeyChord(hardwareKeyCode: 49, modifiers: [.control]),
        timeoutMilliseconds: defaultTimeoutMilliseconds,
        commandBindings: [
            SuperModeCommandBinding(hardwareKeyCodes: [1], actionID: .openSettings),
        ]
    )

    let prefix: HotkeyChord
    let timeoutMilliseconds: UInt32
    let commandBindings: [SuperModeCommandBinding]

    init(
        prefix: HotkeyChord,
        timeoutMilliseconds: UInt32,
        commandBindings: [SuperModeCommandBinding]
    ) {
        self.prefix = prefix
        self.timeoutMilliseconds = timeoutMilliseconds
        self.commandBindings = commandBindings
    }
}

enum SuperModeConfigurationFailure: Error, Equatable, Sendable {
    case invalidTimeout(milliseconds: UInt32)
    case invalidPrefix(InvalidHotkeyReason)
    case reservedPrefix(ReservedHotkeyConflict)
    case hotkeyConflict(DuplicateHotkeyConflict)
    case invalidPath(bindingIndex: Int, levelCount: Int)
    case invalidHardwareKeyCode(bindingIndex: Int, hardwareKeyCode: UInt16)
    case reservedSequenceKey(bindingIndex: Int, hardwareKeyCode: UInt16)
    case invalidAction(bindingIndex: Int, actionID: ActionID)
    case duplicatePath([UInt16])
    case ambiguousRoot(hardwareKeyCode: UInt16)
}

struct ValidatedSuperModeConfiguration: Equatable, Sendable {
    let configuration: SuperModeConfiguration
    let commandTree: SuperModeCommandTree
}

enum SuperModeConfigurationValidationResult: Equatable, Sendable {
    case valid(ValidatedSuperModeConfiguration)
    case invalid(SuperModeConfigurationFailure)
}

protocol SuperModeConfigurationValidating: Sendable {
    func validate(
        _ configuration: SuperModeConfiguration,
        hotkeyBindings: [HotkeyBinding]
    ) -> SuperModeConfigurationValidationResult
}

struct SuperModeConfigurationValidator: SuperModeConfigurationValidating {
    private static let validHardwareKeyCodes: ClosedRange<UInt16> = 0...126
    private static let modifierOnlyHardwareKeyCodes: ClosedRange<UInt16> = 54...63
    private static let escapeHardwareKeyCode: UInt16 = 53
    private static let prefixActionID = ActionID(rawValue: "super-mode.prefix")

    private let actionRegistry: ActionRegistry
    private let appActionCatalog: SuperModeAppActionCatalog
    private let hotkeyConflictDetector: any HotkeyConflictValidating

    init(
        actionRegistry: ActionRegistry,
        appActionCatalog: SuperModeAppActionCatalog = .builtIn,
        hotkeyConflictDetector: any HotkeyConflictValidating = HotkeyConflictDetector()
    ) {
        self.actionRegistry = actionRegistry
        self.appActionCatalog = appActionCatalog
        self.hotkeyConflictDetector = hotkeyConflictDetector
    }

    func validate(
        _ configuration: SuperModeConfiguration,
        hotkeyBindings: [HotkeyBinding]
    ) -> SuperModeConfigurationValidationResult {
        guard configuration.timeoutMilliseconds
            >= SuperModeConfiguration.minimumTimeoutMilliseconds,
            configuration.timeoutMilliseconds
            <= SuperModeConfiguration.maximumTimeoutMilliseconds else {
            return .invalid(.invalidTimeout(milliseconds: configuration.timeoutMilliseconds))
        }

        switch hotkeyConflictDetector.validate(
            HotkeyValidationRequest(
                editedBindingID: nil,
                actionID: Self.prefixActionID,
                candidate: configuration.prefix,
                existingBindings: hotkeyBindings
            )
        ) {
        case .valid:
            break
        case let .invalid(reason):
            return .invalid(.invalidPrefix(reason))
        case let .reserved(conflict):
            return .invalid(.reservedPrefix(conflict))
        case let .duplicate(conflict):
            return .invalid(.hotkeyConflict(conflict))
        }

        var paths = Set<[UInt16]>()
        var oneLevel: [UInt16: ActionID] = [:]
        var twoLevel: [UInt16: [UInt16: ActionID]] = [:]

        for (index, binding) in configuration.commandBindings.enumerated() {
            guard (1...2).contains(binding.hardwareKeyCodes.count) else {
                return .invalid(
                    .invalidPath(
                        bindingIndex: index,
                        levelCount: binding.hardwareKeyCodes.count
                    )
                )
            }
            for hardwareKeyCode in binding.hardwareKeyCodes {
                guard Self.validHardwareKeyCodes.contains(hardwareKeyCode),
                      !Self.modifierOnlyHardwareKeyCodes.contains(hardwareKeyCode) else {
                    return .invalid(
                        .invalidHardwareKeyCode(
                            bindingIndex: index,
                            hardwareKeyCode: hardwareKeyCode
                        )
                    )
                }
                guard hardwareKeyCode != Self.escapeHardwareKeyCode else {
                    return .invalid(
                        .reservedSequenceKey(
                            bindingIndex: index,
                            hardwareKeyCode: hardwareKeyCode
                        )
                    )
                }
            }
            guard actionRegistry.action(for: binding.actionID) != nil
                    || appActionCatalog.action(for: binding.actionID) != nil else {
                return .invalid(
                    .invalidAction(bindingIndex: index, actionID: binding.actionID)
                )
            }
            guard paths.insert(binding.hardwareKeyCodes).inserted else {
                return .invalid(.duplicatePath(binding.hardwareKeyCodes))
            }

            let root = binding.hardwareKeyCodes[0]
            if binding.hardwareKeyCodes.count == 1 {
                guard twoLevel[root] == nil else {
                    return .invalid(.ambiguousRoot(hardwareKeyCode: root))
                }
                oneLevel[root] = binding.actionID
            } else {
                guard oneLevel[root] == nil else {
                    return .invalid(.ambiguousRoot(hardwareKeyCode: root))
                }
                twoLevel[root, default: [:]][binding.hardwareKeyCodes[1]] = binding.actionID
            }
        }

        return .valid(
            ValidatedSuperModeConfiguration(
                configuration: configuration,
                commandTree: SuperModeCommandTree(
                    oneLevel: oneLevel,
                    twoLevel: twoLevel
                )
            )
        )
    }
}

struct SuperModeConfigurationRevision: RawRepresentable, Equatable, Hashable, Sendable {
    let rawValue: UInt64
}

struct SuperModeRuntimeSnapshot: Equatable, Sendable {
    let revision: SuperModeConfigurationRevision
    let configuration: SuperModeConfiguration
    let commandTree: SuperModeCommandTree

    func session(_ sessionID: SuperModeSessionID) -> SuperModeRuntimeSession {
        SuperModeRuntimeSession(revision: revision, sessionID: sessionID)
    }
}

struct SuperModeRuntimeSession: Equatable, Sendable {
    let revision: SuperModeConfigurationRevision
    let sessionID: SuperModeSessionID
}

enum SuperModeRuntimeFreshness: Equatable, Sendable {
    case current
    case stale(currentRevision: SuperModeConfigurationRevision)
    case unavailable
}

protocol SuperModeRuntimeConfigurationReplacing: Actor {
    func replace(
        with configuration: ValidatedSuperModeConfiguration
    ) -> SuperModeRuntimeSnapshot
    func activate(_ session: SuperModeRuntimeSession) -> SuperModeRuntimeFreshness
    func freshness(
        of revision: SuperModeConfigurationRevision
    ) -> SuperModeRuntimeFreshness
    func freshness(of session: SuperModeRuntimeSession) -> SuperModeRuntimeFreshness
}

actor SuperModeRuntimeConfiguration: SuperModeRuntimeConfigurationReplacing {
    private var lastRevision: UInt64 = 0
    private(set) var currentSnapshot: SuperModeRuntimeSnapshot?
    private var activeSession: SuperModeRuntimeSession?

    func replace(
        with validated: ValidatedSuperModeConfiguration
    ) -> SuperModeRuntimeSnapshot {
        precondition(
            lastRevision < UInt64.max,
            "Super Mode exhausted its monotonically unique configuration revision space"
        )
        lastRevision += 1
        let snapshot = SuperModeRuntimeSnapshot(
            revision: SuperModeConfigurationRevision(rawValue: lastRevision),
            configuration: validated.configuration,
            commandTree: validated.commandTree
        )
        currentSnapshot = snapshot
        activeSession = nil
        return snapshot
    }

    func activate(_ session: SuperModeRuntimeSession) -> SuperModeRuntimeFreshness {
        guard let currentSnapshot else { return .unavailable }
        guard currentSnapshot.revision == session.revision else {
            return .stale(currentRevision: currentSnapshot.revision)
        }
        activeSession = session
        return .current
    }

    func freshness(of revision: SuperModeConfigurationRevision) -> SuperModeRuntimeFreshness {
        guard let currentSnapshot else { return .unavailable }
        guard currentSnapshot.revision == revision else {
            return .stale(currentRevision: currentSnapshot.revision)
        }
        return .current
    }

    func freshness(of session: SuperModeRuntimeSession) -> SuperModeRuntimeFreshness {
        guard let currentSnapshot else { return .unavailable }
        guard currentSnapshot.revision == session.revision,
              activeSession == session
        else {
            return .stale(currentRevision: currentSnapshot.revision)
        }
        return .current
    }
}

enum SuperModeConfigurationStartResult: Equatable, Sendable {
    case active(
        settings: HotkeySettings,
        origin: SettingsLoadOrigin,
        runtime: SuperModeRuntimeSnapshot
    )
    case invalidPersistedConfiguration(SuperModeConfigurationFailure)
}

enum SuperModeConfigurationApplyResult: Equatable, Sendable {
    case applied(settings: HotkeySettings, runtime: SuperModeRuntimeSnapshot)
    case rejected(SuperModeConfigurationFailure)
    case persistenceFailed(SettingsSaveFailure)
}

actor SuperModeConfigurationModule {
    private let store: any SettingsStoring
    private let runtime: any SuperModeRuntimeConfigurationReplacing
    private let validator: any SuperModeConfigurationValidating
    private var applyInProgress = false
    private var applyWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        store: any SettingsStoring,
        runtime: any SuperModeRuntimeConfigurationReplacing,
        validator: any SuperModeConfigurationValidating
    ) {
        self.store = store
        self.runtime = runtime
        self.validator = validator
    }

    func currentSettings() async -> SettingsLoadResult {
        await store.load()
    }

    func start() async -> SuperModeConfigurationStartResult {
        let loadResult = await store.load()
        switch loadResult {
        case let .loaded(settings, origin):
            switch validator.validate(
                settings.superModeConfiguration,
                hotkeyBindings: settings.bindings
            ) {
            case let .valid(validated):
                return .active(
                    settings: settings,
                    origin: origin,
                    runtime: await runtime.replace(with: validated)
                )
            case let .invalid(failure):
                return .invalidPersistedConfiguration(failure)
            }
        }
    }

    func apply(
        _ configuration: SuperModeConfiguration,
        hotkeyBindings: [HotkeyBinding]
    ) async -> SuperModeConfigurationApplyResult {
        await acquireApplyPermit()
        defer { releaseApplyPermit() }
        switch validator.validate(configuration, hotkeyBindings: hotkeyBindings) {
        case let .invalid(failure):
            return .rejected(failure)
        case let .valid(validated):
            let settings = HotkeySettings(
                bindings: hotkeyBindings,
                superModeConfiguration: configuration
            )
            switch await store.save(settings) {
            case let .failed(failure):
                return .persistenceFailed(failure)
            case .saved:
                return .applied(
                    settings: settings,
                    runtime: await runtime.replace(with: validated)
                )
            }
        }
    }

    private func acquireApplyPermit() async {
        guard applyInProgress else {
            applyInProgress = true
            return
        }

        await withCheckedContinuation { continuation in
            applyWaiters.append(continuation)
        }
    }

    private func releaseApplyPermit() {
        guard !applyWaiters.isEmpty else {
            applyInProgress = false
            return
        }

        applyWaiters.removeFirst().resume()
    }
}
