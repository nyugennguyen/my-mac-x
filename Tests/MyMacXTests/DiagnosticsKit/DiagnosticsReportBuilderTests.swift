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

final class DiagnosticsReportBuilderTests: XCTestCase {
    func testReportContainsOnlyTypedPermissionTapOSAndAppStatus() {
        let report = DiagnosticsReportBuilder().makeReport(
            from: DiagnosticsStatusSnapshot(
                accessibility: .granted,
                inputMonitoring: .denied,
                eventTap: .unavailable,
                operatingSystem: DiagnosticsVersion(major: 15, minor: 6, patch: 1),
                appVersion: DiagnosticsVersion(major: 0, minor: 6, patch: 0),
                appBuild: 42,
                app: .limited
            )
        )

        XCTAssertEqual(
            report.text,
            """
            My Mac X Diagnostics
            App version: 0.6.0 (42)
            App status: limited
            macOS: 15.6.1
            Accessibility: granted
            Input Monitoring: denied
            Event Tap: unavailable
            Privacy: window titles, document text, key input, host identity, and bundle identifiers are not collected
            """
        )
    }

    func testEveryStatusRendersAsAStableContentFreeToken() {
        for (status, token) in [
            (PermissionDiagnosticsStatus.notRequested, "not-requested"),
            (.denied, "denied"),
            (.granted, "granted"),
        ] {
            let report = DiagnosticsReportBuilder().makeReport(
                from: snapshot(accessibility: status, inputMonitoring: status)
            )
            XCTAssertTrue(report.text.contains("Accessibility: \(token)"))
            XCTAssertTrue(report.text.contains("Input Monitoring: \(token)"))
        }

        for (status, token) in [
            (EventTapDiagnosticsStatus.stopped, "stopped"),
            (.active, "active"),
            (.recovering, "recovering"),
            (.unavailable, "unavailable"),
        ] {
            let report = DiagnosticsReportBuilder().makeReport(
                from: snapshot(eventTap: status)
            )
            XCTAssertTrue(report.text.contains("Event Tap: \(token)"))
        }

        for (status, token) in [
            (AppDiagnosticsStatus.starting, "starting"),
            (.ready, "ready"),
            (.limited, "limited"),
        ] {
            let report = DiagnosticsReportBuilder().makeReport(from: snapshot(app: status))
            XCTAssertTrue(report.text.contains("App status: \(token)"))
        }
    }

    func testReportIncludesEdgeSnapTilingWhenPresent() {
        let snapshot = DiagnosticsStatusSnapshot(
            accessibility: .granted,
            inputMonitoring: .granted,
            eventTap: .active,
            operatingSystem: DiagnosticsVersion(major: 15, minor: 0, patch: 0),
            appVersion: DiagnosticsVersion(major: 1, minor: 0, patch: 0),
            appBuild: 1,
            app: .ready,
            edgeSnap: .stoodDownSystemTiling
        )
        let report = DiagnosticsReportBuilder().makeReport(from: snapshot)
        XCTAssertTrue(report.text.contains("Edge Snap: stood-down-system-tiling"))
    }

    private func snapshot(
        accessibility: PermissionDiagnosticsStatus = .granted,
        inputMonitoring: PermissionDiagnosticsStatus = .granted,
        eventTap: EventTapDiagnosticsStatus = .active,
        app: AppDiagnosticsStatus = .ready
    ) -> DiagnosticsStatusSnapshot {
        DiagnosticsStatusSnapshot(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            eventTap: eventTap,
            operatingSystem: DiagnosticsVersion(major: 15, minor: 6, patch: 1),
            appVersion: DiagnosticsVersion(major: 0, minor: 6, patch: 0),
            appBuild: 42,
            app: app
        )
    }
}
