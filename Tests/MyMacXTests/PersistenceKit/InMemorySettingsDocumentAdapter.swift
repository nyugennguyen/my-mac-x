// MyMacX
// Copyright (C) 2026 NyugenNguyen
//
// This program is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the LICENSE file for details.

import Foundation
@testable import MyMacX

actor InMemorySettingsDocumentAdapter: SettingsDocumentPersisting {
    enum ReplacementOutcome: Sendable { case succeeds, fails, notWritable }

    private(set) var document: Data?
    private(set) var replacementOutcome: ReplacementOutcome = .succeeds
    private(set) var quarantineSucceeds = true
    private(set) var replacementCallCount = 0

    init(document: Data? = nil) { self.document = document }

    func setReplacementOutcome(_ outcome: ReplacementOutcome) { replacementOutcome = outcome }
    func setQuarantineSucceeds(_ succeeds: Bool) { quarantineSucceeds = succeeds }

    func readDocument() async throws -> Data? { document }

    func replaceDocumentAtomically(with data: Data) async throws {
        replacementCallCount += 1
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
