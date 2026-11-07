import CoreGraphics
import XCTest

@testable import MyMacX

final class EdgeSnapGeometryResolverTests: XCTestCase {
    // MARK: - Z-01: Canonical 8-Zone Perimeter Topology & Corner Band Scaling

    func testZ01_Canonical8ZonePerimeterAndCornerBandScaling() throws {
        // Test corner band calculations for various screen sizes
        // Standard laptop: 1512 x 982 -> 18% width = 272.16 (clamped to 180), 18% height = 176.76 (clamped to 160)
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerWidth(for: 1512), 180)
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerHeight(for: 982), 160)

        // Small screen: 400 x 300 -> 18% width = 72 (clamped to 96), 18% height = 54 (clamped to 80)
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerWidth(for: 400), 96)
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerHeight(for: 300), 80)

        // Mid screen: 800 x 600 -> 18% width = 144, 18% height = 108
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerWidth(for: 800), 144)
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerHeight(for: 600), 108)

        let screen = display(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let topology = DisplayTopologySnapshot(displays: [screen], primaryDisplayID: screen.id)
        let resolver = EdgeSnapGeometryResolver()

        // Corner width for 1000 = 180, corner height for 800 = 144
        // Activation distance is 12 pt.
        // Test pointer 10 pt inside top edge, middle of screen -> straight top
        let topTarget = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 500, y: 792),
                topology: topology
            )
        )
        XCTAssertEqual(topTarget.zone, .top)

        // Pointer 15 pt inside top edge -> outside activation distance, returns nil
        XCTAssertNil(
            resolver.resolve(
                pointerLocation: CGPoint(x: 500, y: 780),
                topology: topology
            )
        )

        // Pointer in top-left corner band (x <= 180, within 12 pt of top) -> topLeft
        let topLeftTarget = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 100, y: 795),
                topology: topology
            )
        )
        XCTAssertEqual(topLeftTarget.zone, .topLeft)
    }

    // MARK: - Z-02: Default Action Assignments

    func testZ02_DefaultActionAssignments() throws {
        let screen = display(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let topology = DisplayTopologySnapshot(displays: [screen], primaryDisplayID: screen.id)
        let resolver = EdgeSnapGeometryResolver()

        // cornerWidth = 180, cornerHeight = 144
        // 1. topLeft: near top-left (50, 795)
        let tl = try XCTUnwrap(resolver.resolve(pointerLocation: CGPoint(x: 50, y: 795), topology: topology))
        XCTAssertEqual(tl.zone, .topLeft)
        XCTAssertEqual(tl.action, .topLeftQuarter)

        // 2. top: center-top (500, 795)
        let t = try XCTUnwrap(resolver.resolve(pointerLocation: CGPoint(x: 500, y: 795), topology: topology))
        XCTAssertEqual(t.zone, .top)
        XCTAssertEqual(t.action, .maximize)

        // 3. topRight: near top-right (950, 795)
        let tr = try XCTUnwrap(resolver.resolve(pointerLocation: CGPoint(x: 950, y: 795), topology: topology))
        XCTAssertEqual(tr.zone, .topRight)
        XCTAssertEqual(tr.action, .topRightQuarter)

        // 4. left: middle-left (5, 400)
        let l = try XCTUnwrap(resolver.resolve(pointerLocation: CGPoint(x: 5, y: 400), topology: topology))
        XCTAssertEqual(l.zone, .left)
        XCTAssertEqual(l.action, .leftHalf)

        // 5. right: middle-right (995, 400)
        let r = try XCTUnwrap(resolver.resolve(pointerLocation: CGPoint(x: 995, y: 400), topology: topology))
        XCTAssertEqual(r.zone, .right)
        XCTAssertEqual(r.action, .rightHalf)

        // 6. bottomLeft: near bottom-left (50, 5)
        let bl = try XCTUnwrap(resolver.resolve(pointerLocation: CGPoint(x: 50, y: 5), topology: topology))
        XCTAssertEqual(bl.zone, .bottomLeft)
        XCTAssertEqual(bl.action, .bottomLeftQuarter)

        // 7. bottom: center-bottom (500, 5)
        let b = try XCTUnwrap(resolver.resolve(pointerLocation: CGPoint(x: 500, y: 5), topology: topology))
        XCTAssertEqual(b.zone, .bottom)
        XCTAssertEqual(b.action, .bottomHalf)

        // 8. bottomRight: near bottom-right (950, 5)
        let br = try XCTUnwrap(resolver.resolve(pointerLocation: CGPoint(x: 950, y: 5), topology: topology))
        XCTAssertEqual(br.zone, .bottomRight)
        XCTAssertEqual(br.action, .bottomRightQuarter)
    }

    // MARK: - Z-05: Allowed Action Whitelist

    func testZ05_AllowedActionWhitelist() {
        // Whitelist permits standard dockings
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.maximize))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.leftHalf))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.rightHalf))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.topHalf))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.bottomHalf))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.topLeftQuarter))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.topRightQuarter))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.bottomLeftQuarter))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.bottomRightQuarter))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.leftThird))
        XCTAssertTrue(EdgeSnapZone.isPermittedAction(.leftTwoThirds))

        // Whitelist rejects relative/dynamic/display actions
        XCTAssertFalse(EdgeSnapZone.isPermittedAction(.nativeFullScreen))
        XCTAssertFalse(EdgeSnapZone.isPermittedAction(.restore))
        XCTAssertFalse(EdgeSnapZone.isPermittedAction(.moveDisplayNext))
        XCTAssertFalse(EdgeSnapZone.isPermittedAction(.moveDisplayPrevious))
        XCTAssertFalse(EdgeSnapZone.isPermittedAction(ActionID(rawValue: "window.center")))
    }

    // MARK: - Z-07: Resilient Fallback to Default Action

    func testZ07_ResilientFallbackToDefaultAction() throws {
        let screen = display(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let topology = DisplayTopologySnapshot(displays: [screen], primaryDisplayID: screen.id)
        let resolver = EdgeSnapGeometryResolver()

        // Custom config mapping .top to disallowed action .nativeFullScreen
        let badConfig = EdgeSnapZoneConfiguration(
            customActions: [.top: .nativeFullScreen]
        )
        let target = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 500, y: 795),
                topology: topology,
                configuration: badConfig
            )
        )
        // Degrades cleanly to default action .maximize
        XCTAssertEqual(target.zone, .top)
        XCTAssertEqual(target.action, .maximize)

        // Valid custom action mapping .top to .topHalf is accepted
        let goodConfig = EdgeSnapZoneConfiguration(
            customActions: [.top: .topHalf]
        )
        let targetGood = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 500, y: 795),
                topology: topology,
                configuration: goodConfig
            )
        )
        XCTAssertEqual(targetGood.action, .topHalf)
    }

    // MARK: - Z-08: Per-Zone Disable Switches

    func testZ08_PerZoneDisableSwitches() throws {
        let screen = display(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let topology = DisplayTopologySnapshot(displays: [screen], primaryDisplayID: screen.id)
        let resolver = EdgeSnapGeometryResolver()

        // Disable .top zone
        let configWithTopDisabled = EdgeSnapZoneConfiguration(
            disabledZones: [.top]
        )

        // Pointer in .top zone resolves to nil (stands down)
        XCTAssertNil(
            resolver.resolve(
                pointerLocation: CGPoint(x: 500, y: 795),
                topology: topology,
                configuration: configWithTopDisabled
            )
        )

        // Other zones (e.g. .left) still resolve normally
        let leftTarget = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 5, y: 400),
                topology: topology,
                configuration: configWithTopDisabled
            )
        )
        XCTAssertEqual(leftTarget.zone, .left)
        XCTAssertEqual(leftTarget.action, .leftHalf)
    }

    // MARK: - S-10: Equidistant Seam Coordinate Tie-Breaking

    func testS10_EquidistantSeamCoordinateTieBreaking() throws {
        // Two side-by-side displays: left (0...1000), right (1000...2000)
        let leftScreen = display(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000)
        )
        let rightScreen = display(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000)
        )
        let topology = DisplayTopologySnapshot(
            displays: [leftScreen, rightScreen],
            primaryDisplayID: leftScreen.id
        )
        let resolver = EdgeSnapGeometryResolver()

        // Pointer exactly on seam at x = 1000, y = 500
        // S-10 tie-breaking awards ownership to the display holding x >= minX && x < maxX
        // rightScreen minX is 1000, so 1000 is inside rightScreen's half-open frame!
        let target = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 1000, y: 500),
                topology: topology
            )
        )
        XCTAssertEqual(target.displayID, rightScreen.id)
        // On right display, x = 1000 is its left edge
        XCTAssertEqual(target.zone, .left)
    }

    // MARK: - Helpers

    private func display(
        id: UInt32,
        frame: CGRect
    ) -> DisplaySnapshot {
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
}
