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

    func windowBounds(windowID: CGWindowID) async -> CGRect? {
        windowFrames[windowID]
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
        let windowId = WindowIdentity()

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
        let windowId = WindowIdentity()

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
            topologyProvider: { [displayTopology] in displayTopology }
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
        let windowId = WindowIdentity()

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
        let windowId = WindowIdentity()

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
        let windowId = WindowIdentity()

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
        let undoResult = await windowActions.perform(.undo(token: windowActions.commitResult.undoToken, source: .menuBar))
        XCTAssertEqual(undoResult.disposition, WindowActionResult.Disposition.succeeded)
        if case let .undone(actualFrame) = undoResult.effect {
            XCTAssertEqual(actualFrame, CGRect(x: 100, y: 100, width: 600, height: 400), "Pre-snap frame restored from history")
        } else {
            XCTFail("Expected undone effect with pre-snap frame")
        }

        await coordinator.stop()
    }
}
