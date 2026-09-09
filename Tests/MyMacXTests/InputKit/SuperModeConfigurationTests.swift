import XCTest
import Foundation
@testable import MyMacX

final class SuperModeConfigurationTests: XCTestCase {
    func testDefaultConfigurationOpensSettingsWithS() {
        XCTAssertEqual(
            SuperModeConfiguration.default.commandBindings,
            [SuperModeCommandBinding(hardwareKeyCodes: [1], actionID: .openSettings)]
        )
    }

    func testValidationRejectsInvalidCandidatesBeforeDocumentOrRuntimeReplacement() async {
        let documents = InMemorySettingsDocumentAdapter()
        let store: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )
        let runtime = SuperModeRuntimeConfiguration()
        let module = SuperModeConfigurationModule(
            store: store,
            runtime: runtime,
            validator: SuperModeConfigurationValidator(actionRegistry: .builtIn)
        )
        let unknownAction = ActionID(rawValue: "window.not-registered")
        let invalidCases: [
            (
                configuration: SuperModeConfiguration,
                hotkeys: [HotkeyBinding],
                failure: SuperModeConfigurationFailure
            )
        ] = [
            (
                configuration(timeout: 249),
                [],
                .invalidTimeout(milliseconds: 249)
            ),
            (
                configuration(
                    commands: [
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [],
                            actionID: .maximize
                        ),
                    ]
                ),
                [],
                .invalidPath(bindingIndex: 0, levelCount: 0)
            ),
            (
                configuration(
                    commands: [
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [127],
                            actionID: .maximize
                        ),
                    ]
                ),
                [],
                .invalidHardwareKeyCode(bindingIndex: 0, hardwareKeyCode: 127)
            ),
            (
                configuration(
                    commands: [
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [54],
                            actionID: .maximize
                        ),
                    ]
                ),
                [],
                .invalidHardwareKeyCode(bindingIndex: 0, hardwareKeyCode: 54)
            ),
            (
                configuration(
                    commands: [
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [53],
                            actionID: .maximize
                        ),
                    ]
                ),
                [],
                .reservedSequenceKey(bindingIndex: 0, hardwareKeyCode: 53)
            ),
            (
                configuration(
                    commands: [
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [0],
                            actionID: unknownAction
                        ),
                    ]
                ),
                [],
                .invalidAction(bindingIndex: 0, actionID: unknownAction)
            ),
            (
                configuration(
                    commands: [
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [0, 1],
                            actionID: .leftHalf
                        ),
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [0, 1],
                            actionID: .rightHalf
                        ),
                    ]
                ),
                [],
                .duplicatePath([0, 1])
            ),
            (
                configuration(
                    commands: [
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [0],
                            actionID: .leftHalf
                        ),
                        SuperModeCommandBinding(
                            hardwareKeyCodes: [0, 1],
                            actionID: .rightHalf
                        ),
                    ]
                ),
                [],
                .ambiguousRoot(hardwareKeyCode: 0)
            ),
            (
                configuration(
                    prefix: HotkeyChord(
                        hardwareKeyCode: 49,
                        modifiers: [.command]
                    )
                ),
                [],
                .reservedPrefix(
                    ReservedHotkeyConflict(
                        reservationID: ReservedHotkeyID(
                            rawValue: "system.spotlight"
                        ),
                        replacementAllowed: false
                    )
                )
            ),
            (
                configuration(),
                [prefixConflictingHotkey],
                .hotkeyConflict(
                    DuplicateHotkeyConflict(
                        conflicts: [
                            ConflictingHotkeyBinding(
                                bindingID: prefixConflictingHotkey.id,
                                actionID: prefixConflictingHotkey.actionID
                            ),
                        ]
                    )
                )
            ),
        ]

        for invalidCase in invalidCases {
            let result = await module.apply(
                invalidCase.configuration,
                hotkeyBindings: invalidCase.hotkeys
            )
            XCTAssertEqual(result, .rejected(invalidCase.failure))
        }

        let replacementCallCount = await documents.replacementCallCount
        let runtimeSnapshot = await runtime.currentSnapshot
        XCTAssertEqual(replacementCallCount, 0)
        XCTAssertNil(runtimeSnapshot)
    }
    func testValidationAcceptsBuiltInAppActionsForSuperModeSequences() {
        let validator = SuperModeConfigurationValidator(actionRegistry: .builtIn)
        let configuration = configuration(commands: [
            SuperModeCommandBinding(hardwareKeyCodes: [1], actionID: .openSettings),
            SuperModeCommandBinding(hardwareKeyCodes: [2], actionID: .toggleGaps),
            SuperModeCommandBinding(hardwareKeyCodes: [3], actionID: .selectProfile),
        ])

        guard case let .valid(validated) = validator.validate(
            configuration,
            hotkeyBindings: []
        ) else {
            return XCTFail("Expected built-in app actions to be valid Super Mode bindings")
        }

        XCTAssertEqual(validated.configuration, configuration)
    }

    func testSuccessfulApplyPersistsAndAtomicallyReplacesRuntimeRevision() async {
        let documents = InMemorySettingsDocumentAdapter()
        let store: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )
        let runtime = SuperModeRuntimeConfiguration()
        let module = SuperModeConfigurationModule(
            store: store,
            runtime: runtime,
            validator: SuperModeConfigurationValidator(actionRegistry: .builtIn)
        )
        let firstConfiguration = configuration(
            commands: [
                SuperModeCommandBinding(
                    hardwareKeyCodes: [0],
                    actionID: .leftHalf
                ),
            ]
        )
        let secondConfiguration = configuration(
            timeout: 2_500,
            commands: [
                SuperModeCommandBinding(
                    hardwareKeyCodes: [1, 2],
                    actionID: .rightHalf
                ),
            ]
        )

        let firstResult = await module.apply(
            firstConfiguration,
            hotkeyBindings: []
        )
        guard case let .applied(_, firstRuntime) = firstResult else {
            return XCTFail("Expected first configuration to apply")
        }
        let firstSession = firstRuntime.session(SuperModeSessionID(rawValue: 41))
        let firstActivation = await runtime.activate(firstSession)

        let secondResult = await module.apply(
            secondConfiguration,
            hotkeyBindings: []
        )
        guard case let .applied(secondSettings, secondRuntime) = secondResult else {
            return XCTFail("Expected second configuration to apply")
        }
        let sameIDSession = secondRuntime.session(firstSession.sessionID)

        let currentSnapshot = await runtime.currentSnapshot
        let staleRevision = await runtime.freshness(of: firstRuntime.revision)
        let staleSession = await runtime.freshness(of: firstSession)
        let staleActivation = await runtime.activate(firstSession)
        let sameIDSessionFreshness = await runtime.freshness(of: sameIDSession)
        let currentRevision = await runtime.freshness(of: secondRuntime.revision)
        let replacementCallCount = await documents.replacementCallCount
        let reloadedStore: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )
        let reloadResult = await reloadedStore.load()

        XCTAssertEqual(firstActivation, .current)
        XCTAssertEqual(secondRuntime.revision.rawValue, firstRuntime.revision.rawValue + 1)
        XCTAssertEqual(currentSnapshot, secondRuntime)
        XCTAssertEqual(
            staleRevision,
            .stale(currentRevision: secondRuntime.revision)
        )
        XCTAssertEqual(
            staleSession,
            .stale(currentRevision: secondRuntime.revision)
        )
        XCTAssertEqual(
            staleActivation,
            .stale(currentRevision: secondRuntime.revision)
        )
        XCTAssertEqual(
            sameIDSessionFreshness,
            .stale(currentRevision: secondRuntime.revision)
        )
        XCTAssertEqual(currentRevision, .current)
        XCTAssertEqual(replacementCallCount, 2)
        XCTAssertEqual(
            reloadResult,
            .loaded(secondSettings, origin: .persisted(schemaVersion: 3))
        )

        var reducer = SuperModeReducer(commandTree: secondRuntime.commandTree)
        _ = reducer.reduce(.prefix)
        XCTAssertEqual(reducer.reduce(.keyDown(hardwareKeyCode: 1)).outcome, .submenuEntered)
        XCTAssertEqual(
            reducer.reduce(.keyDown(hardwareKeyCode: 2)).outcome,
            .execute(.rightHalf)
        )
    }

    func testSessionFreshnessRequiresExactActivatedToken() async {
        let runtime = SuperModeRuntimeConfiguration()
        let unavailableSession = SuperModeRuntimeSession(
            revision: SuperModeConfigurationRevision(rawValue: 1),
            sessionID: SuperModeSessionID(rawValue: 40)
        )

        let unavailableActivation = await runtime.activate(unavailableSession)
        let unavailableFreshness = await runtime.freshness(of: unavailableSession)

        let snapshot = await runtime.replace(
            with: ValidatedSuperModeConfiguration(
                configuration: configuration(),
                commandTree: SuperModeCommandTree()
            )
        )
        let activatedSession = snapshot.session(SuperModeSessionID(rawValue: 41))
        let differentSession = snapshot.session(SuperModeSessionID(rawValue: 42))
        let forgedSession = SuperModeRuntimeSession(
            revision: snapshot.revision,
            sessionID: SuperModeSessionID(rawValue: 43)
        )

        let unactivatedFreshness = await runtime.freshness(of: activatedSession)
        let activation = await runtime.activate(activatedSession)
        let activatedFreshness = await runtime.freshness(of: activatedSession)
        let differentSessionFreshness = await runtime.freshness(of: differentSession)
        let forgedSessionFreshness = await runtime.freshness(of: forgedSession)

        XCTAssertEqual(unavailableActivation, .unavailable)
        XCTAssertEqual(unavailableFreshness, .unavailable)
        XCTAssertEqual(
            unactivatedFreshness,
            .stale(currentRevision: snapshot.revision)
        )
        XCTAssertEqual(activation, .current)
        XCTAssertEqual(activatedFreshness, .current)
        XCTAssertEqual(
            differentSessionFreshness,
            .stale(currentRevision: snapshot.revision)
        )
        XCTAssertEqual(
            forgedSessionFreshness,
            .stale(currentRevision: snapshot.revision)
        )
    }

    func testPersistenceFailureLeavesRuntimeRevisionUnchanged() async {
        let documents = InMemorySettingsDocumentAdapter()
        await documents.setReplacementOutcome(.fails)
        let store: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )
        let runtime = SuperModeRuntimeConfiguration()
        let module = SuperModeConfigurationModule(
            store: store,
            runtime: runtime,
            validator: SuperModeConfigurationValidator(actionRegistry: .builtIn)
        )

        let result = await module.apply(configuration(), hotkeyBindings: [])
        let currentSnapshot = await runtime.currentSnapshot

        XCTAssertEqual(result, .persistenceFailed(.atomicReplacementFailed))
        XCTAssertNil(currentSnapshot)
    }

    func testCurrentSettingsReturnsDefaultAndPersistedAggregatesFromStore() async {
        let documents = InMemorySettingsDocumentAdapter()
        let store: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )
        let module = SuperModeConfigurationModule(
            store: store,
            runtime: SuperModeRuntimeConfiguration(),
            validator: SuperModeConfigurationValidator(actionRegistry: .builtIn)
        )

        let defaultResult = await module.currentSettings()

        XCTAssertEqual(
            defaultResult,
            .loaded(
                HotkeySettings(bindings: []),
                origin: .defaults(reason: .noDocument)
            )
        )

        let persistedConfiguration = configuration(
            timeout: 1_750,
            commands: [
                SuperModeCommandBinding(
                    hardwareKeyCodes: [4],
                    actionID: .leftHalf
                ),
            ]
        )
        let applyResult = await module.apply(
            persistedConfiguration,
            hotkeyBindings: []
        )
        guard case let .applied(persistedSettings, _) = applyResult else {
            return XCTFail("Expected configuration to apply")
        }

        let persistedResult = await module.currentSettings()

        XCTAssertEqual(
            persistedResult,
            .loaded(
                persistedSettings,
                origin: .persisted(schemaVersion: 3)
            )
        )
    }

    func testSuccessfulApplySavesBeforeReplacingRuntime() async {
        let operations = SuperModeConfigurationOperationLog()
        let store = RecordingSuperModeSettingsStore(operations: operations)
        let runtime = RecordingSuperModeRuntime(operations: operations)
        let module = SuperModeConfigurationModule(
            store: store,
            runtime: runtime,
            validator: SuperModeConfigurationValidator(actionRegistry: .builtIn)
        )
        let candidate = configuration(timeout: 1_500)

        let result = await module.apply(candidate, hotkeyBindings: [])

        guard case .applied = result else {
            return XCTFail("Expected configuration to apply")
        }
        XCTAssertEqual(
            operations.events,
            [
                .save(timeoutMilliseconds: 1_500),
                .runtimeReplace(timeoutMilliseconds: 1_500),
            ]
        )
    }

    func testConcurrentAppliesSerializeSaveAndRuntimeReplacementAsOneOperation() async {
        let operations = SuperModeConfigurationOperationLog()
        let store = RecordingSuperModeSettingsStore(
            operations: operations,
            pauseFirstSave: true
        )
        let runtime = RecordingSuperModeRuntime(operations: operations)
        let module = SuperModeConfigurationModule(
            store: store,
            runtime: runtime,
            validator: SuperModeConfigurationValidator(actionRegistry: .builtIn)
        )
        let firstConfiguration = configuration(timeout: 1_500)
        let secondConfiguration = configuration(timeout: 2_500)

        let firstApply = Task {
            await module.apply(firstConfiguration, hotkeyBindings: [])
        }
        await store.waitUntilFirstSaveStarts()

        let secondApply = Task {
            await module.apply(secondConfiguration, hotkeyBindings: [])
        }
        for _ in 0..<20 {
            await Task.yield()
        }

        let saveCountWhileFirstApplyIsSuspended = await store.saveCallCount
        XCTAssertEqual(saveCountWhileFirstApplyIsSuspended, 1)
        XCTAssertEqual(
            operations.events,
            [.save(timeoutMilliseconds: 1_500)]
        )

        await store.releaseFirstSave()
        let firstResult = await firstApply.value
        let secondResult = await secondApply.value
        let savedSettings = await store.currentSettings
        let runtimeSnapshot = await runtime.currentSnapshot

        guard case .applied = firstResult else {
            return XCTFail("Expected first configuration to apply")
        }
        guard case .applied = secondResult else {
            return XCTFail("Expected second configuration to apply")
        }
        XCTAssertEqual(savedSettings.superModeConfiguration, secondConfiguration)
        XCTAssertEqual(runtimeSnapshot?.configuration, secondConfiguration)
        XCTAssertEqual(
            operations.events,
            [
                .save(timeoutMilliseconds: 1_500),
                .runtimeReplace(timeoutMilliseconds: 1_500),
                .save(timeoutMilliseconds: 2_500),
                .runtimeReplace(timeoutMilliseconds: 2_500),
            ]
        )
    }

    private func configuration(
        prefix: HotkeyChord = SuperModeConfiguration.default.prefix,
        timeout: UInt32 = SuperModeConfiguration.defaultTimeoutMilliseconds,
        commands: [SuperModeCommandBinding] = []
    ) -> SuperModeConfiguration {
        SuperModeConfiguration(
            prefix: prefix,
            timeoutMilliseconds: timeout,
            commandBindings: commands
        )
    }

    private var prefixConflictingHotkey: HotkeyBinding {
        HotkeyBinding(
            id: UUID(uuidString: "A85D72CB-C4F8-4F62-BF28-243204AD649D")!,
            hardwareKeyCode: 49,
            modifiers: [.control],
            actionID: .maximize
        )
    }
}

