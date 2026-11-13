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
import CoreGraphics
import Foundation

/// Snapshot of macOS system window tiling configuration (Z-09).
public struct SystemTilingState: Equatable, Sendable {
    public let isEdgeTilingEnabled: Bool
    public let isTopTilingEnabled: Bool
    public let isOptionAcceleratorEnabled: Bool
    public let screensHaveSeparateSpaces: Bool
    public let operatingSystemMajorVersion: Int

    public init(
        isEdgeTilingEnabled: Bool,
        isTopTilingEnabled: Bool,
        isOptionAcceleratorEnabled: Bool,
        screensHaveSeparateSpaces: Bool,
        operatingSystemMajorVersion: Int = 15
    ) {
        self.isEdgeTilingEnabled = isEdgeTilingEnabled
        self.isTopTilingEnabled = isTopTilingEnabled
        self.isOptionAcceleratorEnabled = isOptionAcceleratorEnabled
        self.screensHaveSeparateSpaces = screensHaveSeparateSpaces
        self.operatingSystemMajorVersion = operatingSystemMajorVersion
    }
}

/// Reason describing why MyMacX edge snapping stood down for native system tiling.
public struct SystemTilingStandDownReason: Equatable, Sendable {
    public let isEdgeTilingEnabled: Bool
    public let isTopTilingEnabled: Bool
    public let isOptionAcceleratorEnabled: Bool
    public let screensHaveSeparateSpaces: Bool

    public init(
        isEdgeTilingEnabled: Bool,
        isTopTilingEnabled: Bool,
        isOptionAcceleratorEnabled: Bool,
        screensHaveSeparateSpaces: Bool
    ) {
        self.isEdgeTilingEnabled = isEdgeTilingEnabled
        self.isTopTilingEnabled = isTopTilingEnabled
        self.isOptionAcceleratorEnabled = isOptionAcceleratorEnabled
        self.screensHaveSeparateSpaces = screensHaveSeparateSpaces
    }

    public var summary: String {
        "macOS system window tiling is active"
    }
}

/// High-level observable status of edge snap coexistence with macOS system tiling.
public enum SystemTilingCoexistenceStatus: Equatable, Sendable {
    case active
    case stoodDown(reason: SystemTilingStandDownReason)

    public var isStoodDown: Bool {
        switch self {
        case .active: return false
        case .stoodDown: return true
        }
    }
}

/// Protocol for reading macOS system preferences related to window tiling.
public protocol SystemTilingPreferencesReading: Sendable {
    func readWindowManagerPreference(forKey key: String) -> Any?
    func screensHaveSeparateSpaces() -> Bool
    func operatingSystemMajorVersion() -> Int
}

/// Production preference reader querying `com.apple.WindowManager` and AppKit spaces state.
public struct MacOSSystemTilingPreferencesAdapter: SystemTilingPreferencesReading {
    public init() {}

    public func readWindowManagerPreference(forKey key: String) -> Any? {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager") else {
            return nil
        }
        return defaults.object(forKey: key)
    }

    public func screensHaveSeparateSpaces() -> Bool {
        NSScreen.screensHaveSeparateSpaces
    }

    public func operatingSystemMajorVersion() -> Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }
}

/// Reads and interprets system window tiling preferences following macOS defaults semantics (Z-09).
///
/// On macOS 15+, when tiling preferences are unwritten (`nil`), macOS treats them as enabled (`true`).
public struct SystemTilingPreferenceReader: Sendable {
    public static let edgeTilingKey = "EnableTilingByEdgeDrag"
    public static let topTilingKey = "EnableTopTilingByEdgeDrag"
    public static let optionAcceleratorKey = "EnableTilingOptionAccelerator"

    private let reader: any SystemTilingPreferencesReading

    public init(reader: any SystemTilingPreferencesReading = MacOSSystemTilingPreferencesAdapter()) {
        self.reader = reader
    }

