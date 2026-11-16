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

import CoreGraphics
import Foundation
import XCTest
@testable import MyMacX

final class ConfigurationArchiveTests: XCTestCase {
    func testExportAndImportRoundTripPortableConfiguration() throws {
        let archive = ConfigurationArchive(actionRegistry: .builtIn)
        let snapshot = try fixtureSnapshot()

        let data = try archive.export(snapshot)
        let result = archive.import(data)

        XCTAssertEqual(result, .imported(snapshot, origin: .current(schemaVersion: 4)))
    }

    func testExportContainsOnlyTheStrictPortableSchema() throws {
        let archive = ConfigurationArchive(actionRegistry: .builtIn)
        let data = try archive.export(fixtureSnapshot())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            ["schemaVersion", "general", "snapping", "hotkeyBindings", "superMode", "layouts", "displayProfiles", "appRules", "edgeSnap"]
        )
        XCTAssertNil(object["machineSecret"])
        XCTAssertNil(object["settingsPath"])
        XCTAssertNil(object["accessibilityTrust"])
    }

    func testV4RoundTripPreservesRuntimeSettingsAppRulesAndEdgeSnap() throws {
        let identifier = try XCTUnwrap(ApplicationBundleIdentifier("com.example.Editor"))
        let edgeSnap = EdgeSnapZoneConfigurationSnapshot(
            customActions: [.top: .topHalf],
            customPartitions: [.right: [.topHalf, .bottomHalf]],
            disabledZones: [.bottomLeft],
            seamGating: SeamGateSettings(isEnabled: false, crossingSpeedThreshold: 350.0)
        )
        let snapshot = ConfigurationSnapshot(
            general: GeneralSettings(launchesAtLogin: true),
            snapping: SnappingSettings(
                isEnabled: false,
                trigger: .topCenter,
                dwellMilliseconds: 275,
                showsPlacementPreview: false,
                usesReducedEffects: true
            ),
            hotkeySettings: HotkeySettings(bindings: []),
            layouts: [],
            displayProfiles: [],
            appRulePolicy: AppRulePolicy(
                unmatched: .excluded,
                rules: [AppRule(bundleIdentifier: identifier, decision: .included)]
            ),
            edgeSnap: edgeSnap
        )
        let archive = ConfigurationArchive(actionRegistry: .builtIn)

        XCTAssertEqual(
            archive.import(try archive.export(snapshot)),
            .imported(snapshot, origin: .current(schemaVersion: 4))
        )
    }

    func testExportAppliesDeltaCompactionToDefaultEdgeSnap() throws {
        let archive = ConfigurationArchive(actionRegistry: .builtIn)
        let data = try archive.export(try fixtureSnapshot())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let edgeSnap = try XCTUnwrap(object["edgeSnap"] as? [String: Any])

        XCTAssertEqual(edgeSnap["zoneActions"] as? String, "")
        XCTAssertEqual((edgeSnap["disabledZones"] as? [String])?.isEmpty, true)
    }

    func testV3ImportMigratesWithDefaultEdgeSnapConfiguration() throws {
        let v3JSON = Data("""
        {
            "schemaVersion": 3,
            "general": {"launchesAtLogin": false},
            "snapping": {"isEnabled": true, "trigger": "notch", "dwellMilliseconds": 150, "showsPlacementPreview": true, "usesReducedEffects": false},
            "hotkeyBindings": [],
            "superMode": {"prefix": {"hardwareKeyCode": 49, "modifiers": 4}, "timeoutMilliseconds": 1000, "commandBindings": []},
            "layouts": [],
            "displayProfiles": [],
            "appRules": {"unmatched": "included", "rules": []}
        }
        """.utf8)
        let archive = ConfigurationArchive(actionRegistry: .builtIn)
        let result = archive.import(v3JSON)

        let expected = ConfigurationSnapshot(
            general: GeneralSettings(launchesAtLogin: false),
            snapping: SnappingSettings(
                isEnabled: true,
                trigger: .notch,
                dwellMilliseconds: 150,
                showsPlacementPreview: true,
                usesReducedEffects: false
            ),
            hotkeySettings: HotkeySettings(
                bindings: [],
                superModeConfiguration: SuperModeConfiguration(
                    prefix: HotkeyChord(hardwareKeyCode: 49, modifiers: HotkeyModifiers(rawValue: 4)),
                    timeoutMilliseconds: 1000,
                    commandBindings: []
                )
            ),
            layouts: [],
            displayProfiles: [],
            appRulePolicy: AppRulePolicy(),
            edgeSnap: EdgeSnapZoneConfigurationSnapshot()
        )
        XCTAssertEqual(result, .imported(expected, origin: .migrated(fromVersion: 3, toVersion: 4)))
    }

    func testV4ImportDegradesSafelyOnUnknownFieldInEdgeSnapAndSurfacesAnomaly() throws {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)
        let archive = ConfigurationArchive(actionRegistry: .builtIn, diagnosticsLogger: logger)

        let v4WithUnknownField = Data("""
        {
            "schemaVersion": 4,
            "general": {"launchesAtLogin": false},
            "snapping": {"isEnabled": true, "trigger": "notch", "dwellMilliseconds": 150, "showsPlacementPreview": true, "usesReducedEffects": false},
            "hotkeyBindings": [],
            "superMode": {"prefix": {"hardwareKeyCode": 49, "modifiers": 4}, "timeoutMilliseconds": 1000, "commandBindings": []},
            "layouts": [],
            "displayProfiles": [],
            "appRules": {"unmatched": "included", "rules": []},
            "edgeSnap": {
                "zoneActions": "top=window.top-half",
                "disabledZones": ["bottomLeft"],
                "seamGating": {"isEnabled": true, "crossingSpeedThreshold": 400},
                "futureFeatureFlag": true
            }
        }
        """.utf8)

        let result = archive.import(v4WithUnknownField)
        guard case let .imported(snapshot, origin) = result else {
            XCTFail("Expected imported snapshot but got \(result)")
            return
        }

        XCTAssertEqual(origin, .current(schemaVersion: 4))
        XCTAssertEqual(snapshot.edgeSnap.customActions[.top], .topHalf)
        XCTAssertEqual(snapshot.edgeSnap.disabledZones, [.bottomLeft])
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])
    }

    func testImportRejectsUnknownMachineSecretField() {
        let data = Data("""
        {"schemaVersion":2,"hotkeyBindings":[],"superMode":{"prefix":{"hardwareKeyCode":49,"modifiers":4},"timeoutMilliseconds":1000,"commandBindings":[]},"layouts":[],"displayProfiles":[],"machineSecret":"never import me"}
        """.utf8)

        XCTAssertEqual(
            ConfigurationArchive(actionRegistry: .builtIn).import(data),
            .rejected(.malformedOrUnexpectedSchema)
        )
    }

    func testImportRejectsOverlappingLayoutWithoutReturningPartialConfiguration() {
        let data = Data("""
        {"schemaVersion":2,"hotkeyBindings":[],"superMode":{"prefix":{"hardwareKeyCode":49,"modifiers":4},"timeoutMilliseconds":1000,"commandBindings":[]},"layouts":[{"id":"bad","name":"Bad","regions":[{"id":"left","x":0,"y":0,"width":0.6,"height":1},{"id":"right","x":0.5,"y":0,"width":0.5,"height":1}]}],"displayProfiles":[]}
        """.utf8)

        XCTAssertEqual(
            ConfigurationArchive(actionRegistry: .builtIn).import(data),
            .rejected(.invalidConfiguration(.layout(
                layoutID: "bad",
                failure: .overlappingRegions(
                    LayoutRegionID(rawValue: "left"),
                    LayoutRegionID(rawValue: "right")
                )
            )))
        )
    }

    func testV1ImportMigratesWithDefaultSuperModeConfiguration() throws {
        let data = Data("""
        {"schemaVersion":1,"hotkeyBindings":[],"layouts":[],"displayProfiles":[]}
        """.utf8)
        let expected = ConfigurationSnapshot(
            hotkeySettings: HotkeySettings(bindings: []),
            layouts: [],
            displayProfiles: []
        )

        XCTAssertEqual(
            ConfigurationArchive(actionRegistry: .builtIn).import(data),
            .imported(expected, origin: .migrated(fromVersion: 1, toVersion: 4))
        )
    }

    func testImportRejectsFutureSchemaWithoutTryingToMigrateIt() {
        let data = Data("""
        {"schemaVersion":99,"hotkeyBindings":[],"layouts":[],"displayProfiles":[]}
        """.utf8)

        XCTAssertEqual(
            ConfigurationArchive(actionRegistry: .builtIn).import(data),
            .rejected(.unsupportedFutureVersion(99))
        )
    }

    func testImportRejectsOversizedInputBeforeParsing() {
        let data = Data(repeating: 0x20, count: ConfigurationArchive.maximumDocumentSize + 1)

        XCTAssertEqual(
            ConfigurationArchive(actionRegistry: .builtIn).import(data),
            .rejected(.documentTooLarge(maximumBytes: ConfigurationArchive.maximumDocumentSize))
        )
    }

    func testUnicodeLayoutNameRoundTripsWithoutMojibake() throws {
        let snapshot = ConfigurationSnapshot(
            hotkeySettings: HotkeySettings(bindings: []),
            layouts: [LayoutDraft(
                id: "viet",
                name: "Bố cục viết",
                regions: [region("full", x: 0, y: 0, width: 1, height: 1)]
            )],
            displayProfiles: []
        )
        let archive = ConfigurationArchive(actionRegistry: .builtIn)

        let result = archive.import(try archive.export(snapshot))

        XCTAssertEqual(result, .imported(snapshot, origin: .current(schemaVersion: 4)))
    }

    private func fixtureSnapshot() throws -> ConfigurationSnapshot {
        let layout = LayoutDraft(
            id: "writing",
            name: "Writing",
            regions: [
                region("editor", x: 0, y: 0, width: 0.7, height: 1),
                region("notes", x: 0.7, y: 0, width: 0.3, height: 1),
            ]
        )
        let profile = try DisplayProfile(
            stableDisplayID: StableDisplayID(rawValue: "uuid:external"),
            gap: 12,
            layoutIDs: ["built-in", "writing"]
        )
        return ConfigurationSnapshot(
            hotkeySettings: HotkeySettings(bindings: []),
            layouts: [layout],
            displayProfiles: [profile]
        )
    }

    private func region(
        _ id: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> LayoutRegionDraft {
        LayoutRegionDraft(
            id: LayoutRegionID(rawValue: id),
            normalizedFrame: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}

private final class RecordingDiagnosticsWriter: DiagnosticsLogWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEntries: [DiagnosticsLogEntry] = []

    var entries: [DiagnosticsLogEntry] {
        lock.withLock { storedEntries }
    }

    func write(_ entry: DiagnosticsLogEntry) {
        lock.withLock {
            storedEntries.append(entry)
        }
    }
}
