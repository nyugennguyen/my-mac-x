import Foundation
@testable import MyMacX

actor InMemorySettingsDocumentAdapter: SettingsDocumentPersisting {
    enum ReplacementOutcome: Sendable { case succeeds, fails, notWritable }

    private(set) var document: Data?
    private(set) var replacementOutcome: ReplacementOutcome = .succeeds
    private(set) var quarantineSucceeds = true

    init(document: Data? = nil) { self.document = document }

    func setReplacementOutcome(_ outcome: ReplacementOutcome) { replacementOutcome = outcome }
    func setQuarantineSucceeds(_ succeeds: Bool) { quarantineSucceeds = succeeds }

    func readDocument() async throws -> Data? { document }

    func replaceDocumentAtomically(with data: Data) async throws {
        switch replacementOutcome {
        case .succeeds: document = data
        case .fails: throw SettingsDocumentPersistenceError.atomicReplacementFailed
        case .notWritable: throw SettingsDocumentPersistenceError.documentNotWritable
        }
    }

    func quarantineCorruptDocument() async throws {
        guard quarantineSucceeds else { throw SettingsDocumentPersistenceError.quarantineFailed }
        document = nil
    }
}
