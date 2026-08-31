import AppKit
import CoreGraphics
import XCTest
@testable import MyMacX

@MainActor
final class OverlayCoordinatorTests: XCTestCase {
    func testOverlayPresentationPanelIsNonActivatingAndExcludedFromNormalWindowCycling() {
        let panel = OverlayPresentationPanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertFalse(panel.collectionBehavior.contains(.participatesInCycle))
    }

    func testReducedMotionUsesImmediatePresentationForChooserAndPreview() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(
            renderer: renderer,
            accessibilityPreferences: OverlayAccessibilityPreferences(reduceMotion: true)
        )

        _ = coordinator.presentChooser(chooserPresentation())
        _ = coordinator.showPreview(
            OverlayPreviewPresentation(
                displayID: DisplayID(rawValue: 1),
                targetFrame: CGRect(x: 0, y: 0, width: 720, height: 450),
                isConstrainedByMinimumSize: false
            )
        )

        XCTAssertEqual(renderer.chooserModels.last?.presentationPolicy.motion, .immediate)
        XCTAssertEqual(renderer.previewModels.last?.presentationPolicy.motion, .immediate)
    }

    func testReducedTransparencyUsesOpaqueBackgroundForChooserAndPreview() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(
            renderer: renderer,
            accessibilityPreferences: OverlayAccessibilityPreferences(reduceTransparency: true)
        )

        _ = coordinator.presentChooser(chooserPresentation())
        _ = coordinator.showPreview(previewPresentation())

        XCTAssertEqual(renderer.chooserModels.last?.presentationPolicy.background, .opaque)
        XCTAssertEqual(renderer.previewModels.last?.presentationPolicy.background, .opaque)
    }

    func testIncreasedContrastUsesIncreasedTreatmentForChooserAndPreview() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(
            renderer: renderer,
            accessibilityPreferences: OverlayAccessibilityPreferences(increaseContrast: true)
        )

        _ = coordinator.presentChooser(chooserPresentation())
        _ = coordinator.showPreview(previewPresentation())

        XCTAssertEqual(renderer.chooserModels.last?.presentationPolicy.contrast, .increased)
        XCTAssertEqual(renderer.previewModels.last?.presentationPolicy.contrast, .increased)
    }

    func testPresentingChooserForwardsSuppliedPanelFrameAndInitialFocusWithoutCalculatingGeometry() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let presentation = chooserPresentation(
            panelFrame: CGRect(x: -480, y: 880, width: 360, height: 220),
            initialSelection: .rightHalf
        )

        let result = coordinator.presentChooser(presentation)

        XCTAssertEqual(result, .shown(action: .rightHalf))
        XCTAssertEqual(
            renderer.chooserModels,
            [
                OverlayChooserRenderModel(
                    panelFrame: presentation.panelFrame,
                    choices: presentation.choices,
                    selectedAction: .rightHalf,
                    columnCount: presentation.columnCount,
                    presentationPolicy: .init()
                ),
            ]
        )
    }

    func testArrowNavigationSelectsEveryChoiceInVisualOrder() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let presentation = chooserPresentation(
            choices: [
                choice(.maximize),
                choice(.leftHalf),
                choice(.rightHalf),
                choice(.topHalf),
                choice(.bottomHalf),
                choice(.topLeftQuarter),
            ],
            columnCount: 3
        )
        _ = coordinator.presentChooser(presentation)

        XCTAssertEqual(coordinator.moveSelection(.right), .selected(action: .leftHalf))
        XCTAssertEqual(coordinator.moveSelection(.down), .selected(action: .bottomHalf))
        XCTAssertEqual(coordinator.moveSelection(.left), .selected(action: .topHalf))
        XCTAssertEqual(coordinator.moveSelection(.down), .selected(action: .topLeftQuarter))
        XCTAssertEqual(coordinator.moveSelection(.right), .selected(action: .maximize))

        XCTAssertEqual(renderer.chooserModels.map(\.selectedAction), [
            .maximize,
            .leftHalf,
            .bottomHalf,
            .topHalf,
            .topLeftQuarter,
            .maximize,
        ])
    }

    func testKeyboardArrowThenConfirmEmitsSelectionAndConfirmationWithoutExecutingAWindowAction() {
        let renderer = RecordingOverlayRenderer()
        let events = OverlayChooserEventRecorder()
        let coordinator = OverlayCoordinator(renderer: renderer, onEvent: events.record)
        _ = coordinator.presentChooser(chooserPresentation())

        let moved = coordinator.handleKeyboard(.arrow(.right))
        let confirmed = coordinator.handleKeyboard(.confirm)

        XCTAssertEqual(moved, .selectionChanged(action: .leftHalf))
        XCTAssertEqual(confirmed, .confirmed(action: .leftHalf))
        XCTAssertEqual(
            events.events,
            [
                .selectionChanged(action: .leftHalf),
                .confirmed(action: .leftHalf),
            ]
        )
    }

    func testEscapeDismissesChooserEmitsCancellationAndLeavesFurtherKeyboardInputIgnored() {
        let renderer = RecordingOverlayRenderer()
        let events = OverlayChooserEventRecorder()
        let coordinator = OverlayCoordinator(renderer: renderer, onEvent: events.record)
        _ = coordinator.presentChooser(chooserPresentation(initialSelection: .leftHalf))

        let cancelled = coordinator.handleKeyboard(.escape)
        let afterEscape = coordinator.handleKeyboard(.confirm)

        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(afterEscape, .ignored)
        XCTAssertEqual(events.events, [.cancelled])
        XCTAssertEqual(renderer.dismissCount, 1)
    }

    func testPointerSelectionCallbackPublishesOnlyASelectionChangeAndNeverConfirms() {
        let renderer = RecordingOverlayRenderer()
        let events = OverlayChooserEventRecorder()
        let coordinator = OverlayCoordinator(renderer: renderer, onEvent: events.record)
        _ = coordinator.presentChooser(chooserPresentation())

        renderer.select(.rightHalf)

        XCTAssertEqual(events.events, [.selectionChanged(action: .rightHalf)])
        XCTAssertEqual(renderer.chooserModels.last?.selectedAction, .rightHalf)
    }

    func testArrowTraversalCanReachEveryDefaultLayoutAction() {
        let defaultActions: [ActionID] = [
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
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        _ = coordinator.presentChooser(
            chooserPresentation(
                choices: defaultActions.map(choice),
                columnCount: 3
            )
        )

        let reached = defaultActions.dropFirst().map { _ in
            coordinator.handleKeyboard(.arrow(.right))
        }

        XCTAssertEqual(
            reached,
            defaultActions.dropFirst().map(OverlayKeyboardResult.selectionChanged(action:))
        )
    }

    func testPreviewForwardsExactWindowActionFrameAndConstraintWarning() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let presentation = OverlayPreviewPresentation(
            displayID: DisplayID(rawValue: 7),
            targetFrame: CGRect(x: -1440, y: 0, width: 720, height: 900),
            isConstrainedByMinimumSize: true
        )

        let result = coordinator.showPreview(presentation)

        XCTAssertEqual(result, .shown)
        XCTAssertEqual(
            renderer.previewModels,
            [
                OverlayPreviewRenderModel(
                    targetFrame: presentation.targetFrame,
                    isConstrainedByMinimumSize: true,
                    presentationPolicy: .init()
                ),
            ]
        )
    }

    func testRejectsInvalidChooserBeforeRendering() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let presentation = chooserPresentation(
            panelFrame: CGRect(x: 0, y: 0, width: 0, height: 220)
        )

        let result = coordinator.presentChooser(presentation)

        XCTAssertEqual(result, .rejected(.invalidPanelFrame))
        XCTAssertTrue(renderer.chooserModels.isEmpty)
    }

    func testDismissHidesBothSurfaces() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        _ = coordinator.presentChooser(chooserPresentation())
        _ = coordinator.showPreview(
            OverlayPreviewPresentation(
                displayID: DisplayID(rawValue: 1),
                targetFrame: CGRect(x: 0, y: 0, width: 720, height: 450),
                isConstrainedByMinimumSize: false
            )
        )

        coordinator.dismiss()

        XCTAssertEqual(renderer.dismissCount, 1)
    }
}

