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

actor LocalSettingsDocumentAdapter: SettingsDocumentPersisting {
    let documentURL: URL
    private let fileManager: FileManager

    init(documentURL: URL, fileManager: FileManager = .default) {
        self.documentURL = documentURL
        self.fileManager = fileManager
    }

    func readDocument() async throws -> Data? {
        guard fileManager.fileExists(atPath: documentURL.path) else { return nil }
        do { return try Data(contentsOf: documentURL) }
        catch { throw SettingsDocumentPersistenceError.readFailed }
    }

    func replaceDocumentAtomically(with data: Data) async throws {
        let directory = documentURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let temporaryURL = directory.appendingPathComponent(".settings.\(UUID().uuidString).tmp")
            defer { try? fileManager.removeItem(at: temporaryURL) }
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            if fileManager.fileExists(atPath: documentURL.path) {
                _ = try fileManager.replaceItemAt(documentURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: documentURL)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: documentURL.path)
        } catch {
            throw SettingsDocumentPersistenceError.atomicReplacementFailed
        }
    }

    func quarantineCorruptDocument() async throws {
        guard fileManager.fileExists(atPath: documentURL.path) else { return }
        let quarantineURL = documentURL.deletingLastPathComponent().appendingPathComponent(
            "settings.corrupt.\(UUID().uuidString).json"
        )
        do {
            try fileManager.moveItem(at: documentURL, to: quarantineURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: quarantineURL.path)
        } catch {
            throw SettingsDocumentPersistenceError.quarantineFailed
        }
    }
}