    public func readState() -> SystemTilingState {
        let osVersion = reader.operatingSystemMajorVersion()
        let separateSpaces = reader.screensHaveSeparateSpaces()

        guard osVersion >= 15 else {
            return SystemTilingState(
                isEdgeTilingEnabled: false,
                isTopTilingEnabled: false,
                isOptionAcceleratorEnabled: false,
                screensHaveSeparateSpaces: separateSpaces,
                operatingSystemMajorVersion: osVersion
            )
        }

        // Unwritten default rule on macOS 15+: nil defaults to true
        let edgeTiling = (reader.readWindowManagerPreference(forKey: Self.edgeTilingKey) as? Bool) ?? true
        let topTiling = (reader.readWindowManagerPreference(forKey: Self.topTilingKey) as? Bool) ?? true
        let optionAccel = (reader.readWindowManagerPreference(forKey: Self.optionAcceleratorKey) as? Bool) ?? false

        return SystemTilingState(
            isEdgeTilingEnabled: edgeTiling,
            isTopTilingEnabled: topTiling,
            isOptionAcceleratorEnabled: optionAccel,
            screensHaveSeparateSpaces: separateSpaces,
            operatingSystemMajorVersion: osVersion
        )
    }
}

/// Evaluates whether an edge trigger must stand down for system tiling.
public struct SystemTilingCoexistenceDetector: Sendable {
    public init() {}

    /// Evaluates whether MyMacX must stand down for a candidate edge zone.
    ///
    /// - Parameters:
    ///   - zone: The candidate perimeter zone.
    ///   - isSharedSeam: True if this edge is an internal display seam shared with an adjacent monitor.
    ///   - state: The evaluated system tiling state.
    /// - Returns: True if native macOS tiling owns this edge and MyMacX must stand down visibly.
    public func standsDown(
        for zone: EdgeSnapZone,
        isSharedSeam: Bool,
        state: SystemTilingState
    ) -> Bool {
        // Shared display seams are NEVER managed by native macOS 15 tiling. MyMacX owns them unconditionally.
        if isSharedSeam {
            return false
        }

        guard state.operatingSystemMajorVersion >= 15 else {
            return false
        }

        // When separate Spaces is disabled (spans-displays = true), native macOS tiling is inert (Z-09).
        guard state.screensHaveSeparateSpaces else {
            return false
        }

        if zone == .top && state.isTopTilingEnabled {
            return true
        }

        if (zone == .left || zone == .right) && state.isEdgeTilingEnabled {
            return true
        }

        if zone.isCorner && state.isEdgeTilingEnabled {
            return true
        }

        if zone == .bottom && state.isEdgeTilingEnabled {
            return true
        }

        return false
    }
}

/// Observable status model for system tiling coexistence (Track B / Settings status & DiagnosticsKit).
@MainActor
public final class SystemTilingCoexistenceModel: ObservableObject {
    @Published public private(set) var status: SystemTilingCoexistenceStatus
    @Published public private(set) var state: SystemTilingState

    private let reader: SystemTilingPreferenceReader
    private let detector = SystemTilingCoexistenceDetector()
    private let token = NotificationToken()

    private final class NotificationToken: @unchecked Sendable {
        var observers: [any NSObjectProtocol] = []

        deinit {
            observers.forEach {
                NotificationCenter.default.removeObserver($0)
            }
        }
    }

    public init(reader: SystemTilingPreferenceReader = SystemTilingPreferenceReader()) {
        self.reader = reader
        let initialState = reader.readState()
        self.state = initialState
        if initialState.operatingSystemMajorVersion >= 15 && initialState.screensHaveSeparateSpaces && (initialState.isEdgeTilingEnabled || initialState.isTopTilingEnabled) {
            self.status = .stoodDown(reason: SystemTilingStandDownReason(
                isEdgeTilingEnabled: initialState.isEdgeTilingEnabled,
                isTopTilingEnabled: initialState.isTopTilingEnabled,
                isOptionAcceleratorEnabled: initialState.isOptionAcceleratorEnabled,
                screensHaveSeparateSpaces: initialState.screensHaveSeparateSpaces
            ))
        } else {
            self.status = .active
        }

        // Probe P-02: Listen for preferences change and app activation to support live toggling
        let defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        let activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        token.observers = [defaultsObserver, activeObserver]
    }

    public func refresh() {
        let newState = reader.readState()
        self.state = newState
        if newState.operatingSystemMajorVersion >= 15 && newState.screensHaveSeparateSpaces && (newState.isEdgeTilingEnabled || newState.isTopTilingEnabled) {
            self.status = .stoodDown(reason: SystemTilingStandDownReason(
                isEdgeTilingEnabled: newState.isEdgeTilingEnabled,
                isTopTilingEnabled: newState.isTopTilingEnabled,
                isOptionAcceleratorEnabled: newState.isOptionAcceleratorEnabled,
                screensHaveSeparateSpaces: newState.screensHaveSeparateSpaces
            ))
        } else {
            self.status = .active
        }
    }
}
