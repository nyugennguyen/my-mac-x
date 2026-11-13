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

public enum PermissionDiagnosticsStatus: String, Codable, Equatable, Sendable {
    case notRequested = "not-requested"
    case denied
    case granted
}

public enum EventTapDiagnosticsStatus: String, Codable, Equatable, Sendable {
    case stopped
    case active
    case recovering
    case unavailable
}

public enum AppDiagnosticsStatus: String, Codable, Equatable, Sendable {
    case starting
    case ready
    case limited
}

public enum EdgeSnapDiagnosticsStatus: String, Codable, Equatable, Sendable {
    case active
    case stoodDownSystemTiling = "stood-down-system-tiling"
    case disabled
}

/// A content-free numeric version. Free-form platform or application strings are intentionally
/// excluded from diagnostics input so they cannot smuggle user or machine data into a report.
public struct DiagnosticsVersion: Codable, Equatable, Sendable {
    public let major: UInt
    public let minor: UInt
    public let patch: UInt

    public init(major: UInt, minor: UInt, patch: UInt) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

/// The complete typed input accepted by the diagnostics report Module.
///
/// It deliberately has no host name, user name, hardware identifier, bundle identifier, window
/// identity, title, document text, input event, path, or arbitrary error-message field.
public struct DiagnosticsStatusSnapshot: Codable, Equatable, Sendable {
    public let accessibility: PermissionDiagnosticsStatus
    public let inputMonitoring: PermissionDiagnosticsStatus
    public let eventTap: EventTapDiagnosticsStatus
    public let operatingSystem: DiagnosticsVersion
    public let appVersion: DiagnosticsVersion
    public let appBuild: UInt
    public let app: AppDiagnosticsStatus
    public let edgeSnap: EdgeSnapDiagnosticsStatus?

    public init(
        accessibility: PermissionDiagnosticsStatus,
        inputMonitoring: PermissionDiagnosticsStatus,
        eventTap: EventTapDiagnosticsStatus,
        operatingSystem: DiagnosticsVersion,
        appVersion: DiagnosticsVersion,
        appBuild: UInt,
        app: AppDiagnosticsStatus,
        edgeSnap: EdgeSnapDiagnosticsStatus? = nil
    ) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.eventTap = eventTap
        self.operatingSystem = operatingSystem
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.app = app
        self.edgeSnap = edgeSnap
    }
}

public struct DiagnosticsReport: Equatable, Sendable {
    public let text: String

    fileprivate init(text: String) {
        self.text = text
    }
}

/// Produces a deterministic, copyable report exclusively from privacy-safe typed status.
public struct DiagnosticsReportBuilder: Sendable {
    public init() {}

    public func makeReport(from snapshot: DiagnosticsStatusSnapshot) -> DiagnosticsReport {
        var lines = [
            "My Mac X Diagnostics",
            "App version: \(snapshot.appVersion.reportValue) (\(snapshot.appBuild))",
            "App status: \(snapshot.app.rawValue)",
            "macOS: \(snapshot.operatingSystem.reportValue)",
            "Accessibility: \(snapshot.accessibility.rawValue)",
            "Input Monitoring: \(snapshot.inputMonitoring.rawValue)",
            "Event Tap: \(snapshot.eventTap.rawValue)",
        ]
        if let edgeSnap = snapshot.edgeSnap {
            lines.append("Edge Snap: \(edgeSnap.rawValue)")
        }
        lines.append("Privacy: window titles, document text, key input, host identity, and bundle identifiers are not collected")

        return DiagnosticsReport(text: lines.joined(separator: "\n"))
    }
}

private extension DiagnosticsVersion {
    var reportValue: String {
        "\(major).\(minor).\(patch)"
    }
}
