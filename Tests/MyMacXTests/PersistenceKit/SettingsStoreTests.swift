import XCTest
@testable import MyMacX

final class SettingsStoreTests: XCTestCase {
    func testSaveAndLoadConfigurationAtomicallyPreservesAllSprint6Settings() async throws {
        let documents = InMemorySettingsDocumentAdapter()
        let store = SettingsStore(documents: documents, actionRegistry: .builtIn)
        let identifier = try XCTUnwrap(ApplicationBundleIdentifier("com.example.Editor"))
        let edgeSnap = EdgeSnapZoneConfigurationSnapshot(
            customActions: [.top: .topHalf],
            customPartitions: [.right: [.topHalf, .bottomHalf]],
            disabledZones: [.bottomLeft],
            seamGating: SeamGateSettings(isEnabled: false, crossingSpeedThreshold: 350.0)
        )
        let snapshot = ConfigurationSnapshot(
            general: GeneralSettings(launchesAtLogin: true),
            snapping: SnappingSettings(isEnabled: false, trigger: .topCenter, dwellMilliseconds: 275, showsPlacementPreview: false, usesReducedEffects: true),
            hotkeySettings: HotkeySettings(bindings: [fixtureBinding]),
            layouts: [LayoutDraft(id: "wide", name: "Wide", regions: [LayoutRegionDraft(id: LayoutRegionID(rawValue: "all"), normalizedFrame: CGRect(x: 0, y: 0, width: 1, height: 1))])],
            displayProfiles: [try DisplayProfile(stableDisplayID: StableDisplayID(rawValue: "uuid:main"), gap: 8, layoutIDs: ["wide"])],
            appRulePolicy: AppRulePolicy(unmatched: .included, rules: [AppRule(bundleIdentifier: identifier, decision: .excluded)]),
            edgeSnap: edgeSnap
        )

        let saveResult = await store.saveConfiguration(snapshot)
        let loadResult = await store.loadConfiguration()
        XCTAssertEqual(saveResult, .saved(schemaVersion: 4))
        XCTAssertEqual(
            loadResult,
            .loaded(snapshot, origin: .persisted(schemaVersion: 4))
        )
    }
    func testMissingDocumentLoadsEmptyDefaultsWithoutWriting() async {
        let documents = InMemorySettingsDocumentAdapter()
        let store: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )

        let result = await store.load()
        let persistedDocument = await documents.document