private final class SuperModeConfigurationOperationLog: @unchecked Sendable {
    enum Event: Equatable {
        case save(timeoutMilliseconds: UInt32)
        case runtimeReplace(timeoutMilliseconds: UInt32)
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func record(_ event: Event) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }
}

private actor RecordingSuperModeSettingsStore: SettingsStoring {
    private let operations: SuperModeConfigurationOperationLog
    private let pauseFirstSave: Bool
    private var firstSaveRelease: CheckedContinuation<Void, Never>?
    private var firstSaveObserver: CheckedContinuation<Void, Never>?

    private(set) var currentSettings = HotkeySettings(bindings: [])
    private(set) var saveCallCount = 0

    init(
        operations: SuperModeConfigurationOperationLog,
        pauseFirstSave: Bool = false
    ) {
        self.operations = operations
        self.pauseFirstSave = pauseFirstSave
    }

    func load() async -> SettingsLoadResult {
        .loaded(currentSettings, origin: .persisted(schemaVersion: 2))
    }

    func save(_ settings: HotkeySettings) async -> SettingsSaveResult {
        saveCallCount += 1
        currentSettings = settings
        operations.record(
            .save(
                timeoutMilliseconds: settings.superModeConfiguration.timeoutMilliseconds
            )
        )

        if saveCallCount == 1, pauseFirstSave {
            firstSaveObserver?.resume()
            firstSaveObserver = nil
            await withCheckedContinuation { continuation in
                firstSaveRelease = continuation
            }
        }

        return .saved(schemaVersion: 2)
    }

    func waitUntilFirstSaveStarts() async {
        guard saveCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            firstSaveObserver = continuation
        }
    }

    func releaseFirstSave() {
        firstSaveRelease?.resume()
        firstSaveRelease = nil
    }
}

private actor RecordingSuperModeRuntime: SuperModeRuntimeConfigurationReplacing {
    private let operations: SuperModeConfigurationOperationLog
    private var lastRevision: UInt64 = 0
    private var activeSession: SuperModeRuntimeSession?
    private(set) var currentSnapshot: SuperModeRuntimeSnapshot?

    init(operations: SuperModeConfigurationOperationLog) {
        self.operations = operations
    }

    func replace(
        with validated: ValidatedSuperModeConfiguration
    ) -> SuperModeRuntimeSnapshot {
        lastRevision += 1
        operations.record(
            .runtimeReplace(
                timeoutMilliseconds: validated.configuration.timeoutMilliseconds
            )
        )
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

    func freshness(
        of revision: SuperModeConfigurationRevision
    ) -> SuperModeRuntimeFreshness {
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
