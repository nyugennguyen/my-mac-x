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
import Combine
import SwiftUI

// MARK: - Deep Link Helpers

@MainActor
public enum SystemSettingsDeepLink {
    public static let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    public static let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    private static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    @discardableResult
    public static func openAccessibility() -> Bool {
        if NSWorkspace.shared.open(accessibilityURL) {
            return true
        }
        return openGeneralSettings()
    }

    @discardableResult
    public static func openInputMonitoring() -> Bool {
        if NSWorkspace.shared.open(inputMonitoringURL) {
            return true
        }
        return openGeneralSettings()
    }

    @discardableResult
    public static func openGeneralSettings() -> Bool {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: systemSettingsBundleIdentifier
        ) else {
            return false
        }
        return NSWorkspace.shared.open(applicationURL)
    }
}

// MARK: - Onboarding View Model

@MainActor
public final class OnboardingViewModel: ObservableObject {
    public typealias AccessibilityStateProvider = @MainActor () -> AccessibilityPermissionState
    public typealias InputMonitoringStateProvider = @MainActor () -> Bool
    public typealias RequestInputMonitoringAccess = @MainActor () -> Bool
    public typealias ActionHandler = @MainActor () -> Void

    @Published public private(set) var accessibilityGranted: Bool = false
    @Published public private(set) var accessibilityState: AccessibilityPermissionState = .notRequested
    @Published public private(set) var inputMonitoringGranted: Bool = false

    private let accessibilityStateProvider: AccessibilityStateProvider
    private let refreshAccessibilityState: AccessibilityStateProvider
    private let inputMonitoringStateProvider: InputMonitoringStateProvider
    private let requestInputMonitoringAccessAction: RequestInputMonitoringAccess
    private let openAccessibilitySettingsAction: ActionHandler
    private let openInputMonitoringSettingsAction: ActionHandler
    private let openAppSettingsAction: ActionHandler
    private let completeAction: ActionHandler

    public init(
        accessibilityStateProvider: @escaping AccessibilityStateProvider,
        refreshAccessibilityState: @escaping AccessibilityStateProvider,
        inputMonitoringStateProvider: @escaping InputMonitoringStateProvider,
        requestInputMonitoringAccess: @escaping RequestInputMonitoringAccess,
        openAccessibilitySettings: @escaping ActionHandler,
        openInputMonitoringSettings: @escaping ActionHandler,
        openAppSettings: @escaping ActionHandler,
        completeAction: @escaping ActionHandler
    ) {
        self.accessibilityStateProvider = accessibilityStateProvider
        self.refreshAccessibilityState = refreshAccessibilityState
        self.inputMonitoringStateProvider = inputMonitoringStateProvider
        self.requestInputMonitoringAccessAction = requestInputMonitoringAccess
        self.openAccessibilitySettingsAction = openAccessibilitySettings
        self.openInputMonitoringSettingsAction = openInputMonitoringSettings
        self.openAppSettingsAction = openAppSettings
        self.completeAction = completeAction

        refresh()
    }

    public var allPermissionsGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    public func refresh() {
        let state = refreshAccessibilityState()
        accessibilityState = state
        accessibilityGranted = (state == .granted)
        inputMonitoringGranted = inputMonitoringStateProvider()
    }

    public func grantAccessibility() {
        openAccessibilitySettingsAction()
        refresh()
    }

    public func grantInputMonitoring() {
        let granted = requestInputMonitoringAccessAction()
        if !granted && !inputMonitoringStateProvider() {
            openInputMonitoringSettingsAction()
        }
        refresh()
    }

    public func openSettings() {
        openAppSettingsAction()
    }

    public func complete() {
        completeAction()
    }
}

// MARK: - Onboarding View (Open Design)

public struct OnboardingView: View {
    @ObservedObject public var model: OnboardingViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(model: OnboardingViewModel) {
        self.model = model
    }

