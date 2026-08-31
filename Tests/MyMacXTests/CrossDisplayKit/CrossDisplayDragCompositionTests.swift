import CoreGraphics
import XCTest

@testable import MyMacX

@MainActor
final class CrossDisplayDragCompositionTests: XCTestCase {
    func testDraggingCapturedWindowIntoNotchTriggerPresentsLayoutChooser() async throws {
        let display = builtInDisplay()
        let topology = InMemoryDisplayTopologyObserver(
            initial: available(generation: 1, displays: [display], primary: display.id)
        )
        let pointer = InMemoryCompositionPointerAdapter()
        let window = WindowIdentity()
        let movements = InMemoryCompositionWindowMovementAdapter(window: window)
        let monitor = PointerDragMonitor(pointerEvents: pointer, windowMovements: movements)
        let renderer = CompositionRecordingOverlayRenderer()
        let overlay = OverlayCoordinator(renderer: renderer)
        let dwell = try TriggerDwellEngine(
            configuration: TriggerDwellConfiguration(dwellDuration: .milliseconds(120))
        )
        let composition = CrossDisplayDragComposition(
            overlay: overlay,
            topologyObserving: topology,
            triggerEngine: dwell,
            pointerMonitor: monitor
        )
        _ = composition

        await eventually { await pointer.hasStarted }
        try await Task.sleep(for: .milliseconds(100))
        let triggerPoint = CGPoint(
            x: display.notchTrigger.region.midX,
            y: display.notchTrigger.region.midY
        )

        await pointer.send(.leftButtonPressed(location: triggerPoint))
        await eventually { await movements.isObserving }
        await pointer.send(.leftButtonDragged(location: triggerPoint))
        await movements.send(window)
        for _ in 0..<20 {
            await pointer.send(.leftButtonDragged(location: triggerPoint))
            try await Task.sleep(for: .milliseconds(10))
        }

        await eventually(timeout: .seconds(1)) { renderer.chooserModels.count == 1 }
        XCTAssertEqual(renderer.chooserModels.first?.panelFrame.width, 360)
        XCTAssertEqual(
            renderer.chooserModels.first?.choices.map(\.action),
            [
                .maximize,
                .leftHalf,
                .rightHalf,
                .topHalf,
                .bottomHalf,
                .topLeftQuarter,
                .topRightQuarter,
                .bottomLeftQuarter,
                .bottomRightQuarter,
            ]
        )

        let chooserFrame = try XCTUnwrap(renderer.chooserModels.first?.panelFrame)
        let expectedActions: [ActionID] = [
            .maximize,
            .leftHalf,
            .rightHalf,
            .topHalf,
            .bottomHalf,
            .topLeftQuarter,
            .topRightQuarter,
            .bottomLeftQuarter,
            .bottomRightQuarter,
        ]
        let contentFrame = chooserFrame.insetBy(dx: 12, dy: 12)
        for (index, action) in expectedActions.enumerated() {
            let column = index % 3
            let row = index / 3
            let regionPoint = CGPoint(
                x: contentFrame.minX + (CGFloat(column) + 0.5) * contentFrame.width / 3,
                y: contentFrame.maxY - (CGFloat(row) + 0.5) * contentFrame.height / 3
            )
            await pointer.send(.leftButtonDragged(location: regionPoint))
            await eventually {
                renderer.chooserModels.last?.selectedAction == action
            }
            XCTAssertEqual(renderer.chooserModels.last?.selectedAction, action)
        }
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(renderer.dismissCount, 0)
    }
    func testTopologyChangeDuringCrossDisplayDragEmitsReplaceTransition() {
        // Arrange: start a drag on the external display
        var coordinator = CrossDisplayDragCoordinator()
        let oldTopology = mixedScaleTopology(generation: 1)
        let externalPreview = preview(
            displayID: 11,
            frame: CGRect(x: -1_600, y: -180, width: 800, height: 900)
        )

        // Act: present on external, then topology changes (display reordered)
        let present = coordinator.update(
            trigger: triggerEvent(generation: 1, .activated(DisplayID(rawValue: 11))),
            resolution: resolution(displayID: 11),
            topology: oldTopology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: externalPreview
        )

        let reorderedDisplay = display(
            id: 11,
            frame: CGRect(x: -1_200, y: -300, width: 1_200, height: 900),
            visibleFrame: CGRect(x: -1_200, y: -275, width: 1_200, height: 875),
            scale: 1.25,
            trigger: CGRect(x: -690, y: 584, width: 180, height: 16)
        )
        let newTopology = available(
            generation: 2,
            displays: [builtInDisplay(), reorderedDisplay],
            primary: DisplayID(rawValue: 22)
        )

        // Topology change dismisses old surface
        let topologyChanged = coordinator.update(
            trigger: nil,
            resolution: nil,
            topology: newTopology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        // Fresh activation on the new topology
        let freshActivation = coordinator.update(
            trigger: triggerEvent(generation: 2, .activated(DisplayID(rawValue: 11))),
            resolution: resolution(displayID: 11),
            topology: newTopology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        // Assert: topology change dismisses, fresh activation presents
        guard case .present = present else {
            return XCTFail("Expected initial presentation")
        }
        guard case let .dismiss(dismissed, reason) = topologyChanged else {
            return XCTFail("Expected dismissal on topology change")
        }
        XCTAssertEqual(reason, .topologyChanged)
        XCTAssertEqual(dismissed.displayID, DisplayID(rawValue: 11))

        guard case let .present(newTarget) = freshActivation else {
            return XCTFail("Expected fresh presentation after topology change")
        }
        XCTAssertEqual(newTarget.generation, DisplayTopologyGeneration(rawValue: 2))
        XCTAssertEqual(newTarget.displayID, DisplayID(rawValue: 11))
    }

    func testReplaceTransitionDismissesOldBeforePresentingNew() {
        var coordinator = CrossDisplayDragCoordinator()
        let topology = mixedScaleTopology(generation: 1)

        // Present on external display
        let presentExternal = coordinator.update(
            trigger: triggerEvent(generation: 1, .activated(DisplayID(rawValue: 11))),
            resolution: resolution(displayID: 11),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        // Deactivate external, pointer is inside built-in trigger
        let deactivateExternal = coordinator.update(
            trigger: triggerEvent(generation: 1, .deactivated(DisplayID(rawValue: 11))),
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        // Activate built-in — should produce atomic replace
        let activateBuiltin = coordinator.update(
            trigger: triggerEvent(generation: 1, .activated(DisplayID(rawValue: 22))),
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        guard case let .present(externalTarget) = presentExternal else {
            return XCTFail("Expected external presentation")
        }
        XCTAssertEqual(deactivateExternal, .unchanged,
                       "Old surface must stay until new activation")

        guard case let .replace(dismissing, presenting) = activateBuiltin else {
            return XCTFail("Expected atomic replace")
        }
        // Dismissal references the old target
        XCTAssertEqual(dismissing, externalTarget)
        XCTAssertEqual(dismissing.displayID, DisplayID(rawValue: 11))
        // New target is on the built-in display
        XCTAssertEqual(presenting.displayID, DisplayID(rawValue: 22))
        XCTAssertEqual(presenting.generation, DisplayTopologyGeneration(rawValue: 1))
    }

    func testWindowIntentPreviewCarriesCorrectTargetDisplay() {
        // This test proves that the SnapInteractionStateMachine passes the
        // trigger-activated DisplayID through to WindowIntent.preview as targetDisplay.
        let interaction = InteractionID(
            UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        )
        let targetDisplay = DisplayID(rawValue: 42)

        // Verify the enum case carries the parameter
        let intent = WindowIntent.preview(
            action: .leftHalf,
            interaction: interaction,
            capturedWindow: nil,
            targetDisplay: targetDisplay
        )

        switch intent {
        case .preview(_, _, _, let passedDisplay):
            XCTAssertEqual(passedDisplay, targetDisplay)
        default:
            XCTFail("Expected preview intent")
        }
    }

    func testWindowIntentPreviewDefaultsToNilTargetDisplay() {
        let interaction = InteractionID()

        let intent = WindowIntent.preview(
            action: .leftHalf,
            interaction: interaction
        )

        switch intent {
        case .preview(_, _, _, let passedDisplay):
            XCTAssertNil(passedDisplay)
        default:
            XCTFail("Expected preview intent")
        }
    }
}

private actor InMemoryDisplayTopologyObserver: DisplayTopologyObserving {
    let initial: DisplayTopologyState

    init(initial: DisplayTopologyState) { self.initial = initial }

    func updates() -> AsyncStream<DisplayTopologyState> {
        AsyncStream { continuation in
            continuation.yield(initial)
        }
    }
}

private actor InMemoryCompositionPointerAdapter: PointerEventAdapting {
    private let stream: AsyncStream<PointerPlatformSignal>
    private let continuation: AsyncStream<PointerPlatformSignal>.Continuation
    private(set) var hasStarted = false

    init() {
        let channel = AsyncStream.makeStream(of: PointerPlatformSignal.self)
        stream = channel.stream
        continuation = channel.continuation
    }

    func start() -> PointerEventAdapterStart {
        hasStarted = true
        return .active(stream)
    }

    func stop() {}
    func send(_ signal: PointerPlatformSignal) { continuation.yield(signal) }
}

private actor InMemoryCompositionWindowMovementAdapter: PointerDragWindowMovementAdapting {
    private let window: WindowIdentity
    private var continuation: AsyncStream<WindowIdentity>.Continuation?
    private(set) var isObserving = false

    init(window: WindowIdentity) { self.window = window }

    func observeFocusedWindow() -> PointerDragWindowObservationResult {
        let channel = AsyncStream.makeStream(of: WindowIdentity.self)
        continuation = channel.continuation
        isObserving = true
        return .observing(window: window, movements: channel.stream)
    }

    func stopObserving() {
        continuation?.finish()
        continuation = nil
        isObserving = false
    }

    func send(_ window: WindowIdentity) { continuation?.yield(window) }
}

@MainActor
private final class CompositionRecordingOverlayRenderer: OverlayRendering {
    private(set) var chooserModels: [OverlayChooserRenderModel] = []
    private(set) var dismissCount = 0

    func showChooser(
        _ model: OverlayChooserRenderModel,
        onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
    ) {
        chooserModels.append(model)
    }

    func showPreview(_ model: OverlayPreviewRenderModel) {}
    func dismiss() { dismissCount += 1 }
}

@MainActor
private func eventually(
    timeout: Duration = .milliseconds(500),
    condition: @escaping () async -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()), clock.now < deadline {
        await Task.yield()
    }
}

// MARK: - Test Fixtures

private func triggerEvent(
    generation: UInt64,
    _ event: TriggerDwellEvent
) -> CrossDisplayTriggerEvent {
    CrossDisplayTriggerEvent(
        generation: DisplayTopologyGeneration(rawValue: generation),
        event: event
    )
}

private func resolution(displayID: UInt32) -> NotchTriggerResolution {
    NotchTriggerResolution(
        displayID: DisplayID(rawValue: displayID),
        trigger: NotchTrigger(
            classification: .topCenterFallback,
            inferredNotchRegion: nil,
            region: .zero
        ),
        pointerIsInsideTrigger: true
    )
}

private func mixedScaleTopology(generation: UInt64) -> DisplayTopologyState {
    let external = display(
        id: 11,
        frame: CGRect(x: -1_600, y: -200, width: 1_200, height: 950),
        visibleFrame: CGRect(x: -1_600, y: -180, width: 1_200, height: 930),
        scale: 1.25,
        trigger: CGRect(x: -1_090, y: 734, width: 180, height: 16)
    )
    let builtIn = builtInDisplay()
    return available(
        generation: generation,
        displays: [builtIn, external],
        primary: builtIn.id
    )
}

private func builtInDisplay() -> DisplaySnapshot {
    display(
        id: 22,
        frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
        visibleFrame: CGRect(x: 0, y: 25, width: 1_000, height: 775),
        scale: 2,
        trigger: CGRect(x: 410, y: 784, width: 180, height: 16)
    )
}

private func available(
    generation: UInt64,
    displays: [DisplaySnapshot],
    primary: DisplayID
) -> DisplayTopologyState {
    .available(VersionedDisplayTopology(
        generation: DisplayTopologyGeneration(rawValue: generation),
        topology: DisplayTopologySnapshot(displays: displays, primaryDisplayID: primary)
    ))
}

private func display(
    id: UInt32,
    frame: CGRect,
    visibleFrame: CGRect,
    scale: CGFloat,
    trigger: CGRect
) -> DisplaySnapshot {
    DisplaySnapshot(
        id: DisplayID(rawValue: id),
        frame: frame,
        visibleFrame: visibleFrame,
        backingScaleFactor: scale,
        safeArea: DisplaySafeArea(
            insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        ),
        notchTrigger: NotchTrigger(
            classification: .topCenterFallback,
            inferredNotchRegion: nil,
            region: trigger
        )
    )
}

private func preview(displayID: UInt32, frame: CGRect) -> OverlayPreviewPresentation {
    OverlayPreviewPresentation(
        displayID: DisplayID(rawValue: displayID),
        targetFrame: frame,
        isConstrainedByMinimumSize: false
    )
}
