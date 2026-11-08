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

    // MARK: - Z-03 & Z-04: Multi-Area Partitioning & Fractional Sub-Area Selection

    func testZ03_DefaultPartitionAssignments() {
        // Horizontal top edge
        XCTAssertEqual(EdgeSnapZone.top.defaultPartitions(count: 1), [.maximize])
        XCTAssertEqual(EdgeSnapZone.top.defaultPartitions(count: 2), [.leftHalf, .rightHalf])
        XCTAssertEqual(EdgeSnapZone.top.defaultPartitions(count: 3), [.leftThird, ActionID(rawValue: "window.center-third"), ActionID(rawValue: "window.right-third")])
        XCTAssertEqual(EdgeSnapZone.top.defaultPartitions(count: 4), [ActionID(rawValue: "window.left-quarter"), ActionID(rawValue: "window.left-middle-quarter"), ActionID(rawValue: "window.right-middle-quarter"), ActionID(rawValue: "window.right-quarter")])

        // Horizontal bottom edge
        XCTAssertEqual(EdgeSnapZone.bottom.defaultPartitions(count: 1), [.bottomHalf])
        XCTAssertEqual(EdgeSnapZone.bottom.defaultPartitions(count: 2), [.leftHalf, .rightHalf])
        XCTAssertEqual(EdgeSnapZone.bottom.defaultPartitions(count: 3), [.leftThird, ActionID(rawValue: "window.center-third"), ActionID(rawValue: "window.right-third")])
        XCTAssertEqual(EdgeSnapZone.bottom.defaultPartitions(count: 4), [ActionID(rawValue: "window.left-quarter"), ActionID(rawValue: "window.left-middle-quarter"), ActionID(rawValue: "window.right-middle-quarter"), ActionID(rawValue: "window.right-quarter")])

        // Vertical left edge
        XCTAssertEqual(EdgeSnapZone.left.defaultPartitions(count: 1), [.leftHalf])
        XCTAssertEqual(EdgeSnapZone.left.defaultPartitions(count: 2), [.topHalf, .bottomHalf])
        XCTAssertEqual(EdgeSnapZone.left.defaultPartitions(count: 3), [ActionID(rawValue: "window.top-third"), ActionID(rawValue: "window.middle-third"), ActionID(rawValue: "window.bottom-third")])
        XCTAssertEqual(EdgeSnapZone.left.defaultPartitions(count: 4), [ActionID(rawValue: "window.top-quarter"), ActionID(rawValue: "window.upper-middle-quarter"), ActionID(rawValue: "window.lower-middle-quarter"), ActionID(rawValue: "window.bottom-quarter")])

        // Vertical right edge
        XCTAssertEqual(EdgeSnapZone.right.defaultPartitions(count: 1), [.rightHalf])
        XCTAssertEqual(EdgeSnapZone.right.defaultPartitions(count: 2), [.topHalf, .bottomHalf])
        XCTAssertEqual(EdgeSnapZone.right.defaultPartitions(count: 3), [ActionID(rawValue: "window.top-third"), ActionID(rawValue: "window.middle-third"), ActionID(rawValue: "window.bottom-third")])
        XCTAssertEqual(EdgeSnapZone.right.defaultPartitions(count: 4), [ActionID(rawValue: "window.top-quarter"), ActionID(rawValue: "window.upper-middle-quarter"), ActionID(rawValue: "window.lower-middle-quarter"), ActionID(rawValue: "window.bottom-quarter")])

        // Corners strictly single area (maximumParts = 1)
        XCTAssertEqual(EdgeSnapZone.topLeft.defaultPartitions(count: 1), [.topLeftQuarter])
        XCTAssertEqual(EdgeSnapZone.topLeft.defaultPartitions(count: 3), [.topLeftQuarter])
        XCTAssertEqual(EdgeSnapZone.topRight.defaultPartitions(count: 2), [.topRightQuarter])
    }

    func testZ04_FractionalSubAreaSelectionAlongSplitHorizontalEdge() throws {
        // Display frame: 1000 x 800.
        // Corner width = 180 (minX..180, 820..1000).
        // Straight top edge: x in 180...820, length = 640.
        let screen = display(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let topology = DisplayTopologySnapshot(displays: [screen], primaryDisplayID: screen.id)
        let resolver = EdgeSnapGeometryResolver()

        // 2 partitions on top edge: leftHalf, rightHalf.
        // Division is at x = 180 + 320 = 500.
        let twoPartConfig = EdgeSnapZoneConfiguration(
            customPartitions: [.top: [.leftHalf, .rightHalf]]
        )

        // Point at x = 300 (f = (300 - 180)/640 = 0.1875 -> index 0)
        let targetLeft = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 300, y: 795),
                topology: topology,
                configuration: twoPartConfig
            )
        )
        XCTAssertEqual(targetLeft.zone, .top)
        XCTAssertEqual(targetLeft.partitionIndex, 0)
        XCTAssertEqual(targetLeft.action, .leftHalf)
        XCTAssertEqual(targetLeft.activationRegion, CGRect(x: 180, y: 788, width: 320, height: 12))

        // Point at x = 700 (f = (700 - 180)/640 = 0.8125 -> index 1)
        let targetRight = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 700, y: 795),
                topology: topology,
                configuration: twoPartConfig
            )
        )
        XCTAssertEqual(targetRight.zone, .top)
        XCTAssertEqual(targetRight.partitionIndex, 1)
        XCTAssertEqual(targetRight.action, .rightHalf)
        XCTAssertEqual(targetRight.activationRegion, CGRect(x: 500, y: 788, width: 320, height: 12))

        // 3 partitions on top edge: leftThird, centerThird, rightThird.
        // 640 / 3 = 213.333 pt per partition.
        // Boundary 1: 180 + 213.33 = 393.33
        // Boundary 2: 180 + 426.66 = 606.66
        let threePartConfig = EdgeSnapZoneConfiguration(
            customPartitions: [.top: [.leftThird, ActionID(rawValue: "window.center-third"), ActionID(rawValue: "window.right-third")]]
        )

        let targetP0 = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 250, y: 795),
                topology: topology,
                configuration: threePartConfig
            )
        )
        XCTAssertEqual(targetP0.partitionIndex, 0)
        XCTAssertEqual(targetP0.action, .leftThird)

        let targetP1 = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 500, y: 795),
                topology: topology,
                configuration: threePartConfig
            )
        )
        XCTAssertEqual(targetP1.partitionIndex, 1)
        XCTAssertEqual(targetP1.action, ActionID(rawValue: "window.center-third"))

        let targetP2 = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 750, y: 795),
                topology: topology,
                configuration: threePartConfig
            )
        )
        XCTAssertEqual(targetP2.partitionIndex, 2)
        XCTAssertEqual(targetP2.action, ActionID(rawValue: "window.right-third"))
    }

    func testZ04_FractionalSubAreaSelectionAlongSplitVerticalEdge() throws {
        // Display frame: 1000 x 800.
        // Corner height = 144 (minY..144, 656..800).
        // Straight left edge: y in 144...656, length = 512.
        // In AppKit coords: top of straight edge is y = 656 (f = 0), bottom is y = 144 (f = 1).
        let screen = display(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let topology = DisplayTopologySnapshot(displays: [screen], primaryDisplayID: screen.id)
        let resolver = EdgeSnapGeometryResolver()

        // 2 partitions on left edge: topHalf, bottomHalf.
        // Division is at y = 656 - 256 = 400.
        let twoPartConfig = EdgeSnapZoneConfiguration(
            customPartitions: [.left: [.topHalf, .bottomHalf]]
        )

        // Point near top of left edge: y = 550 (f = (656 - 550)/512 = 0.207 -> index 0)
        let targetTop = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 5, y: 550),
                topology: topology,
                configuration: twoPartConfig
            )
        )
        XCTAssertEqual(targetTop.zone, .left)
        XCTAssertEqual(targetTop.partitionIndex, 0)
        XCTAssertEqual(targetTop.action, .topHalf)
        XCTAssertEqual(targetTop.activationRegion, CGRect(x: 0, y: 400, width: 12, height: 256))

        // Point near bottom of left edge: y = 250 (f = (656 - 250)/512 = 0.792 -> index 1)
        let targetBottom = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 5, y: 250),
                topology: topology,
                configuration: twoPartConfig
            )
        )
        XCTAssertEqual(targetBottom.zone, .left)
        XCTAssertEqual(targetBottom.partitionIndex, 1)
        XCTAssertEqual(targetBottom.action, .bottomHalf)
        XCTAssertEqual(targetBottom.activationRegion, CGRect(x: 0, y: 144, width: 12, height: 256))
    }

    func testZ04_DegradedAndInvalidPartitionsFallback() throws {
        let screen = display(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let topology = DisplayTopologySnapshot(displays: [screen], primaryDisplayID: screen.id)
        let resolver = EdgeSnapGeometryResolver()

        // 1. Unpermitted action in partition reverts entire zone to default action (Z-07)
        let badActionConfig = EdgeSnapZoneConfiguration(
            customPartitions: [.top: [.leftHalf, .nativeFullScreen]]
        )
        let targetBadAction = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 300, y: 795),
                topology: topology,
                configuration: badActionConfig
            )
        )
        XCTAssertEqual(targetBadAction.action, .maximize)
        XCTAssertEqual(targetBadAction.partitionIndex, 0)

        // 2. Corner with >1 part reverts to corner default (max 1 part)
        let badCornerConfig = EdgeSnapZoneConfiguration(
            customPartitions: [.topLeft: [.topHalf, .bottomHalf]]
        )
        let targetBadCorner = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 50, y: 795),
                topology: topology,
                configuration: badCornerConfig
            )
        )
        XCTAssertEqual(targetBadCorner.zone, .topLeft)
        XCTAssertEqual(targetBadCorner.action, .topLeftQuarter)
        XCTAssertEqual(targetBadCorner.partitionIndex, 0)

        // 3. Straight edge with >4 parts reverts to default
        let badEdgeConfig = EdgeSnapZoneConfiguration(
            customPartitions: [.top: [.leftHalf, .rightHalf, .leftThird, .topHalf, .bottomHalf]]
        )
        let targetBadEdge = try XCTUnwrap(
            resolver.resolve(
                pointerLocation: CGPoint(x: 500, y: 795),
                topology: topology,
                configuration: badEdgeConfig
            )
        )
        XCTAssertEqual(targetBadEdge.action, .maximize)
        XCTAssertEqual(targetBadEdge.partitionIndex, 0)
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

    // MARK: - Finding 4 Regression: Sub-192 pt Geometries Keep Corner Bands <= Half Dimension

    func testFinding4_CornerBandsClampedToHalfDisplayDimension() {
        // Tiny display frame: 100 x 80
        // Width: 100 * 0.5 = 50 -> cornerWidth clamped to 50 (instead of 96)
        // Height: 80 * 0.5 = 40 -> cornerHeight clamped to 40 (instead of 80)
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerWidth(for: 100), 50)
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerHeight(for: 80), 40)

        // Standard display: 1512 x 982 -> 180 x 160
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerWidth(for: 1512), 180)
        XCTAssertEqual(EdgeSnapGeometryResolver.cornerHeight(for: 982), 160)
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