@MainActor
private final class RecordingOverlayRenderer: OverlayRendering {
    private(set) var chooserModels: [OverlayChooserRenderModel] = []
    private(set) var previewModels: [OverlayPreviewRenderModel] = []
    private(set) var dismissCount = 0
    private var onSelect: (@MainActor @Sendable (ActionID) -> Void)?

    func showChooser(
        _ model: OverlayChooserRenderModel,
        onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
    ) {
        chooserModels.append(model)
        self.onSelect = onSelect
    }

    func showPreview(_ model: OverlayPreviewRenderModel) {
        previewModels.append(model)
    }

    func dismiss() {
        dismissCount += 1
    }

    func select(_ action: ActionID) {
        onSelect?(action)
    }
}

@MainActor
private final class OverlayChooserEventRecorder {
    private(set) var events: [OverlayChooserEvent] = []

    func record(_ event: OverlayChooserEvent) {
        events.append(event)
    }
}

private func chooserPresentation(
    panelFrame: CGRect = CGRect(x: 540, y: 720, width: 360, height: 220),
    choices: [OverlayLayoutChoice] = [
        choice(.maximize),
        choice(.leftHalf),
        choice(.rightHalf),
    ],
    columnCount: Int = 3,
    initialSelection: ActionID? = nil
) -> OverlayChooserPresentation {
    OverlayChooserPresentation(
        displayID: DisplayID(rawValue: 1),
        panelFrame: panelFrame,
        choices: choices,
        columnCount: columnCount,
        initialSelection: initialSelection
    )
}

private func previewPresentation() -> OverlayPreviewPresentation {
    OverlayPreviewPresentation(
        displayID: DisplayID(rawValue: 1),
        targetFrame: CGRect(x: 0, y: 0, width: 720, height: 450),
        isConstrainedByMinimumSize: false
    )
}

private func choice(_ action: ActionID) -> OverlayLayoutChoice {
    OverlayLayoutChoice(
        action: action,
        title: action.rawValue,
        accessibilityLabel: action.rawValue
    )
}
