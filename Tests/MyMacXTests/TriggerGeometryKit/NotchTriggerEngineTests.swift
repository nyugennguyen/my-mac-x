import CoreGraphics
import XCTest

@testable import MyMacX

final class NotchTriggerEngineTests: XCTestCase {
    func testResolvesValidatedNotchTriggerOnTheDisplayUnderThePointer() throws {
        let external = display(
            id: 2,
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            scale: 1,
            trigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: 870, y: 1_064, width: 180, height: 16)
            )
        )
        let builtIn = display(
            id: 1,
            frame: CGRect(x: 1_920, y: 124, width: 1_470, height: 956),
            scale: 2,
            trigger: NotchTrigger(
                classification: .notch,
                inferredNotchRegion: CGRect(x: 2_566, y: 1_048, width: 179, height: 32),
                region: CGRect(x: 2_534, y: 1_028, width: 243, height: 52)
            )
        )
        let topology = DisplayTopologySnapshot(
            displays: [external, builtIn],
            primaryDisplayID: external.id
        )

        let resolved = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 2_600, y: 1_050),
                topology: topology
            )
        )

        XCTAssertEqual(resolved.displayID, builtIn.id)
        XCTAssertEqual(resolved.trigger, builtIn.notchTrigger)
        XCTAssertTrue(resolved.pointerIsInsideTrigger)
    }

    func testTreatsThePhysicalTopEdgeAsPartOfTheTopCenterFallback() throws {
        let fallback = NotchTrigger(
            classification: .topCenterFallback,
            inferredNotchRegion: nil,
            region: CGRect(x: 870, y: 1_064, width: 180, height: 16)
        )
        let external = display(
            id: 2,
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            scale: 1,
            trigger: fallback
        )

        let resolved = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 960, y: 1_080),
                topology: DisplayTopologySnapshot(
                    displays: [external],
                    primaryDisplayID: external.id
                )
            )
        )

        XCTAssertEqual(resolved.trigger, fallback)
        XCTAssertTrue(resolved.pointerIsInsideTrigger)
    }

    func testReturnsCurrentDisplayGeometryBeforePointerEntersTheTrigger() throws {
        let fallback = NotchTrigger(
            classification: .topCenterFallback,
            inferredNotchRegion: nil,
            region: CGRect(x: 410, y: 784, width: 180, height: 16)
        )
        let display = display(
            id: 42,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            scale: 2,
            trigger: fallback
        )

        let resolved = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 500, y: 400),
                topology: DisplayTopologySnapshot(
                    displays: [display],
                    primaryDisplayID: display.id
                )
            )
        )

        XCTAssertEqual(
            resolved,
            NotchTriggerResolution(
                displayID: display.id,
                trigger: fallback,
                pointerIsInsideTrigger: false
            )
        )
    }

    func testUsesGlobalLogicalPointsAcrossNegativeOriginsAndMixedScaleDisplays() throws {
        let negative = display(
            id: 41,
            frame: CGRect(x: -1_600, y: -200, width: 1_200, height: 950),
            scale: 1.25,
            trigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: -1_090, y: 734, width: 180, height: 16)
            )
        )
        let retina = display(
            id: 42,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            scale: 2,
            trigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: 410, y: 784, width: 180, height: 16)
            )
        )
        let topology = DisplayTopologySnapshot(
            displays: [negative, retina],
            primaryDisplayID: retina.id
        )

        let negativeResolution = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: -1_000, y: 742),
                topology: topology
            )
        )
        let retinaResolution = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 500, y: 792),
                topology: topology
            )
        )

        XCTAssertEqual(negativeResolution.displayID, negative.id)
        XCTAssertTrue(negativeResolution.pointerIsInsideTrigger)
        XCTAssertEqual(retinaResolution.displayID, retina.id)
        XCTAssertTrue(retinaResolution.pointerIsInsideTrigger)
    }

    func testTriggerResolutionIsTranslationAndBackingScaleInvariant() throws {
        let xOrigins: [CGFloat] = [-3_840, -1_920, -700, 0, 2_048]
        let yOrigins: [CGFloat] = [-1_200, -300, 0, 640, 1_400]
        let scales: [CGFloat] = [1, 1.25, 2]
        var caseID: UInt32 = 100

        for x in xOrigins {
            for y in yOrigins {
                for scale in scales {
                    let trigger = NotchTrigger(
                        classification: .topCenterFallback,
                        inferredNotchRegion: nil,
                        region: CGRect(x: x + 870, y: y + 1_064, width: 180, height: 16)
                    )
                    let display = display(
                        id: caseID,
                        frame: CGRect(x: x, y: y, width: 1_920, height: 1_080),
                        scale: scale,
                        trigger: trigger
                    )
                    let topology = DisplayTopologySnapshot(
                        displays: [display],
                        primaryDisplayID: display.id
                    )

                    XCTAssertEqual(
                        NotchTriggerEngine().resolve(
                            pointerLocation: CGPoint(x: x + 960, y: y + 1_072),
                            topology: topology
                        ),
                        NotchTriggerResolution(
                            displayID: display.id,
                            trigger: trigger,
                            pointerIsInsideTrigger: true
                        ),
                        "origin=(\(x), \(y)), scale=\(scale)"
                    )
                    caseID += 1
                }
            }
        }
    }

    func testSharedDisplayEdgeUsesTheNeighborWhoseHalfOpenFrameContainsThePointer() throws {
        let left = display(
            id: 10,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            scale: 1,
            trigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: 410, y: 784, width: 180, height: 16)
            )
        )
        let right = display(
            id: 20,
            frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
            scale: 2,
            trigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: 1_410, y: 784, width: 180, height: 16)
            )
        )

        let resolved = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 1_000, y: 400),
                topology: DisplayTopologySnapshot(
                    displays: [left, right],
                    primaryDisplayID: left.id
                )
            )
        )

        XCTAssertEqual(resolved.displayID, right.id)
        XCTAssertFalse(resolved.pointerIsInsideTrigger)
    }

    func testReturnsNoGeometryForNonFiniteOrOffDisplayPointers() {
        let display = display(
            id: 2,
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            scale: 1,
            trigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: 870, y: 1_064, width: 180, height: 16)
            )
        )
        let topology = DisplayTopologySnapshot(
            displays: [display],
            primaryDisplayID: display.id
        )

        for location in [
            CGPoint(x: CGFloat.nan, y: 400),
            CGPoint(x: 400, y: CGFloat.infinity),
            CGPoint(x: -1, y: 400),
            CGPoint(x: 400, y: -1),
        ] {
            XCTAssertNil(
                NotchTriggerEngine().resolve(
                    pointerLocation: location,
                    topology: topology
                )
            )
        }
    }

    private func display(
        id: UInt32,
        frame: CGRect,
        scale: CGFloat,
        trigger: NotchTrigger
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: frame,
            backingScaleFactor: scale,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            ),
            notchTrigger: trigger
        )
    }
}
