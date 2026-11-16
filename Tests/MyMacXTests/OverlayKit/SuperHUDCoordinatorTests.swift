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
import XCTest
@testable import MyMacX

@MainActor
final class SuperHUDCoordinatorTests: XCTestCase {
    func testStateTransitionsMapToWaitingSubmenuPendingAndSuccess() {
        let renderer = RecordingSuperHUDRenderer()
        let scheduler = RecordingSuperHUDScheduler()
        let coordinator = SuperHUDCoordinator(renderer: renderer, dismissScheduler: scheduler)
        let session = SuperModeSessionID(rawValue: 7)
        let presentation = SuperHUDPresentation(panelFrame: CGRect(x: 1, y: 2, width: 320, height: 64), actionTitle: "Restore")

        coordinator.present(transition: transition(from: .idle, to: .armed(session: session), outcome: .armed), presentation: presentation)
        XCTAssertEqual(renderer.models.last?.state, .waiting)
        coordinator.present(transition: transition(from: .armed(session: session), to: .submenu(session: session, hardwareKeyCode: 3), outcome: .submenuEntered), presentation: presentation)
        XCTAssertEqual(renderer.models.last?.state, .submenu)
        coordinator.present(transition: transition(from: .submenu(session: session, hardwareKeyCode: 3), to: .idle, outcome: .execute(.restore)), presentation: presentation)
        XCTAssertEqual(renderer.models.last?.state, .pending)
        coordinator.present(dispatchResult: .dispatched(success), session: session)
        XCTAssertEqual(renderer.models.last?.state, .success)
        XCTAssertEqual(scheduler.scheduledDelay, 0.8)
    }

    func testStaleResultCannotReplaceNewSessionAndTimeoutDismissesAfterFeedback() {
        let renderer = RecordingSuperHUDRenderer()
        let scheduler = RecordingSuperHUDScheduler()
        let coordinator = SuperHUDCoordinator(renderer: renderer, dismissScheduler: scheduler)
        let old = SuperModeSessionID(rawValue: 1)
        let current = SuperModeSessionID(rawValue: 2)
        let presentation = SuperHUDPresentation(panelFrame: .zero, actionTitle: nil)
        coordinator.present(transition: transition(from: .idle, to: .armed(session: old), outcome: .armed), presentation: presentation)
        coordinator.present(transition: transition(from: .idle, to: .armed(session: current), outcome: .armed), presentation: presentation)

        coordinator.present(dispatchResult: .dispatched(success), session: old)
        XCTAssertEqual(renderer.models.last?.state, .waiting)
        coordinator.present(transition: transition(from: .armed(session: current), to: .idle, outcome: .cancelled(.timeout)), presentation: presentation)
        XCTAssertEqual(renderer.models.last?.state, .timeout)
        scheduler.fire()
        XCTAssertEqual(renderer.dismissCount, 1)
        XCTAssertEqual(coordinator.lastDismissal, .timeout)
    }

    func testPanelAndAccessibilityPolicyRemainNonActivatingAndAccessible() {
        let panel = SuperHUDPanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))

        let renderer = RecordingSuperHUDRenderer()
        let coordinator = SuperHUDCoordinator(
            renderer: renderer,
            dismissScheduler: RecordingSuperHUDScheduler(),
            accessibilityPreferences: .init(reduceMotion: true, reduceTransparency: true, increaseContrast: true)
        )
        let session = SuperModeSessionID(rawValue: 9)
        coordinator.present(
            transition: transition(from: .idle, to: .armed(session: session), outcome: .armed),
            presentation: .init(panelFrame: .zero, actionTitle: nil)
        )
        let model = renderer.models.last
        XCTAssertEqual(model?.presentationPolicy.motion, .immediate)
        XCTAssertEqual(model?.presentationPolicy.background, .opaque)
        XCTAssertEqual(model?.presentationPolicy.contrast, .increased)
        XCTAssertTrue(model?.accessibilityLabel.contains("Super Mode") == true)
    }

    func testAccessibilityPreferenceChangeRedrawsTheVisibleHUD() {
        let renderer = RecordingSuperHUDRenderer()
        let coordinator = SuperHUDCoordinator(
            renderer: renderer,
            dismissScheduler: RecordingSuperHUDScheduler()
        )
        let session = SuperModeSessionID(rawValue: 11)
        coordinator.present(
            transition: transition(from: .idle, to: .armed(session: session), outcome: .armed),
            presentation: .init(panelFrame: .zero, actionTitle: nil)
        )

        coordinator.updateAccessibilityPreferences(.init(
            reduceMotion: true,
            reduceTransparency: true,
            increaseContrast: true
        ))

        XCTAssertEqual(renderer.models.count, 2)
        XCTAssertEqual(renderer.models.last?.presentationPolicy.motion, .immediate)
        XCTAssertEqual(renderer.models.last?.presentationPolicy.background, .opaque)
        XCTAssertEqual(renderer.models.last?.presentationPolicy.contrast, .increased)
    }

    private var success: WindowActionResult {
        WindowActionResult(disposition: .succeeded, effect: .none, undoToken: nil, warnings: [])
    }

    private func transition(from previous: SuperModePresentationState, to current: SuperModePresentationState, outcome: SuperModeOutcome) -> SuperModeTransition {
        SuperModeTransition(previous: previous, current: current, disposition: .consume, outcome: outcome)
    }
}

@MainActor
private final class RecordingSuperHUDRenderer: SuperHUDRendering {
    var models: [SuperHUDRenderModel] = []
    var dismissCount = 0
    func show(_ model: SuperHUDRenderModel) { models.append(model) }
    func dismiss() { dismissCount += 1 }
}

@MainActor
private final class RecordingSuperHUDScheduler: SuperHUDDismissScheduling {
    var scheduledDelay: TimeInterval?
    var action: (@MainActor @Sendable () -> Void)?
    func schedule(after delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) {
        scheduledDelay = delay
        self.action = action
    }
    func cancel() { action = nil }
    func fire() { let pending = action; action = nil; pending?() }
}
