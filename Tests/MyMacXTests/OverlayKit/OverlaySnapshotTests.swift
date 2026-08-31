import AppKit
import CoreGraphics
import XCTest

@testable import MyMacX

// MARK: - Recording renderer (snapshot variant)

@MainActor
private final class SnapshotOverlayRenderer: OverlayRendering {
    private(set) var chooserModels: [OverlayChooserRenderModel] = []
    private(set) var previewModels: [OverlayPreviewRenderModel] = []
    private(set) var dismissCount = 0

    func showChooser(
        _ model: OverlayChooserRenderModel,
        onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
    ) {
        chooserModels.append(model)
    }

    func showPreview(_ model: OverlayPreviewRenderModel) {
        previewModels.append(model)
    }

    func dismiss() {
        dismissCount += 1
    }
}

// MARK: - Test helpers

private func snapshotChoices() -> [OverlayLayoutChoice] {
    [
        OverlayLayoutChoice(action: .maximize, title: "Maximize", accessibilityLabel: "Maximize"),
        OverlayLayoutChoice(action: .leftHalf, title: "Left Half", accessibilityLabel: "Left Half"),
        OverlayLayoutChoice(action: .rightHalf, title: "Right Half", accessibilityLabel: "Right Half"),
        OverlayLayoutChoice(action: .topHalf, title: "Top Half", accessibilityLabel: "Top Half"),
        OverlayLayoutChoice(action: .bottomHalf, title: "Bottom Half", accessibilityLabel: "Bottom Half"),
        OverlayLayoutChoice(action: .topLeftQuarter, title: "Top Left", accessibilityLabel: "Top Left"),
    ]
}

