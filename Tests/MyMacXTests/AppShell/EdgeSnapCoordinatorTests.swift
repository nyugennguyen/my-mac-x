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

private final class MockPointerEventAdapter: PointerEventAdapting, @unchecked Sendable {
    private var continuation: AsyncStream<PointerPlatformSignal>.Continuation?
    private var stream: AsyncStream<PointerPlatformSignal>?

    init() {
        let (s, c) = AsyncStream.makeStream(of: PointerPlatformSignal.self)
        stream = s
        continuation = c
    }

    func start() async -> PointerEventAdapterStart {
        if let stream {
            return .active(stream)
        }
        let (s, c) = AsyncStream.makeStream(of: PointerPlatformSignal.self)
        stream = s
        continuation = c
        return .active(s)
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    func yield(_ signal: PointerPlatformSignal) {
        continuation?.yield(signal)
    }
}

@MainActor
private final class MockOverlayPresenter: EdgeSnapOverlayPresenting, @unchecked Sendable {
    var shownPreview: PlacementPreviewPresentation?
    var isDismissed: Bool = true

    func showPreview(_ presentation: PlacementPreviewPresentation) -> OverlayPreviewToken {
        shownPreview = presentation
        isDismissed = false
        return OverlayPreviewToken(displayID: presentation.displayID)
    }

    func dismiss() {
        shownPreview = nil
        isDismissed = true
    }
}

private final class TestWindowActions: WindowActionPerforming, @unchecked Sendable {
    var intents: [WindowIntent] = []
    var previewResult: WindowActionResult = WindowActionResult(
        disposition: .succeeded,
        effect: .preview(frame: CGRect(x: 0, y: 0, width: 700, height: 900), displayID: 1, constrained: false),
        undoToken: nil,
        warnings: []
    )
    var commitResult: WindowActionResult = WindowActionResult(
        disposition: .succeeded,
        effect: .committed(actualFrame: CGRect(x: 0, y: 0, width: 700, height: 900), constrained: false),
        undoToken: UndoToken(),
        warnings: []
    )

    func perform(_ intent: WindowIntent) async -> WindowActionResult {
        intents.append(intent)
        switch intent {
        case .preview:
            return previewResult
        case .commitPreview:
            return commitResult
        case .cancelPreview:
            return .cancelled
        case .undo:
            return WindowActionResult(
                disposition: .succeeded,
                effect: .undone(actualFrame: CGRect(x: 100, y: 100, width: 600, height: 400)),
                undoToken: nil,
                warnings: []
            )
        case .commit:
            return commitResult
        }
    }
}

private final class MockSampler: WindowServerWindowSampling, @unchecked Sendable {
    var windowFrames: [CGWindowID: CGRect] = [:]
    var candidate: (windowID: CGWindowID, bounds: CGRect, processID: pid_t)?
    var windowBoundsHook: (@Sendable () async -> Void)?

    func windowBounds(windowID: CGWindowID) async -> CGRect? {
        if let hook = windowBoundsHook {
            await hook()
        }
        return windowFrames[windowID]
    }

    func topmostWindow(at point: CGPoint) async -> (windowID: CGWindowID, bounds: CGRect, processID: pid_t)? {
        candidate
    }
}

private final class MockAXAdapter: AccessibilityWindowAdapting, @unchecked Sendable {
    var candidate: AccessibilityWindowCandidate?

    func captureFocusedWindow() async -> AccessibilityWindowCapture {
        if let candidate {
            return .candidate(candidate)
        }
        return .unsupported
    }
}

private final class MockAppRules: AppRuleDeciding, @unchecked Sendable {
    var decision: AppRuleDecision = .included

