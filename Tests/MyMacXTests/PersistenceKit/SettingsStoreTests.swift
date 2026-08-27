import XCTest
@testable import MyMacX

final class SettingsStoreTests: XCTestCase {
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

    func testSaveAndFreshStoreLoadPreserveExactBindingSnapshot() async {
        let documents = InMemorySettingsDocumentAdapter()
        let settings = HotkeySettings(bindings: [fixtureBinding])
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)

        let saveResult = await store.save(settings)
        XCTAssertEqual(saveResult, .saved(schemaVersion: 1))

        let reloaded: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)
        let reloadedResult = await reloaded.load()
        XCTAssertEqual(reloadedResult, .loaded(settings, origin: .persisted(schemaVersion: 1)))
    }

    func testV0DocumentMigratesThenFreshStoreReportsV1Persistence() async {
        let documents = InMemorySettingsDocumentAdapter(document: Data("""
        {"bindings":[{"id":"90E0D434-DA13-4DB4-8CB2-54E5A832D62B","keyCode":123,"modifiers":3,"actionID":"window.left-half"}]}
        """.utf8))
        let settings = HotkeySettings(bindings: [fixtureBinding])
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)

        let migratedResult = await store.load()
        XCTAssertEqual(migratedResult, .loaded(settings, origin: .migrated(fromVersion: 0, toVersion: 1)))

        let reloaded: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)
        let reloadedResult = await reloaded.load()
        XCTAssertEqual(reloadedResult, .loaded(settings, origin: .persisted(schemaVersion: 1)))
    }

    func testMalformedDocumentQuarantinesThenAllowsSave() async {
        let documents = InMemorySettingsDocumentAdapter(document: Data("{not json".utf8))
        let store: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)

        let loadResult = await store.load()
        XCTAssertEqual(loadResult, .loaded(HotkeySettings(bindings: []), origin: .defaults(reason: .corruptDocumentQuarantined)))
        let saveResult = await store.save(HotkeySettings(bindings: [fixtureBinding]))
        XCTAssertEqual(saveResult, .saved(schemaVersion: 1))
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
        XCTAssertEqual(initialSaveResult, .saved(schemaVersion: 1))
        await documents.setReplacementOutcome(.fails)

        let failedSaveResult = await initialStore.save(HotkeySettings(bindings: []))
        XCTAssertEqual(failedSaveResult, .failed(.atomicReplacementFailed))

        let reloaded: any SettingsStoring = SettingsStore(documents: documents, actionRegistry: .builtIn)
        let reloadedResult = await reloaded.load()
        XCTAssertEqual(reloadedResult, .loaded(settings, origin: .persisted(schemaVersion: 1)))
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
        XCTAssertEqual(loadResult, .loaded(HotkeySettings(bindings: [binding]), origin: .persisted(schemaVersion: 1)))
    }

    func testFutureVersionIsPreservedAndSaveIsBlocked() async {
        let future = Data("{\"schemaVersion\":2,\"hotkeyBindings\":[]}".utf8)
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

    private var fixtureBinding: HotkeyBinding {
        HotkeyBinding(
            id: UUID(uuidString: "90E0D434-DA13-4DB4-8CB2-54E5A832D62B")!,
            hardwareKeyCode: 123,
            modifiers: [.command, .option],
            actionID: .leftHalf
        )
    }
}