private func snapshotChooserPresentation(
    panelFrame: CGRect = CGRect(x: 540, y: 720, width: 360, height: 220),
    choices: [OverlayLayoutChoice] = snapshotChoices(),
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

private func snapshotPreviewPresentation(
    targetFrame: CGRect = CGRect(x: 0, y: 25, width: 720, height: 875),
    constrained: Bool = false
) -> OverlayPreviewPresentation {
    OverlayPreviewPresentation(
        displayID: DisplayID(rawValue: 1),
        targetFrame: targetFrame,
        isConstrainedByMinimumSize: constrained
    )
}

// MARK: - Assertion helpers

private func assertChooserBaseline(
    _ model: OverlayChooserRenderModel,
    expectedPanelFrame: CGRect,
    expectedChoiceCount: Int,
    expectedSelectedAction: ActionID,
    expectedColumnCount: Int,
    expectedMotion: OverlayMotionTreatment,
    expectedBackground: OverlayBackgroundTreatment,
    expectedContrast: OverlayContrastTreatment,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(model.panelFrame, expectedPanelFrame, "panelFrame", file: file, line: line)
    XCTAssertEqual(model.choices.count, expectedChoiceCount, "choice count", file: file, line: line)
    XCTAssertEqual(model.selectedAction, expectedSelectedAction, "selectedAction", file: file, line: line)
    XCTAssertEqual(model.columnCount, expectedColumnCount, "columnCount", file: file, line: line)
    XCTAssertEqual(model.presentationPolicy.motion, expectedMotion, "motion", file: file, line: line)
    XCTAssertEqual(model.presentationPolicy.background, expectedBackground, "background", file: file, line: line)
    XCTAssertEqual(model.presentationPolicy.contrast, expectedContrast, "contrast", file: file, line: line)
}

private func assertPreviewBaseline(
    _ model: OverlayPreviewRenderModel,
    expectedTargetFrame: CGRect,
    expectedConstrained: Bool,
    expectedMotion: OverlayMotionTreatment,
    expectedBackground: OverlayBackgroundTreatment,
    expectedContrast: OverlayContrastTreatment,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(model.targetFrame, expectedTargetFrame, "targetFrame", file: file, line: line)
    XCTAssertEqual(model.isConstrainedByMinimumSize, expectedConstrained, "isConstrainedByMinimumSize", file: file, line: line)
    XCTAssertEqual(model.presentationPolicy.motion, expectedMotion, "motion", file: file, line: line)
    XCTAssertEqual(model.presentationPolicy.background, expectedBackground, "background", file: file, line: line)
    XCTAssertEqual(model.presentationPolicy.contrast, expectedContrast, "contrast", file: file, line: line)
}

// MARK: - Snapshot tests

@MainActor
final class OverlaySnapshotTests: XCTestCase {

    // MARK: Chooser — light mode, standard accessibility

    func testChooserRenderModel_LightMode_StandardAccessibility() {
        let renderer = SnapshotOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let panelFrame = CGRect(x: 540, y: 720, width: 360, height: 220)
        let choices = snapshotChoices()

        let result = coordinator.presentChooser(
            snapshotChooserPresentation(panelFrame: panelFrame, choices: choices)
        )

        XCTAssertEqual(result, .shown(action: .maximize))
        let model = try! XCTUnwrap(renderer.chooserModels.last)
        assertChooserBaseline(
            model,
            expectedPanelFrame: panelFrame,
            expectedChoiceCount: 6,
            expectedSelectedAction: .maximize,
            expectedColumnCount: 3,
            expectedMotion: .standard,
            expectedBackground: .translucent,
            expectedContrast: .standard
        )
    }

    // MARK: Chooser — dark mode, reduce motion

    func testChooserRenderModel_DarkMode_ReduceMotion() {
        let renderer = SnapshotOverlayRenderer()
        let coordinator = OverlayCoordinator(
            renderer: renderer,
            accessibilityPreferences: OverlayAccessibilityPreferences(
                reduceMotion: true,
                reduceTransparency: true
            )
        )

        let result = coordinator.presentChooser(snapshotChooserPresentation())

        XCTAssertEqual(result, .shown(action: .maximize))
        let model = try! XCTUnwrap(renderer.chooserModels.last)
        assertChooserBaseline(
            model,
            expectedPanelFrame: CGRect(x: 540, y: 720, width: 360, height: 220),
            expectedChoiceCount: 6,
            expectedSelectedAction: .maximize,
            expectedColumnCount: 3,
            expectedMotion: .immediate,
            expectedBackground: .opaque,
            expectedContrast: .standard
        )
    }

    // MARK: Chooser — high contrast

    func testChooserRenderModel_HighContrast() {
        let renderer = SnapshotOverlayRenderer()
        let coordinator = OverlayCoordinator(
            renderer: renderer,
            accessibilityPreferences: OverlayAccessibilityPreferences(increaseContrast: true)
        )

        let result = coordinator.presentChooser(snapshotChooserPresentation())

        XCTAssertEqual(result, .shown(action: .maximize))
        let model = try! XCTUnwrap(renderer.chooserModels.last)
        assertChooserBaseline(
            model,
            expectedPanelFrame: CGRect(x: 540, y: 720, width: 360, height: 220),
            expectedChoiceCount: 6,
            expectedSelectedAction: .maximize,
            expectedColumnCount: 3,
            expectedMotion: .standard,
            expectedBackground: .translucent,
            expectedContrast: .increased
        )
    }

    // MARK: Preview — standard

    func testPreviewRenderModel_Standard() {
        let renderer = SnapshotOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let targetFrame = CGRect(x: 0, y: 25, width: 720, height: 875)

        let result = coordinator.showPreview(
            snapshotPreviewPresentation(targetFrame: targetFrame, constrained: false)
        )

        XCTAssertEqual(result, .shown)
        let model = try! XCTUnwrap(renderer.previewModels.last)
        assertPreviewBaseline(
            model,
            expectedTargetFrame: targetFrame,
            expectedConstrained: false,
            expectedMotion: .standard,
            expectedBackground: .translucent,
            expectedContrast: .standard
        )
    }

    // MARK: Preview — constrained by minimum size

    func testPreviewRenderModel_ConstrainedByMinimumSize() {
        let renderer = SnapshotOverlayRenderer()
        let coordinator = OverlayCoordinator(renderer: renderer)
        let targetFrame = CGRect(x: -1_440, y: 25, width: 720, height: 875)

        let result = coordinator.showPreview(
            snapshotPreviewPresentation(targetFrame: targetFrame, constrained: true)
        )

        XCTAssertEqual(result, .shown)
        let model = try! XCTUnwrap(renderer.previewModels.last)
        assertPreviewBaseline(
            model,
            expectedTargetFrame: targetFrame,
            expectedConstrained: true,
            expectedMotion: .standard,
            expectedBackground: .translucent,
            expectedContrast: .standard
        )
    }
}
