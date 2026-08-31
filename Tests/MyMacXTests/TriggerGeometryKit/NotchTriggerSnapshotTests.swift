import CoreGraphics
import XCTest

@testable import MyMacX

// MARK: - Display fixtures

private func notchDisplay(
    id: UInt32 = 1,
    frame: CGRect = CGRect(x: 1_920, y: 124, width: 1_470, height: 956),
    visibleFrame: CGRect = CGRect(x: 1_920, y: 124, width: 1_470, height: 924),
    scale: CGFloat = 2,
    triggerRegion: CGRect = CGRect(x: 2_534, y: 1_028, width: 243, height: 52)
) -> DisplaySnapshot {
    DisplaySnapshot(
        id: DisplayID(rawValue: id),
        frame: frame,
        visibleFrame: visibleFrame,
        backingScaleFactor: scale,
        safeArea: DisplaySafeArea(
            insets: DisplayEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        ),
        notchTrigger: NotchTrigger(
            classification: .notch,
            inferredNotchRegion: CGRect(x: 2_566, y: 1_048, width: 179, height: 32),
            region: triggerRegion
        )
    )
}

private func nonNotchDisplay(
    id: UInt32 = 2,
    frame: CGRect = CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
    visibleFrame: CGRect = CGRect(x: 0, y: 0, width: 1_920, height: 1_050),
    scale: CGFloat = 1,
    triggerRegion: CGRect = CGRect(x: 870, y: 1_064, width: 180, height: 16)
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
            region: triggerRegion
        )
    )
}

// MARK: - Snapshot tests

final class NotchTriggerSnapshotTests: XCTestCase {

    // MARK: Trigger region calculation — notch display

    func testNotchDisplay_TriggerRegionMatchesExpectedBounds() throws {
        let display = notchDisplay()
        let topology = DisplayTopologySnapshot(
            displays: [display],
            primaryDisplayID: display.id
        )

        // Pointer inside notch trigger
        let inside = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 2_600, y: 1_050),
                topology: topology
            )
        )
        XCTAssertEqual(inside.displayID, display.id)
        XCTAssertEqual(inside.trigger.classification, .notch)
        XCTAssertTrue(inside.pointerIsInsideTrigger)
        XCTAssertEqual(
            inside.trigger.region,
            CGRect(x: 2_534, y: 1_028, width: 243, height: 52)
        )
        XCTAssertNotNil(inside.trigger.inferredNotchRegion)

        // Pointer outside notch trigger but on display
        let outside = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 2_000, y: 500),
                topology: topology
            )
        )
        XCTAssertEqual(outside.displayID, display.id)
        XCTAssertFalse(outside.pointerIsInsideTrigger)
    }

    // MARK: Trigger region calculation — non-notch display

    func testNonNotchDisplay_TopCenterFallbackTriggerRegionMatchesExpectedBounds() throws {
        let display = nonNotchDisplay()
        let topology = DisplayTopologySnapshot(
            displays: [display],
            primaryDisplayID: display.id
        )

        // Pointer inside top-center fallback trigger
        let inside = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 960, y: 1_072),
                topology: topology
            )
        )
        XCTAssertEqual(inside.displayID, display.id)
        XCTAssertEqual(inside.trigger.classification, .topCenterFallback)
        XCTAssertNil(inside.trigger.inferredNotchRegion)
        XCTAssertTrue(inside.pointerIsInsideTrigger)
        XCTAssertEqual(
            inside.trigger.region,
            CGRect(x: 870, y: 1_064, width: 180, height: 16)
        )

        // Pointer outside trigger
        let outside = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 100, y: 500),
                topology: topology
            )
        )
        XCTAssertEqual(outside.displayID, display.id)
        XCTAssertFalse(outside.pointerIsInsideTrigger)
    }

    // MARK: Trigger region within visible frame bounds

    func testNotchTrigger_RegionIsWithinDisplayFrame() {
        let display = notchDisplay()
        XCTAssertTrue(
            display.frame.contains(display.notchTrigger.region),
            "Notch trigger region must be within the display frame"
        )
    }

    func testNonNotchTrigger_RegionIsWithinDisplayFrame() {
        let display = nonNotchDisplay()
        // The top-center fallback extends to the physical top edge (maxY),
        // which is the display frame boundary.
        let trigger = display.notchTrigger.region
        XCTAssertGreaterThanOrEqual(trigger.minX, display.frame.minX)
        XCTAssertLessThanOrEqual(trigger.maxX, display.frame.maxX)
        XCTAssertGreaterThanOrEqual(trigger.minY, display.frame.minY)
        XCTAssertLessThanOrEqual(trigger.maxY, display.frame.maxY)
    }

    // MARK: Chooser frame fitting within visible frame bounds

    func testChooserPanelFrame_FitsWithinNotchDisplayVisibleFrame() {
        let display = notchDisplay()
        let chooserWidth: CGFloat = 360
        let chooserHeight: CGFloat = 220

        // Place chooser centered horizontally in the visible frame, near the top
        let chooserFrame = CGRect(
            x: display.visibleFrame.midX - chooserWidth / 2,
            y: display.visibleFrame.maxY - chooserHeight - 20,
            width: chooserWidth,
            height: chooserHeight
        )

        XCTAssertTrue(
            display.visibleFrame.contains(chooserFrame),
            "Chooser panel must fit within the visible frame of a notch display"
        )
    }

    func testChooserPanelFrame_FitsWithinNonNotchDisplayVisibleFrame() {
        let display = nonNotchDisplay()
        let chooserWidth: CGFloat = 360
        let chooserHeight: CGFloat = 220

        let chooserFrame = CGRect(
            x: display.visibleFrame.midX - chooserWidth / 2,
            y: display.visibleFrame.maxY - chooserHeight - 20,
            width: chooserWidth,
            height: chooserHeight
        )

        XCTAssertTrue(
            display.visibleFrame.contains(chooserFrame),
            "Chooser panel must fit within the visible frame of a non-notch display"
        )
    }

    // MARK: Mixed topology — notch and non-notch coexist

    func testMixedTopology_ResolvesCorrectDisplayForEachPointerLocation() throws {
        let external = nonNotchDisplay(id: 2)
        let builtIn = notchDisplay(id: 1)
        let topology = DisplayTopologySnapshot(
            displays: [external, builtIn],
            primaryDisplayID: external.id
        )

        // Pointer on external display
        let externalResolution = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 960, y: 540),
                topology: topology
            )
        )
        XCTAssertEqual(externalResolution.displayID, external.id)
        XCTAssertEqual(externalResolution.trigger.classification, .topCenterFallback)

        // Pointer on built-in display inside notch
        let builtInResolution = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 2_600, y: 1_050),
                topology: topology
            )
        )
        XCTAssertEqual(builtInResolution.displayID, builtIn.id)
        XCTAssertEqual(builtInResolution.trigger.classification, .notch)
        XCTAssertTrue(builtInResolution.pointerIsInsideTrigger)
    }
}
