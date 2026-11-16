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

import AppKit
import ApplicationServices

public enum AccessibilityPermissionState: Equatable, Sendable {
    /// Trust is absent and the app has not yet directed the user to grant access.
    case notRequested
    /// Trust is absent after the app directed the user to grant access.
    case denied
    case granted
    /// Trust is absent after this installation previously observed a grant.
    case revoked
}

struct AccessibilityPermissionHistory: Equatable, Sendable {
    var userWasDirectedToGrantPermission = false
    var permissionHasBeenGranted = false
}

@MainActor
protocol AccessibilityPermissionHistoryAdapting: AnyObject {
    func load() -> AccessibilityPermissionHistory
    func save(_ history: AccessibilityPermissionHistory)
}

@MainActor
protocol AccessibilityPermissionAdapting {
    func isProcessTrusted() -> Bool
    func openSystemSettings() -> Bool
}

@MainActor
public final class AccessibilityPermissionManager {
    private let adapter: any AccessibilityPermissionAdapting
    private let historyAdapter: any AccessibilityPermissionHistoryAdapting
    private var history: AccessibilityPermissionHistory

    public private(set) var state: AccessibilityPermissionState

    public convenience init() {
        self.init(
            adapter: SystemAccessibilityPermissionAdapter(),
            historyAdapter: UserDefaultsAccessibilityPermissionHistoryAdapter()
        )
    }

    convenience init(adapter: any AccessibilityPermissionAdapting) {
        self.init(
            adapter: adapter,
            historyAdapter: TransientAccessibilityPermissionHistoryAdapter()
        )
    }

    init(
        adapter: any AccessibilityPermissionAdapting,
        historyAdapter: any AccessibilityPermissionHistoryAdapting
    ) {
        self.adapter = adapter
        self.historyAdapter = historyAdapter

        var history = historyAdapter.load()
        let isTrusted = adapter.isProcessTrusted()
        if isTrusted, !history.permissionHasBeenGranted {
            history.permissionHasBeenGranted = true
            historyAdapter.save(history)
        }

        self.history = history
        state = isTrusted ? .granted : Self.untrustedState(for: history)
    }

    @discardableResult
    public func refresh() -> AccessibilityPermissionState {
        if adapter.isProcessTrusted() {
            if !history.permissionHasBeenGranted {
                history.permissionHasBeenGranted = true
                historyAdapter.save(history)
            }
            state = .granted
        } else {
            state = Self.untrustedState(for: history)
        }

        return state
    }

    /// Records onboarding history; this method does not trigger a system prompt.
    @discardableResult
    public func recordUserWasDirectedToGrantPermission() -> AccessibilityPermissionState {
        if !history.userWasDirectedToGrantPermission {
            history.userWasDirectedToGrantPermission = true
            historyAdapter.save(history)
        }

        if state != .granted {
            state = Self.untrustedState(for: history)
        }

        return state
    }

    /// Opens the general System Settings app, not a promised preference pane.
    @discardableResult
    public func openSystemSettings() -> Bool {
        adapter.openSystemSettings()
    }

    private static func untrustedState(
        for history: AccessibilityPermissionHistory
    ) -> AccessibilityPermissionState {
        if history.permissionHasBeenGranted {
            return .revoked
        }

        return history.userWasDirectedToGrantPermission ? .denied : .notRequested
    }
}

@MainActor
private final class TransientAccessibilityPermissionHistoryAdapter:
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
private final class UserDefaultsAccessibilityPermissionHistoryAdapter:
    AccessibilityPermissionHistoryAdapting
{
    private enum Key {
        static let userWasDirectedToGrantPermission =
            "accessibility.user-was-directed-to-grant-permission"
        static let permissionHasBeenGranted =
            "accessibility.permission-has-been-granted"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AccessibilityPermissionHistory {
        AccessibilityPermissionHistory(
            userWasDirectedToGrantPermission: defaults.bool(
                forKey: Key.userWasDirectedToGrantPermission
            ),
            permissionHasBeenGranted: defaults.bool(
                forKey: Key.permissionHasBeenGranted
            )
        )
    }

    func save(_ history: AccessibilityPermissionHistory) {
        defaults.set(
            history.userWasDirectedToGrantPermission,
            forKey: Key.userWasDirectedToGrantPermission
        )
        defaults.set(
            history.permissionHasBeenGranted,
            forKey: Key.permissionHasBeenGranted
        )
    }
}

@MainActor
private struct SystemAccessibilityPermissionAdapter: AccessibilityPermissionAdapting {
    private static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func openSystemSettings() -> Bool {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.systemSettingsBundleIdentifier
        ) else {
            return false
        }

        return NSWorkspace.shared.open(applicationURL)
    }
}
