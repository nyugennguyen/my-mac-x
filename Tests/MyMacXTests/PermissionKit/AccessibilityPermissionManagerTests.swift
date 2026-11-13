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

import XCTest
@testable import MyMacX

@MainActor
final class AccessibilityPermissionManagerTests: XCTestCase {
    func testFreshUntrustedInstallIsNotRequested() {
        let adapter = ScriptedAccessibilityPermissionAdapter(
            trustStates: [false, false]
        )
        let manager = AccessibilityPermissionManager(
            adapter: adapter,
            historyAdapter: InMemoryAccessibilityPermissionHistoryAdapter()
        )

        XCTAssertEqual(manager.state, .notRequested)
        XCTAssertEqual(manager.refresh(), .notRequested)
    }

    func testDirectingUserToGrantPermissionChangesUntrustedStateToDenied() {
        let adapter = ScriptedAccessibilityPermissionAdapter(
            trustStates: [false]
        )
        let manager = AccessibilityPermissionManager(
            adapter: adapter,
            historyAdapter: InMemoryAccessibilityPermissionHistoryAdapter()
        )

        XCTAssertEqual(manager.recordUserWasDirectedToGrantPermission(), .denied)
        XCTAssertEqual(manager.state, .denied)
    }

    func testDirectedHistoryPersistsAcrossManagerRecreation() {
        let history = InMemoryAccessibilityPermissionHistoryAdapter()
        let firstManager = AccessibilityPermissionManager(
            adapter: ScriptedAccessibilityPermissionAdapter(trustStates: [false]),
            historyAdapter: history
        )

        XCTAssertEqual(firstManager.recordUserWasDirectedToGrantPermission(), .denied)

        let recreatedManager = AccessibilityPermissionManager(
            adapter: ScriptedAccessibilityPermissionAdapter(trustStates: [false]),
            historyAdapter: history
        )

        XCTAssertEqual(recreatedManager.state, .denied)
    }

    func testRefreshReportsGrantAfterUserWasDirected() {
        let adapter = ScriptedAccessibilityPermissionAdapter(
            trustStates: [false, true]
        )
        let manager = AccessibilityPermissionManager(
            adapter: adapter,
            historyAdapter: InMemoryAccessibilityPermissionHistoryAdapter()
        )

        XCTAssertEqual(manager.recordUserWasDirectedToGrantPermission(), .denied)
        XCTAssertEqual(manager.refresh(), .granted)
    }

    func testRefreshReportsRevokedAfterARecordedGrantIsLost() {
        let adapter = ScriptedAccessibilityPermissionAdapter(
            trustStates: [false, true, false]
        )
        let manager = AccessibilityPermissionManager(
            adapter: adapter,
            historyAdapter: InMemoryAccessibilityPermissionHistoryAdapter()
        )

        XCTAssertEqual(manager.recordUserWasDirectedToGrantPermission(), .denied)
        XCTAssertEqual(manager.refresh(), .granted)
        XCTAssertEqual(manager.refresh(), .revoked)
    }

    func testRefreshRemainsDeniedUntilTrustHasBeenGranted() {
        let adapter = ScriptedAccessibilityPermissionAdapter(
            trustStates: [false, false]
        )
        let manager = AccessibilityPermissionManager(
            adapter: adapter,
            historyAdapter: InMemoryAccessibilityPermissionHistoryAdapter()
        )

        XCTAssertEqual(manager.recordUserWasDirectedToGrantPermission(), .denied)
        XCTAssertEqual(manager.refresh(), .denied)
    }

    func testGrantedHistoryReportsRevokedAfterManagerRecreation() {
        let history = InMemoryAccessibilityPermissionHistoryAdapter()
        let firstManager = AccessibilityPermissionManager(
            adapter: ScriptedAccessibilityPermissionAdapter(
                trustStates: [false, true]
            ),
            historyAdapter: history
        )

        XCTAssertEqual(firstManager.recordUserWasDirectedToGrantPermission(), .denied)
        XCTAssertEqual(firstManager.refresh(), .granted)

        let recreatedManager = AccessibilityPermissionManager(
            adapter: ScriptedAccessibilityPermissionAdapter(trustStates: [false]),
            historyAdapter: history
        )

        XCTAssertEqual(recreatedManager.state, .revoked)
    }

    func testOpenSystemSettingsUsesTheSettingsOpener() {
        let adapter = ScriptedAccessibilityPermissionAdapter(
            trustStates: [false],
            opensSettings: true
        )
        let manager = AccessibilityPermissionManager(
            adapter: adapter,
            historyAdapter: InMemoryAccessibilityPermissionHistoryAdapter()
        )

        XCTAssertTrue(manager.openSystemSettings())
        XCTAssertEqual(adapter.settingsOpenCount, 1)
    }
}

@MainActor
private final class InMemoryAccessibilityPermissionHistoryAdapter:
    AccessibilityPermissionHistoryAdapting
{
    private var history = AccessibilityPermissionHistory()

    func load() -> AccessibilityPermissionHistory {
        history
    }

    func save(_ history: AccessibilityPermissionHistory) {
        self.history = history
    }
}

@MainActor
private final class ScriptedAccessibilityPermissionAdapter: AccessibilityPermissionAdapting {
    private var trustStates: [Bool]
    private let opensSettings: Bool

    private(set) var settingsOpenCount = 0

    init(trustStates: [Bool], opensSettings: Bool = false) {
        precondition(!trustStates.isEmpty)
        self.trustStates = trustStates
        self.opensSettings = opensSettings
    }

    func isProcessTrusted() -> Bool {
        if trustStates.count == 1 {
            return trustStates[0]
        }

        return trustStates.removeFirst()
    }

    func openSystemSettings() -> Bool {
        settingsOpenCount += 1
        return opensSettings
    }
}
