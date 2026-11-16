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
import XCTest
@testable import MyMacX

@MainActor
final class OverlayCoordinatorTests: XCTestCase {
    func testActiveChooserKeyboardAdapterRoutesArrowReturnAndEscapeWithoutRetainingRawInput() async {
        let renderer = RecordingOverlayRenderer()
        let events = OverlayChooserEventRecorder()
        let coordinator = OverlayCoordinator(renderer: renderer, onEvent: events.record)
        let keyboard = LayoutChooserKeyboardInputAdapter()
        coordinator.installKeyboardInputAdapter(keyboard)
        _ = coordinator.presentChooser(chooserPresentation())

        XCTAssertEqual(keyboard.handle(keyDown(124)), .consume)
        await eventually { renderer.chooserModels.last?.selectedAction == .leftHalf }
        XCTAssertEqual(keyboard.handle(keyDown(36)), .consume)
        await eventually { renderer.dismissCount == 1 }
        XCTAssertEqual(
            events.events,
            [.selectionChanged(action: .leftHalf), .confirmed(action: .leftHalf)]
        )

        _ = coordinator.presentChooser(chooserPresentation(initialSelection: .rightHalf))
        XCTAssertEqual(keyboard.handle(keyDown(53)), .consume)
        await eventually { renderer.dismissCount == 2 }
        XCTAssertEqual(events.events.last, .cancelled)

        XCTAssertFalse(keyboard.isAcceptingInput)
        XCTAssertEqual(keyboard.handle(keyDown(0)), .passThrough)
    }

    func testChooserKeyboardAdapterRoutesEveryArrowInVisualDirections() async {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let keyboard = LayoutChooserKeyboardInputAdapter()
        coordinator.installKeyboardInputAdapter(keyboard)
        _ = coordinator.presentChooser(
            chooserPresentation(
                choices: [
                    choice(.maximize), choice(.leftHalf), choice(.rightHalf),
                    choice(.topHalf), choice(.bottomHalf), choice(.topLeftQuarter),
                ],
                columnCount: 3,
                initialSelection: .bottomHalf
            )
        )

        XCTAssertEqual(keyboard.handle(keyDown(123)), .consume)
        await eventually { renderer.chooserModels.last?.selectedAction == .topHalf }
        XCTAssertEqual(keyboard.handle(keyDown(126)), .consume)
        await eventually { renderer.chooserModels.last?.selectedAction == .maximize }
        XCTAssertEqual(keyboard.handle(keyDown(124)), .consume)
        await eventually { renderer.chooserModels.last?.selectedAction == .leftHalf }
        XCTAssertEqual(keyboard.handle(keyDown(125)), .consume)
        await eventually { renderer.chooserModels.last?.selectedAction == .bottomHalf }
    }

    func testChooserKeyboardAdapterPassesUnrelatedModifiedAndNonKeyDownInputThrough() {
        let coordinator = OverlayCoordinator(renderer: RecordingOverlayRenderer())
        let keyboard = LayoutChooserKeyboardInputAdapter()
        coordinator.installKeyboardInputAdapter(keyboard)
        _ = coordinator.presentChooser(chooserPresentation())

        XCTAssertEqual(keyboard.handle(keyDown(0)), .passThrough)
        XCTAssertEqual(
            keyboard.handle(keyDown(124, modifiers: CGEventFlags.maskCommand.rawValue)),
            .passThrough
        )
        XCTAssertEqual(
            keyboard.handle(
                .key(
                    EventTapKeySignal(
                        kind: .keyUp,
                        hardwareKeyCode: 124,
                        modifierFlags: 0,
                        isRepeat: false
                    )
                )
            ),
            .passThrough
        )
        XCTAssertEqual(keyboard.handle(.disabledByTimeout), .passThrough)
        XCTAssertTrue(keyboard.isAcceptingInput)
    }

    func testChooserUsesCompactMacOSNativeVisualSystem() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)

        _ = coordinator.presentChooser(chooserPresentation())

        let style = try! XCTUnwrap(renderer.chooserModels.last?.visualStyle)
        XCTAssertEqual(style.cornerRadius, 16)
        XCTAssertEqual(style.contentPadding, 14)
        XCTAssertEqual(style.itemSpacing, 8)
        XCTAssertEqual(style.minimumTargetSize, CGSize(width: 64, height: 52))
        XCTAssertTrue(style.showsOnlySelectedTitle)
        XCTAssertTrue(style.usesLayoutGlyphs)
    }

    func testPointerHitTestingUsesTheSameContentPaddingAsTheRenderedChooser() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let panel = CGRect(x: 100, y: 100, width: 360, height: 220)
        _ = coordinator.presentChooser(chooserPresentation(panelFrame: panel))

        XCTAssertEqual(
            coordinator.trackPointer(at: CGPoint(x: panel.minX + 13, y: panel.midY)),
            .insideChooser(displayID: DisplayID(rawValue: 1), action: nil)
        )
        XCTAssertEqual(
            coordinator.trackPointer(at: CGPoint(x: panel.minX + 15, y: panel.maxY - 15)),
            .insideChooser(displayID: DisplayID(rawValue: 1), action: .maximize)
        )
    }

    func testRuntimePreferenceUpdateRedrawsVisibleChooserAndAppliesToNextPreview() {
        let renderer = RecordingOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        _ = coordinator.presentChooser(chooserPresentation())

        coordinator.updateAccessibilityPreferences(.init(
            reduceMotion: true,
            reduceTransparency: true
        ))
        _ = coordinator.showPreview(previewPresentation())

        XCTAssertEqual(renderer.chooserModels.count, 2)
        XCTAssertEqual(renderer.chooserModels.last?.presentationPolicy.motion, .immediate)
        XCTAssertEqual(renderer.chooserModels.last?.presentationPolicy.background, .opaque)
        XCTAssertEqual(renderer.previewModels.last?.presentationPolicy.motion, .immediate)
        XCTAssertEqual(renderer.previewModels.last?.presentationPolicy.background, .opaque)
    }

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

private func keyDown(
    _ hardwareKeyCode: UInt16,
    modifiers: UInt64 = 0,
    isRepeat: Bool = false
) -> EventTapSignal {
    .key(
        EventTapKeySignal(
            kind: .keyDown,
            hardwareKeyCode: hardwareKeyCode,
            modifierFlags: modifiers,
            isRepeat: isRepeat
        )
    )
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        await Task.yield()
    }
}
