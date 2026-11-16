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
import SwiftUI
import XCTest
@testable import MyMacX

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {
    nonisolated(unsafe) private var testDefaults: UserDefaults!
    private let suiteName = "test.mymacx.onboarding"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Policy Tests

    func testPolicyPresentsWhenBothMissingOnFirstLaunch() {
        XCTAssertTrue(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: false,
            permissionState: .notRequested,
            inputMonitoringGranted: false
        ))
    }

    func testPolicyPresentsWhenOnlyAccessibilityMissingOnFirstLaunch() {
        XCTAssertTrue(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: false,
            permissionState: .notRequested,
            inputMonitoringGranted: true
        ))
    }

    func testPolicyPresentsWhenOnlyInputMonitoringMissingOnFirstLaunch() {
        XCTAssertTrue(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: false,
            permissionState: .granted,
            inputMonitoringGranted: false
        ))
    }

    func testPolicyDoesNotPresentWhenBothAlreadyGrantedOnFirstLaunch() {
        XCTAssertFalse(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: false,
            permissionState: .granted,
            inputMonitoringGranted: true
        ))
    }

    func testPolicyDoesNotPresentWhenExplanationAlreadySeen() {
        XCTAssertFalse(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: true,
            permissionState: .notRequested,
            inputMonitoringGranted: false
        ))
        XCTAssertFalse(FirstLaunchOnboardingPolicy.shouldPresent(
            hasSeenExplanation: true,
            permissionState: .denied,
            inputMonitoringGranted: false
        ))
    }

    // MARK: - View Model Tests

    func testViewModelInitialState() {
        var accessibilityState: AccessibilityPermissionState = .notRequested
        var inputMonitoringGranted = false

        let model = OnboardingViewModel(
            accessibilityStateProvider: { accessibilityState },
            refreshAccessibilityState: { accessibilityState },
            inputMonitoringStateProvider: { inputMonitoringGranted },
            requestInputMonitoringAccess: { false },
            openAccessibilitySettings: {},
            openInputMonitoringSettings: {},
            openAppSettings: {},
            completeAction: {}
        )

        XCTAssertFalse(model.accessibilityGranted)
        XCTAssertEqual(model.accessibilityState, .notRequested)
        XCTAssertFalse(model.inputMonitoringGranted)
        XCTAssertFalse(model.allPermissionsGranted)

        accessibilityState = .granted
        inputMonitoringGranted = true
        model.refresh()

        XCTAssertTrue(model.accessibilityGranted)
        XCTAssertEqual(model.accessibilityState, .granted)
        XCTAssertTrue(model.inputMonitoringGranted)
        XCTAssertTrue(model.allPermissionsGranted)
    }

    func testGrantAccessibilityInvokesActionAndRefreshes() {
        var accessibilityActionCalled = false
        var currentAccessibilityState: AccessibilityPermissionState = .notRequested

        let model = OnboardingViewModel(
            accessibilityStateProvider: { currentAccessibilityState },
            refreshAccessibilityState: { currentAccessibilityState },
            inputMonitoringStateProvider: { true },
            requestInputMonitoringAccess: { true },
            openAccessibilitySettings: {
                accessibilityActionCalled = true
                currentAccessibilityState = .granted
            },
            openInputMonitoringSettings: {},
            openAppSettings: {},
            completeAction: {}
        )

        XCTAssertFalse(accessibilityActionCalled)
        XCTAssertFalse(model.accessibilityGranted)

        model.grantAccessibility()

        XCTAssertTrue(accessibilityActionCalled)
        XCTAssertTrue(model.accessibilityGranted)
    }

    func testGrantInputMonitoringInvokesRequestAndDeepLinksIfDenied() {
        var requestAccessCalled = false
        var deepLinkCalled = false
        var currentInputMonitoring = false

        let model = OnboardingViewModel(
            accessibilityStateProvider: { .granted },
            refreshAccessibilityState: { .granted },
            inputMonitoringStateProvider: { currentInputMonitoring },
            requestInputMonitoringAccess: {
                requestAccessCalled = true
                return false
            },
            openAccessibilitySettings: {},
            openInputMonitoringSettings: {
                deepLinkCalled = true
                currentInputMonitoring = true
            },
            openAppSettings: {},
            completeAction: {}
        )

        model.grantInputMonitoring()

        XCTAssertTrue(requestAccessCalled)
        XCTAssertTrue(deepLinkCalled)
        XCTAssertTrue(model.inputMonitoringGranted)
    }

    func testGrantInputMonitoringMarksGrantedWhenRequestSucceeds() {
        var requestAccessCalled = false
        var deepLinkCalled = false
        var currentAccess = false

        let model = OnboardingViewModel(
            accessibilityStateProvider: { .granted },
            refreshAccessibilityState: { .granted },
            inputMonitoringStateProvider: { currentAccess },
            requestInputMonitoringAccess: {
                requestAccessCalled = true
                currentAccess = true
                return true
            },
            openAccessibilitySettings: {},
            openInputMonitoringSettings: {
                deepLinkCalled = true
            },
            openAppSettings: {},
            completeAction: {}
        )

        model.grantInputMonitoring()

        XCTAssertTrue(requestAccessCalled)
        XCTAssertFalse(deepLinkCalled)
        XCTAssertTrue(model.inputMonitoringGranted)
    }

    // MARK: - Controller Lifecycle & Window Tests

    func testControllerPresentsAndCompletesWindow() {
        var completed = false
        let controller = OnboardingWindowController(
            defaults: testDefaults,
            accessibilityStateProvider: { .notRequested },
            refreshAccessibilityState: { .notRequested },
            inputMonitoringStateProvider: { false },
            requestInputMonitoringAccess: { false },
            openAccessibilitySettings: {},
            openInputMonitoringSettings: {},
            openAppSettings: {},
            onComplete: { completed = true }
        )

        XCTAssertFalse(testDefaults.bool(forKey: OnboardingWindowController.explanationSeenKey))

        let window = controller.windowForTesting(contentSize: NSSize(width: 580, height: 560))
        XCTAssertNotNil(window)
        XCTAssertEqual(window.contentView?.frame.size.width, 580)
        XCTAssertEqual(window.contentView?.frame.size.height, 560)

        controller.complete()

        XCTAssertTrue(testDefaults.bool(forKey: OnboardingWindowController.explanationSeenKey))
        XCTAssertTrue(completed)
    }
}