    public var body: some View {
        let increaseContrast = colorSchemeContrast == .increased
        let context = SettingsEnvironmentContext(
            colorScheme: colorScheme,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )

        VStack(spacing: 20) {
            headerSection
            privacyBanner(context: context)
            permissionsSection(context: context)
            footerSection
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 580)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SettingsTokenResolver.cardBackground(context: context))
        )
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 8, x: 0, y: 4)

                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(String(localized: "Welcome to My Mac X"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(String(localized: "A native, local-first window manager. Set up permissions below to enable window snapping, multi-display moves, and global hotkeys."))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 480)
            }
        }
    }

    private func privacyBanner(context: SettingsEnvironmentContext) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.green)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "100% Local & Private"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(String(localized: "My Mac X operates strictly on your Mac. It never logs keystrokes, reads window titles, or accesses your private files."))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.green.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func permissionsSection(context: SettingsEnvironmentContext) -> some View {
        VStack(spacing: 12) {
            permissionCard(
                iconName: "hand.raised.square.fill",
                iconColor: Color.blue,
                title: String(localized: "Accessibility Permission"),
                badgeText: model.accessibilityGranted ? String(localized: "Granted") : String(localized: "Required"),
                isGranted: model.accessibilityGranted,
                isRecommended: false,
                explanation: String(localized: "Required to inspect window boundaries and perform move, resize, and edge snapping actions."),
                actionTitle: model.accessibilityGranted ? String(localized: "Granted") : String(localized: "Grant Access…"),
                action: { model.grantAccessibility() },
                context: context
            )

            permissionCard(
                iconName: "keyboard.fill",
                iconColor: Color.purple,
                title: String(localized: "Input Monitoring Permission"),
                badgeText: model.inputMonitoringGranted ? String(localized: "Granted") : String(localized: "Recommended"),
                isGranted: model.inputMonitoringGranted,
                isRecommended: true,
                explanation: String(localized: "Recommended to detect global hotkeys, Super Mode prefix chords, and cursor drag-to-snap gestures."),
                actionTitle: model.inputMonitoringGranted ? String(localized: "Granted") : String(localized: "Grant Access…"),
                action: { model.grantInputMonitoring() },
                context: context
            )
        }
    }

    private func permissionCard(
        iconName: String,
        iconColor: Color,
        title: String,
        badgeText: String,
        isGranted: Bool,
        isRecommended: Bool,
        explanation: String,
        actionTitle: String,
        action: @escaping () -> Void,
        context: SettingsEnvironmentContext
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    statusBadge(text: badgeText, isGranted: isGranted, isRecommended: isRecommended)
                }

                Text(explanation)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }

            Spacer(minLength: 8)

            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.green.opacity(0.1))
                )
            } else {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SettingsTokenResolver.cardBackground(context: context))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isGranted ? Color.green.opacity(0.3) : (SettingsTokenResolver.cardBorder(context: context) ?? Color(nsColor: .separatorColor).opacity(0.2)),
                    lineWidth: 0.5
                )
        )
    }

    private func statusBadge(text: String, isGranted: Bool, isRecommended: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : (isRecommended ? "info.circle.fill" : "exclamationmark.circle.fill"))
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 9.5, weight: .bold))
        }
        .foregroundStyle(isGranted ? Color.green : (isRecommended ? Color.purple : Color.orange))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill((isGranted ? Color.green : (isRecommended ? Color.purple : Color.orange)).opacity(0.12))
        )
    }

    private var footerSection: some View {
        VStack(spacing: 12) {
            Divider()

            HStack {
                if model.allPermissionsGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text(String(localized: "All permissions configured! You're ready."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if !model.accessibilityGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        Text(String(localized: "Accessibility is required to manage windows."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.purple)
                        Text(String(localized: "Input Monitoring recommended for shortcuts."))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(String(localized: "Settings…")) {
                    model.openSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(model.accessibilityGranted ? String(localized: "Get Started") : String(localized: "Continue")) {
                    model.complete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Onboarding Window Controller

@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    public static let explanationSeenKey = "onboarding.accessibilityExplanationSeen.v1"

    public typealias AccessibilityStateProvider = @MainActor () -> AccessibilityPermissionState
    public typealias InputMonitoringStateProvider = @MainActor () -> Bool
    public typealias RequestInputMonitoringAccess = @MainActor () -> Bool
    public typealias ActionHandler = @MainActor () -> Void

    private let defaults: UserDefaults
    private let model: OnboardingViewModel
    private let onComplete: ActionHandler?
    private var window: NSWindow?
    private var timer: Timer?
    private var activeObserver: (any NSObjectProtocol)?

    public init(
        defaults: UserDefaults = .standard,
        accessibilityStateProvider: @escaping AccessibilityStateProvider,
        refreshAccessibilityState: @escaping AccessibilityStateProvider,
        inputMonitoringStateProvider: @escaping InputMonitoringStateProvider,
        requestInputMonitoringAccess: @escaping RequestInputMonitoringAccess,
        openAccessibilitySettings: @escaping ActionHandler = { SystemSettingsDeepLink.openAccessibility() },
        openInputMonitoringSettings: @escaping ActionHandler = { SystemSettingsDeepLink.openInputMonitoring() },
        openAppSettings: @escaping ActionHandler = {},
        onComplete: ActionHandler? = nil
    ) {
        self.defaults = defaults
        self.onComplete = onComplete
        var completeRef: (() -> Void)?
        let model = OnboardingViewModel(
            accessibilityStateProvider: accessibilityStateProvider,
            refreshAccessibilityState: refreshAccessibilityState,
            inputMonitoringStateProvider: inputMonitoringStateProvider,
            requestInputMonitoringAccess: requestInputMonitoringAccess,
            openAccessibilitySettings: openAccessibilitySettings,
            openInputMonitoringSettings: openInputMonitoringSettings,
            openAppSettings: openAppSettings,
            completeAction: { completeRef?() }
        )
        self.model = model
        super.init()

        completeRef = { [weak self] in
            self?.complete()
        }
    }

    public var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    public func presentIfNeeded() {
        guard FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: defaults.bool(forKey: Self.explanationSeenKey),
            permissionState: model.accessibilityState,
            inputMonitoringGranted: model.inputMonitoringGranted
        ) else { return }

        present()
    }

    public func present() {
        let onboardingWindow = window ?? makeWindow()
        window = onboardingWindow
        NSApplication.shared.activate(ignoringOtherApps: true)
        onboardingWindow.makeKeyAndOrderFront(nil)
        model.refresh()
        startObserving()
    }

    public func complete() {
        defaults.set(true, forKey: Self.explanationSeenKey)
        stopObserving()
        window?.close()
        onComplete?()
    }

    public func refreshPermissions() {
        model.refresh()
    }

    public func windowWillClose(_ notification: Notification) {
        defaults.set(true, forKey: Self.explanationSeenKey)
        stopObserving()
    }

    private func startObserving() {
        stopObserving()

        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refresh()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isWindowVisible else { return }
                self.model.refresh()
            }
        }
    }

    private func stopObserving() {
        timer?.invalidate()
        timer = nil
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
    }

    private func makeWindow(dynamicTypeSize: DynamicTypeSize? = nil) -> NSWindow {
        let rootView = OnboardingView(model: model)
        let controller: NSViewController
        if let dynamicTypeSize {
            controller = NSHostingController(rootView: rootView.dynamicTypeSize(dynamicTypeSize))
        } else {
            controller = NSHostingController(rootView: rootView)
        }

        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Welcome to My Mac X")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 580, height: 560))
        window.center()
        window.setAccessibilityLabel(String(localized: "Welcome to My Mac X Onboarding"))
        window.delegate = self
        return window
    }

    public var modelForTesting: OnboardingViewModel { model }
    public var windowForTesting: NSWindow? { window }

    func windowForTesting(
        contentSize: NSSize,
        dynamicTypeSize: DynamicTypeSize? = nil
    ) -> NSWindow {
        let onboardingWindow = makeWindow(dynamicTypeSize: dynamicTypeSize)
        window = onboardingWindow
        onboardingWindow.setContentSize(contentSize)
        onboardingWindow.contentView?.layoutSubtreeIfNeeded()
        return onboardingWindow
    }
}