        XCTAssertEqual(
            result,
            .loaded(HotkeySettings(bindings: []), origin: .defaults(reason: .noDocument))
        )
        XCTAssertNil(persistedDocument)
    }

    func testSaveAndFreshStoreLoadPreservePrefixTimeoutAndCommandPaths() async {
        let documents = InMemorySettingsDocumentAdapter()
        let settings = HotkeySettings(
            bindings: [fixtureBinding],
            superModeConfiguration: fixtureConfiguration
        )
        let store: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )

        let saveResult = await store.save(settings)
        XCTAssertEqual(saveResult, .saved(schemaVersion: 4))

        let reloaded: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )
        let reloadedResult = await reloaded.load()
        XCTAssertEqual(
            reloadedResult,
            .loaded(settings, origin: .persisted(schemaVersion: 4))
        )
    }

    func testV0DocumentMigratesToV2WithDefaultSuperModeConfiguration() async {
        let documents = InMemorySettingsDocumentAdapter(document: Data("""
        {"bindings":[{"id":"90E0D434-DA13-4DB4-8CB2-54E5A832D62B","keyCode":123,"modifiers":3,"actionID":"window.left-half"}]}
        """.utf8))
        let settings = HotkeySettings(bindings: [fixtureBinding])
        let store: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )

        let migratedResult = await store.load()
        XCTAssertEqual(
            migratedResult,
            .loaded(settings, origin: .migrated(fromVersion: 0, toVersion: 4))
        )

        let reloaded: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )
        let reloadedResult = await reloaded.load()
        XCTAssertEqual(
            reloadedResult,
            .loaded(settings, origin: .persisted(schemaVersion: 4))
        )
    }

    func testV1DocumentMigratesToV2WithoutChangingHotkeys() async {
        let documents = InMemorySettingsDocumentAdapter(document: Data("""
        {"schemaVersion":1,"hotkeyBindings":[{"id":"90E0D434-DA13-4DB4-8CB2-54E5A832D62B","hardwareKeyCode":123,"modifiers":3,"actionID":"window.left-half"}]}
        """.utf8))
        let settings = HotkeySettings(bindings: [fixtureBinding])
        let store: any SettingsStoring = SettingsStore(
            documents: documents,
            actionRegistry: .builtIn
        )

        let result = await store.load()
        let replacementCallCount = await documents.replacementCallCount

        XCTAssertEqual(
            result,
            .loaded(settings, origin: .migrated(fromVersion: 1, toVersion: 4))
        )
        XCTAssertEqual(replacementCallCount, 1)
    }

    func testMalformedDocumentQuarantinesThenAllowsSave() async {
        let documents = InMemorySettingsDocumentAdapter(document: Data("{not json".utf8))
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)

        let loadResult = await store.load()
        XCTAssertEqual(loadResult, .loaded(HotkeySettings(bindings: []), origin: .defaults(reason: .corruptDocumentQuarantined)))
        let saveResult = await store.save(HotkeySettings(bindings: [fixtureBinding]))
        XCTAssertEqual(saveResult, .saved(schemaVersion: 4))
    }

    func testUnquarantinableCorruptDocumentBlocksSave() async {
        let documents = InMemorySettingsDocumentAdapter(document: Data("{not json".utf8))
        await documents.setQuarantineSucceeds(false)
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)

        let loadResult = await store.load()
        XCTAssertEqual(loadResult, .loaded(HotkeySettings(bindings: []), origin: .defaults(reason: .corruptDocumentCouldNotBeQuarantined)))
        let saveResult = await store.save(HotkeySettings(bindings: [fixtureBinding]))
        XCTAssertEqual(saveResult, .failed(.recoveryRequired))
    }

    func testReplacementFailurePreservesPriorSnapshotForFreshStore() async {
        let settings = HotkeySettings(bindings: [fixtureBinding])
        let documents = InMemorySettingsDocumentAdapter()
        let initialStore: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)
        let initialSaveResult = await initialStore.save(settings)
        XCTAssertEqual(initialSaveResult, .saved(schemaVersion: 4))
        await documents.setReplacementOutcome(.fails)

        let failedSaveResult = await initialStore.save(HotkeySettings(bindings: []))
        XCTAssertEqual(failedSaveResult, .failed(.atomicReplacementFailed))

        let reloaded: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)
        let reloadedResult = await reloaded.load()
        XCTAssertEqual(reloadedResult, .loaded(settings, origin: .persisted(schemaVersion: 4)))
    }

    func testUnsafePersistedBindingRecoversWithoutReturningIt() async {
        let documents = InMemorySettingsDocumentAdapter(document: Data("""
        {"schemaVersion":1,"hotkeyBindings":[{"id":"90E0D434-DA13-4DB4-8CB2-54E5A832D62B","hardwareKeyCode":123,"modifiers":16,"actionID":"window.unknown"}]}
        """.utf8))
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)

        let loadResult = await store.load()
        XCTAssertEqual(loadResult, .loaded(HotkeySettings(bindings: []), origin: .defaults(reason: .corruptDocumentQuarantined)))
    }

    func testUnavailableRegisteredActionLoadsUnchanged() async {
        let unavailable = ActionDescriptor(
            id: ActionID(rawValue: "window.experimental"),
            title: "Experimental",
            symbolName: "sparkles",
            availability: .unavailable(.experimental)
        )
        let binding = HotkeyBinding(id: fixtureBinding.id, hardwareKeyCode: 123, modifiers: [.command], actionID: unavailable.id)
        let documents = InMemorySettingsDocumentAdapter(document: Data("""
        {"schemaVersion":1,"hotkeyBindings":[{"id":"90E0D434-DA13-4DB4-8CB2-54E5A832D62B","hardwareKeyCode":123,"modifiers":1,"actionID":"window.experimental"}]}
        """.utf8))
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: ActionRegistry(actions: [unavailable]))

        let loadResult = await store.load()
        XCTAssertEqual(
            loadResult,
            .loaded(
                HotkeySettings(bindings: [binding]),
                origin: .migrated(fromVersion: 1, toVersion: 4)
            )
        )
    }

    func testFutureVersionIsPreservedAndSaveIsBlocked() async {
        let future = Data("{\"schemaVersion\":5,\"hotkeyBindings\":[]}".utf8)
        let documents = InMemorySettingsDocumentAdapter(document: future)
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)

        let loadResult = await store.load()
        XCTAssertEqual(loadResult, .loaded(HotkeySettings(bindings: []), origin: .defaults(reason: .unsupportedFutureVersion)))
        let saveResult = await store.save(HotkeySettings(bindings: [fixtureBinding]))
        let preservedDocument = await documents.document
        XCTAssertEqual(saveResult, .failed(.recoveryRequired))
        XCTAssertEqual(preservedDocument, future)
    }

    func testStructurallyUnsafeSaveIsRejectedWithoutConflictPolicy() async {
        let documents = InMemorySettingsDocumentAdapter()
        let duplicate = HotkeyBinding(id: fixtureBinding.id, hardwareKeyCode: 124, modifiers: [], actionID: .rightHalf)
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)

        let saveResult = await store.save(HotkeySettings(bindings: [fixtureBinding, duplicate]))
        let persistedDocument = await documents.document
        XCTAssertEqual(saveResult, .failed(.structurallyInvalid))
        XCTAssertNil(persistedDocument)
    }

    private var fixtureConfiguration: SuperModeConfiguration {
        SuperModeConfiguration(
            prefix: HotkeyChord(hardwareKeyCode: 49, modifiers: [.control, .option]),
            timeoutMilliseconds: 1_750,
            commandBindings: [
                SuperModeCommandBinding(hardwareKeyCodes: [0], actionID: .maximize),
                SuperModeCommandBinding(
                    hardwareKeyCodes: [1, 2],
                    actionID: .rightHalf
                ),
            ]
        )
    }

    private var fixtureBinding: HotkeyBinding {
        HotkeyBinding(
            id: UUID(uuidString: "90E0D434-DA13-4DB4-8CB2-54E5A832D62B")!,
            hardwareKeyCode: 123,
            modifiers: [.command, .option],
            actionID: .leftHalf
        )
    }
}