    func decision(for bundleIdentifier: String?) async -> AppRuleDecision {
        decision
    }
}

@MainActor
final class EdgeSnapCoordinatorTests: XCTestCase {
    private func makeDisplay(id: UInt32, frame: CGRect) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: frame,
            backingScaleFactor: 2,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            ),
            notchTrigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: .zero
            )
        )
    }

    private var displayTopology: DisplayTopologySnapshot {
        DisplayTopologySnapshot(
            displays: [
                makeDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
            ],
            primaryDisplayID: DisplayID(rawValue: 1)
        )
    }

    // MARK: - Happy Path: Move -> Edge -> Preview -> Commit

    func testDragToLeftEdgeShowsPreviewAndMouseUpCommits() async {
        let pointerAdapter = MockPointerEventAdapter()
        let overlayPresenter = MockOverlayPresenter()
        let windowActions = TestWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let sampler = MockSampler()
        let axAdapter = MockAXAdapter()
        let windowId = WindowIdentity(processID: 500)

        sampler.candidate = (windowID: 101, bounds: CGRect(x: 200, y: 200, width: 600, height: 400), processID: 500)
        sampler.windowFrames[101] = CGRect(x: 200, y: 200, width: 600, height: 400)
        axAdapter.candidate = AccessibilityWindowCandidate(
            identity: windowId,
            capabilities: WindowCapabilities(isMovable: true, isResizable: true, minimized: .inactive, nativeFullScreen: .inactive)
        )

        let targetResolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: axAdapter,
            appRules: MockAppRules()
        )

        let coordinator = EdgeSnapCoordinator(
            pointerEvents: pointerAdapter,
            overlayPresenter: overlayPresenter,
            stateMachine: stateMachine,
            windowSampler: sampler,
            targetResolver: targetResolver,
            topologyProvider: { [displayTopology] in displayTopology },
            systemTilingStateProvider: {
                SystemTilingState(
                    isEdgeTilingEnabled: false,
                    isTopTilingEnabled: false,
                    isOptionAcceleratorEnabled: false,
                    screensHaveSeparateSpaces: true,
                    operatingSystemMajorVersion: 15
                )
            }
        )

        await coordinator.start()

        // 1. Mouse down at (300, 500)
        await coordinator.consumeSignal(.leftButtonPressed(location: CGPoint(x: 300, y: 500), timestamp: 1_000_000))

        // 2. Drag to (10, 500) near left edge. Window moves along with pointer to (0, 200)
        sampler.windowFrames[101] = CGRect(x: 0, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 10, y: 500), timestamp: 30_000_000))

        // Preview must have been displayed!
        XCTAssertFalse(overlayPresenter.isDismissed, "Preview overlay should be visible at left edge")

        // 3. Mouse up to drop
        await coordinator.consumeSignal(.leftButtonReleased(location: CGPoint(x: 10, y: 500), timestamp: 50_000_000))

        // Commit was performed!
        XCTAssertTrue(overlayPresenter.isDismissed, "Preview overlay dismissed after release")
        let committed = windowActions.intents.contains { intent in
            if case .commitPreview = intent { return true }
            return false
        }
        XCTAssertTrue(committed, "CommitPreview intent should have been executed on release")

        await coordinator.stop()
    }

    // MARK: - Cancellation on 3-Strike Mismatch (D-08)

    func testThreeConsecutiveMismatchesCancelDragTracking() async {
        let pointerAdapter = MockPointerEventAdapter()
        let overlayPresenter = MockOverlayPresenter()
        let windowActions = TestWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let sampler = MockSampler()
        let axAdapter = MockAXAdapter()
        let windowId = WindowIdentity(processID: 501)

        sampler.candidate = (windowID: 102, bounds: CGRect(x: 200, y: 200, width: 600, height: 400), processID: 501)
        sampler.windowFrames[102] = CGRect(x: 200, y: 200, width: 600, height: 400)
        axAdapter.candidate = AccessibilityWindowCandidate(
            identity: windowId,
            capabilities: WindowCapabilities(isMovable: true, isResizable: true, minimized: .inactive, nativeFullScreen: .inactive)
        )

        let targetResolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: axAdapter,
            appRules: MockAppRules()
        )

        let coordinator = EdgeSnapCoordinator(
            pointerEvents: pointerAdapter,
            overlayPresenter: overlayPresenter,
            stateMachine: stateMachine,
            windowSampler: sampler,
            targetResolver: targetResolver,
            topologyProvider: { [displayTopology] in displayTopology },
            systemTilingStateProvider: {
                SystemTilingState(
                    isEdgeTilingEnabled: false,
                    isTopTilingEnabled: false,
                    isOptionAcceleratorEnabled: false,
                    screensHaveSeparateSpaces: true
                )
            }
        )

        await coordinator.start()

        // Mouse down
        await coordinator.consumeSignal(.leftButtonPressed(location: CGPoint(x: 300, y: 500), timestamp: 1_000_000))

        // Window moves in wrong direction (unrelated) 3 times:
        // Pointer moved +50 in X, but window moved -50 in X
        sampler.windowFrames[102] = CGRect(x: 150, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 350, y: 500), timestamp: 20_000_000))

        sampler.windowFrames[102] = CGRect(x: 100, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 400, y: 500), timestamp: 40_000_000))

        sampler.windowFrames[102] = CGRect(x: 50, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 450, y: 500), timestamp: 60_000_000))

        // Now drag pointer all the way to left edge (10, 500)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 10, y: 500), timestamp: 80_000_000))

        // Because tracking was cancelled by 3 mismatches, no preview is shown!
        XCTAssertTrue(overlayPresenter.isDismissed)

        // Mouse release does not commit
        await coordinator.consumeSignal(.leftButtonReleased(location: CGPoint(x: 10, y: 500), timestamp: 100_000_000))

        let committed = windowActions.intents.contains { intent in
            if case .commitPreview = intent { return true }
            return false
        }
        XCTAssertFalse(committed, "Cancelled drag must never commit")

        await coordinator.stop()
    }

    // MARK: - Seam-Gate Rejection at High Speed (S-02)

    func testHighSpeedFlickAcrossSharedSeamIsSuppressed() async {
        let multiDisplay = DisplayTopologySnapshot(
            displays: [
                makeDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1400, height: 900)),
                makeDisplay(id: 2, frame: CGRect(x: 1400, y: 0, width: 1400, height: 900))
            ],
            primaryDisplayID: DisplayID(rawValue: 1)
        )

        let pointerAdapter = MockPointerEventAdapter()
        let overlayPresenter = MockOverlayPresenter()
        let windowActions = TestWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let sampler = MockSampler()
        let axAdapter = MockAXAdapter()
        let windowId = WindowIdentity(processID: 502)

        sampler.candidate = (windowID: 103, bounds: CGRect(x: 900, y: 200, width: 400, height: 400), processID: 502)
        sampler.windowFrames[103] = CGRect(x: 900, y: 200, width: 400, height: 400)
        axAdapter.candidate = AccessibilityWindowCandidate(
            identity: windowId,
            capabilities: WindowCapabilities(isMovable: true, isResizable: true, minimized: .inactive, nativeFullScreen: .inactive)
        )

        let targetResolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: axAdapter,
            appRules: MockAppRules()
        )

        let coordinator = EdgeSnapCoordinator(
            pointerEvents: pointerAdapter,
            overlayPresenter: overlayPresenter,
            stateMachine: stateMachine,
            windowSampler: sampler,
            targetResolver: targetResolver,
            topologyProvider: { multiDisplay }
        )

        await coordinator.start()

        // User drags fast toward right seam (x=1400):
        // 60 pt in 30 ms = 2000 pt/s (well above 400 pt/s gate)
        await coordinator.consumeSignal(.leftButtonPressed(location: CGPoint(x: 1330, y: 450), timestamp: 1_000_000))

        sampler.windowFrames[103] = CGRect(x: 960, y: 200, width: 400, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 1360, y: 450), timestamp: 15_000_000))

        sampler.windowFrames[103] = CGRect(x: 995, y: 200, width: 400, height: 400)
        // Hit activation zone (within 12 pt of x=1400) at high speed
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 1395, y: 450), timestamp: 35_000_000))

        // Seam gator must suppress snap preview!
        XCTAssertTrue(overlayPresenter.isDismissed, "High speed flick across display seam must suppress snap preview")

        await coordinator.stop()
    }

    // MARK: - Coexistence Stand-Down on Outer Edge (Z-09)

    func testStandsDownVisiblyWhenMacOSOwnsEdge() async {
        let pointerAdapter = MockPointerEventAdapter()
        let overlayPresenter = MockOverlayPresenter()
        let windowActions = TestWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let sampler = MockSampler()
        let axAdapter = MockAXAdapter()
        let windowId = WindowIdentity(processID: 503)

        sampler.candidate = (windowID: 104, bounds: CGRect(x: 200, y: 200, width: 600, height: 400), processID: 503)
        sampler.windowFrames[104] = CGRect(x: 200, y: 200, width: 600, height: 400)
        axAdapter.candidate = AccessibilityWindowCandidate(
            identity: windowId,
            capabilities: WindowCapabilities(isMovable: true, isResizable: true, minimized: .inactive, nativeFullScreen: .inactive)
        )

        let targetResolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: axAdapter,
            appRules: MockAppRules()
        )

        let coordinator = EdgeSnapCoordinator(
            pointerEvents: pointerAdapter,
            overlayPresenter: overlayPresenter,
            stateMachine: stateMachine,
            windowSampler: sampler,
            targetResolver: targetResolver,
            topologyProvider: { [displayTopology] in displayTopology },
            systemTilingStateProvider: {
                SystemTilingState(
                    isEdgeTilingEnabled: true, // macOS Sequoia owns edge drag!
                    isTopTilingEnabled: true,
                    isOptionAcceleratorEnabled: false,
                    screensHaveSeparateSpaces: true,
                    operatingSystemMajorVersion: 15
                )
            }
        )

        await coordinator.start()

        // Press and drag to left outer edge
        await coordinator.consumeSignal(.leftButtonPressed(location: CGPoint(x: 300, y: 500), timestamp: 1_000_000))

        sampler.windowFrames[104] = CGRect(x: 0, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 10, y: 500), timestamp: 30_000_000))

        // MyMacX must stand down: no preview drawn!
        XCTAssertTrue(overlayPresenter.isDismissed, "MyMacX must stand down when macOS owns edge drag")

        // Mouse release must not commit
        await coordinator.consumeSignal(.leftButtonReleased(location: CGPoint(x: 10, y: 500), timestamp: 50_000_000))

        let committed = windowActions.intents.contains { intent in
            if case .commitPreview = intent { return true }
            return false
        }
        XCTAssertFalse(committed, "Must not commit when stood down for system tiling")

        await coordinator.stop()
    }

    // MARK: - History & Undo Integration

    func testCommitPreviewRecordsPreSnapFrameAndCanUndo() async {
        let pointerAdapter = MockPointerEventAdapter()
        let overlayPresenter = MockOverlayPresenter()
        let windowActions = TestWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let sampler = MockSampler()
        let axAdapter = MockAXAdapter()
        let windowId = WindowIdentity(processID: 504)

        sampler.candidate = (windowID: 105, bounds: CGRect(x: 200, y: 200, width: 600, height: 400), processID: 504)
        sampler.windowFrames[105] = CGRect(x: 200, y: 200, width: 600, height: 400)
        axAdapter.candidate = AccessibilityWindowCandidate(
            identity: windowId,
            capabilities: WindowCapabilities(isMovable: true, isResizable: true, minimized: .inactive, nativeFullScreen: .inactive)
        )

        let targetResolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: axAdapter,
            appRules: MockAppRules()
        )

        let coordinator = EdgeSnapCoordinator(
            pointerEvents: pointerAdapter,
            overlayPresenter: overlayPresenter,
            stateMachine: stateMachine,
            windowSampler: sampler,
            targetResolver: targetResolver,
            topologyProvider: { [displayTopology] in displayTopology },
            systemTilingStateProvider: {
                SystemTilingState(
                    isEdgeTilingEnabled: false,
                    isTopTilingEnabled: false,
                    isOptionAcceleratorEnabled: false,
                    screensHaveSeparateSpaces: true,
                    operatingSystemMajorVersion: 15
                )
            }
        )

        await coordinator.start()

        // 1. Mouse down & drag to left edge
        await coordinator.consumeSignal(.leftButtonPressed(location: CGPoint(x: 300, y: 500), timestamp: 1_000_000))
        sampler.windowFrames[105] = CGRect(x: 0, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 10, y: 500), timestamp: 30_000_000))

        XCTAssertFalse(overlayPresenter.isDismissed, "Preview overlay should be visible")

        // 2. Mouse up to drop and commit
        await coordinator.consumeSignal(.leftButtonReleased(location: CGPoint(x: 10, y: 500), timestamp: 50_000_000))
        XCTAssertTrue(overlayPresenter.isDismissed)

        // 3. Verify commit intent executed
        let commitIntent = windowActions.intents.first { intent in
            if case .commitPreview = intent { return true }
            return false
        }
        XCTAssertNotNil(commitIntent, "Commit preview must have executed")

        // 4. Perform undo with the commit's undo token
        let token = windowActions.commitResult.undoToken
        XCTAssertNotNil(token, "Commit preview must produce undo token")
        let undoResult = await windowActions.perform(.undo(token: token, source: .menuBar))
        XCTAssertEqual(undoResult.disposition, WindowActionResult.Disposition.succeeded)
        guard case let .undo(recordedToken, recordedSource)? = windowActions.intents.last else {
            return XCTFail("Expected undo intent recorded")
        }
        XCTAssertEqual(recordedToken, token)
        XCTAssertEqual(recordedSource, .menuBar)

        await coordinator.stop()
    }

    // MARK: - Resurrection Across Async Suspension Guard (Major 2)

    func testStopDuringInFlightSampleMustNotShowOverlayNorSetActiveRun() async {
        let pointerAdapter = MockPointerEventAdapter()
        let overlayPresenter = MockOverlayPresenter()
        let windowActions = TestWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let sampler = MockSampler()
        let axAdapter = MockAXAdapter()
        let windowId = WindowIdentity(processID: 505)

        sampler.candidate = (windowID: 106, bounds: CGRect(x: 200, y: 200, width: 600, height: 400), processID: 505)
        sampler.windowFrames[106] = CGRect(x: 200, y: 200, width: 600, height: 400)
        axAdapter.candidate = AccessibilityWindowCandidate(
            identity: windowId,
            capabilities: WindowCapabilities(isMovable: true, isResizable: true, minimized: .inactive, nativeFullScreen: .inactive)
        )

        let targetResolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: axAdapter,
            appRules: MockAppRules()
        )

        final class CoordinatorBox: @unchecked Sendable {
            var coordinator: EdgeSnapCoordinator?
        }
        let box = CoordinatorBox()
        let coordinator = EdgeSnapCoordinator(
            pointerEvents: pointerAdapter,
            overlayPresenter: overlayPresenter,
            stateMachine: stateMachine,
            windowSampler: sampler,
            targetResolver: targetResolver,
            topologyProvider: { [displayTopology] in displayTopology },
            systemTilingStateProvider: {
                SystemTilingState(
                    isEdgeTilingEnabled: false,
                    isTopTilingEnabled: false,
                    isOptionAcceleratorEnabled: false,
                    screensHaveSeparateSpaces: true
                )
            }
        )
        box.coordinator = coordinator

        await coordinator.start()

        // 1. Mouse down at (300, 500)
        await coordinator.consumeSignal(.leftButtonPressed(location: CGPoint(x: 300, y: 500), timestamp: 1_000_000))

        // Hook window bounds sample so when the drag sample is in-flight, coordinator.stop() is invoked
        sampler.windowBoundsHook = {
            await box.coordinator?.stop()
        }

        // Move window to left edge
        sampler.windowFrames[106] = CGRect(x: 0, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 10, y: 500), timestamp: 30_000_000))

        // Since stop() was called during in-flight sample, the completed sample must NOT resurrect activeRun or show overlay
        XCTAssertTrue(overlayPresenter.isDismissed, "Overlay must remain dismissed after stop() during in-flight sample")
        XCTAssertNil(overlayPresenter.shownPreview, "No preview presentation should be recorded after stop()")
        XCTAssertFalse(coordinator.hasActiveRun, "ActiveRun must not be resurrected after stop()")
    }

    // MARK: - Master Toggle Guard (Major 3)

    func testDisabledMasterToggleDoesNotShowPreviewNorCommit() async {
        let pointerAdapter = MockPointerEventAdapter()
        let overlayPresenter = MockOverlayPresenter()
        let windowActions = TestWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let sampler = MockSampler()
        let axAdapter = MockAXAdapter()
        let windowId = WindowIdentity(processID: 506)

        sampler.candidate = (windowID: 107, bounds: CGRect(x: 200, y: 200, width: 600, height: 400), processID: 506)
        sampler.windowFrames[107] = CGRect(x: 200, y: 200, width: 600, height: 400)
        axAdapter.candidate = AccessibilityWindowCandidate(
            identity: windowId,
            capabilities: WindowCapabilities(isMovable: true, isResizable: true, minimized: .inactive, nativeFullScreen: .inactive)
        )

        let targetResolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: axAdapter,
            appRules: MockAppRules()
        )

        let coordinator = EdgeSnapCoordinator(
            pointerEvents: pointerAdapter,
            overlayPresenter: overlayPresenter,
            stateMachine: stateMachine,
            windowSampler: sampler,
            targetResolver: targetResolver,
            topologyProvider: { [displayTopology] in displayTopology },
            isEnabledProvider: { false } // Snapping is disabled!
        )

        await coordinator.start()

        // 1. Mouse down at (300, 500)
        await coordinator.consumeSignal(.leftButtonPressed(location: CGPoint(x: 300, y: 500), timestamp: 1_000_000))

        // 2. Move to left edge
        sampler.windowFrames[107] = CGRect(x: 0, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 10, y: 500), timestamp: 30_000_000))

        // When disabled, no preview should ever be shown
        XCTAssertTrue(overlayPresenter.isDismissed, "Preview overlay must not be shown when master toggle is disabled")
        XCTAssertNil(overlayPresenter.shownPreview)

        // 3. Mouse up
        await coordinator.consumeSignal(.leftButtonReleased(location: CGPoint(x: 10, y: 500), timestamp: 50_000_000))

        let committed = windowActions.intents.contains { intent in
            if case .commitPreview = intent { return true }
            return false
        }
        XCTAssertFalse(committed, "Must not commit preview when snapping is disabled")

        await coordinator.stop()
    }

    func testZeroTimestampSamplesStillShowPreviewOverlay() async {
        let pointerAdapter = MockPointerEventAdapter()
        let overlayPresenter = MockOverlayPresenter()
        let windowActions = TestWindowActions()
        let stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        let sampler = MockSampler()
        let axAdapter = MockAXAdapter()
        let windowId = WindowIdentity(processID: 508)

        sampler.candidate = (windowID: 108, bounds: CGRect(x: 200, y: 200, width: 600, height: 400), processID: 508)
        sampler.windowFrames[108] = CGRect(x: 200, y: 200, width: 600, height: 400)
        axAdapter.candidate = AccessibilityWindowCandidate(
            identity: windowId,
            capabilities: WindowCapabilities(isMovable: true, isResizable: true, minimized: .inactive, nativeFullScreen: .inactive)
        )

        let targetResolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: axAdapter,
            appRules: MockAppRules()
        )

        let coordinator = EdgeSnapCoordinator(
            pointerEvents: pointerAdapter,
            overlayPresenter: overlayPresenter,
            stateMachine: stateMachine,
            windowSampler: sampler,
            targetResolver: targetResolver,
            topologyProvider: { [displayTopology] in displayTopology },
            systemTilingStateProvider: {
                SystemTilingState(
                    isEdgeTilingEnabled: false,
                    isTopTilingEnabled: false,
                    isOptionAcceleratorEnabled: false,
                    screensHaveSeparateSpaces: true
                )
            }
        )

        await coordinator.start()

        // 1. Mouse down with 0 timestamp
        await coordinator.consumeSignal(.leftButtonPressed(location: CGPoint(x: 300, y: 500), timestamp: 0))

        // 2. Drag to left edge with 0 timestamp
        sampler.windowFrames[108] = CGRect(x: 0, y: 200, width: 600, height: 400)
        await coordinator.consumeSignal(.leftButtonDragged(location: CGPoint(x: 10, y: 500), timestamp: 0))

        XCTAssertFalse(overlayPresenter.isDismissed, "Preview overlay should be visible even when timestamps are zero")
        XCTAssertNotNil(overlayPresenter.shownPreview)

        await coordinator.stop()
    }
}
