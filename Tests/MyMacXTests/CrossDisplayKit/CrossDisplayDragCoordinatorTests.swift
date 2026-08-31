import CoreGraphics
import XCTest

@testable import MyMacX

final class CrossDisplayDragCoordinatorTests: XCTestCase {
    func testCrossDisplayDwellHandoffKeepsTheOldSurfaceUntilItCanReplaceAtomically() {
        var coordinator = CrossDisplayDragCoordinator()
        let topology = mixedScaleTopology(generation: 1)
        let externalPreview = preview(
            displayID: 11,
            frame: CGRect(x: -1_600, y: -180, width: 800, height: 900)
        )

        let first = coordinator.update(
            trigger: triggerEvent(generation: 1, .activated(DisplayID(rawValue: 11))),
            resolution: resolution(displayID: 11),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: externalPreview
        )
        let oldDeactivated = coordinator.update(
            trigger: triggerEvent(generation: 1, .deactivated(DisplayID(rawValue: 11))),
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: externalPreview
        )
        let newActivated = coordinator.update(
            trigger: triggerEvent(generation: 1, .activated(DisplayID(rawValue: 22))),
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: externalPreview
        )

        guard case let .present(externalTarget) = first else {
            return XCTFail("Expected the first Display to present")
        }
        XCTAssertEqual(oldDeactivated, .unchanged)
        guard case let .replace(dismissing, presenting) = newActivated else {
            return XCTFail("Expected one atomic cross-Display replacement")
        }
        XCTAssertEqual(externalTarget.displayID, DisplayID(rawValue: 11))
        XCTAssertEqual(externalTarget.preview, externalPreview)
        XCTAssertEqual(dismissing, externalTarget)
        XCTAssertEqual(presenting.displayID, DisplayID(rawValue: 22))
        XCTAssertNil(presenting.preview, "A preview belonging to the old Display must not move")
        assertContains(
            presenting.chooserFrame,
            inside: CGRect(x: 0, y: 25, width: 1_000, height: 775)
        )
    }

    func testSameDisplayPreviewUpdateDoesNotRecreateTheChooser() {
        var coordinator = CrossDisplayDragCoordinator()
        let topology = mixedScaleTopology(generation: 1)

        let first = coordinator.update(
            trigger: triggerEvent(generation: 1, .activated(DisplayID(rawValue: 22))),
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )
        let targetPreview = preview(
            displayID: 22,
            frame: CGRect(x: 0, y: 25, width: 500, height: 775)
        )
        let second = coordinator.update(
            trigger: nil,
            resolution: nil,
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: targetPreview
        )

        guard case let .present(chooserOnly) = first,
              case let .updatePreview(displayID, preview) = second
        else {
            return XCTFail("Expected the preview to update without recreating the chooser")
        }
        XCTAssertNil(chooserOnly.preview)
        XCTAssertEqual(displayID, DisplayID(rawValue: 22))
        XCTAssertEqual(preview, targetPreview)
    }

    func testSharedBoundaryResolutionPresentsTheHalfOpenFrameOwner() throws {
        var coordinator = CrossDisplayDragCoordinator()
        let left = display(
            id: 31,
            frame: CGRect(x: -1_000, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: -1_000, y: 25, width: 1_000, height: 775),
            scale: 1,
            trigger: CGRect(x: -90, y: 784, width: 90, height: 16)
        )
        let right = display(
            id: 32,
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 25, width: 1_000, height: 775),
            scale: 2,
            trigger: CGRect(x: 0, y: 784, width: 90, height: 16)
        )
        let topology = available(generation: 4, displays: [left, right], primary: right.id)
        let topologySnapshot = try XCTUnwrap(topology.snapshot)
        let boundaryResolution = try XCTUnwrap(
            NotchTriggerEngine().resolve(
                pointerLocation: CGPoint(x: 0, y: 792),
                topology: topologySnapshot
            )
        )

        let transition = coordinator.update(
            trigger: triggerEvent(generation: 4, .activated(boundaryResolution.displayID)),
            resolution: boundaryResolution,
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        guard case let .present(target) = transition else {
            return XCTFail("Expected a presentation at the shared edge")
        }
        XCTAssertEqual(target.displayID, right.id)
    }

    func testTopologyGenerationChangeDismissesUntilAFreshScopedActivationArrives() {
        var coordinator = CrossDisplayDragCoordinator()
        let oldDisplay = display(
            id: 41,
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1_200, height: 875),
            scale: 2,
            trigger: CGRect(x: 510, y: 884, width: 180, height: 16)
        )
        let reorderedDisplay = display(
            id: 41,
            frame: CGRect(x: -1_200, y: -300, width: 1_200, height: 900),
            visibleFrame: CGRect(x: -1_200, y: -275, width: 1_200, height: 875),
            scale: 2,
            trigger: CGRect(x: -690, y: 584, width: 180, height: 16)
        )
        let oldTopology = available(generation: 7, displays: [oldDisplay], primary: oldDisplay.id)
        let newTopology = available(
            generation: 8,
            displays: [reorderedDisplay],
            primary: reorderedDisplay.id
        )

        let first = coordinator.update(
            trigger: triggerEvent(generation: 7, .activated(oldDisplay.id)),
            resolution: resolution(displayID: 41),
            topology: oldTopology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )
        let topologyChanged = coordinator.update(
            trigger: nil,
            resolution: resolution(displayID: 41),
            topology: newTopology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )
        let freshActivation = coordinator.update(
            trigger: triggerEvent(generation: 8, .activated(reorderedDisplay.id)),
            resolution: resolution(displayID: 41),
            topology: newTopology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        guard case let .present(oldTarget) = first,
              case let .dismiss(dismissed, reason) = topologyChanged,
              case let .present(newTarget) = freshActivation
        else {
            return XCTFail("Expected invalidation, dismissal, then fresh presentation")
        }
        XCTAssertEqual(dismissed, oldTarget)
        XCTAssertEqual(reason, .topologyChanged)
        XCTAssertEqual(oldTarget.generation, DisplayTopologyGeneration(rawValue: 7))
        XCTAssertEqual(newTarget.generation, DisplayTopologyGeneration(rawValue: 8))
        XCTAssertNotEqual(oldTarget.chooserFrame, newTarget.chooserFrame)
    }

    func testDisplayDetachAndUnavailableTopologyDismissTheActiveSurface() {
        var detachedCoordinator = CrossDisplayDragCoordinator()
        let topology = mixedScaleTopology(generation: 10)
        let first = detachedCoordinator.update(
            trigger: triggerEvent(generation: 10, .activated(DisplayID(rawValue: 11))),
            resolution: resolution(displayID: 11),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )
        let detached = detachedCoordinator.update(
            trigger: nil,
            resolution: nil,
            topology: available(
                generation: 11,
                displays: [builtInDisplay()],
                primary: DisplayID(rawValue: 22)
            ),
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        guard case let .present(target) = first,
              case let .dismiss(dismissed, reason) = detached
        else {
            return XCTFail("Expected the detached Display surface to be dismissed")
        }
        XCTAssertEqual(dismissed, target)
        XCTAssertEqual(reason, .topologyChanged)

        var unavailableCoordinator = CrossDisplayDragCoordinator()
        _ = unavailableCoordinator.update(
            trigger: triggerEvent(generation: 10, .activated(DisplayID(rawValue: 22))),
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )
        let unavailable = unavailableCoordinator.update(
            trigger: nil,
            resolution: nil,
            topology: .unavailable(
                generation: DisplayTopologyGeneration(rawValue: 11),
                failure: .systemUnavailable
            ),
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )
        guard case let .dismiss(_, reason) = unavailable else {
            return XCTFail("Expected unavailable geometry to dismiss")
        }
        XCTAssertEqual(reason, .topologyUnavailable)
    }

    func testOrdinaryDwellDeactivationDismissesInsteadOfBypassingHysteresis() {
        var coordinator = CrossDisplayDragCoordinator()
        let topology = mixedScaleTopology(generation: 12)
        let first = coordinator.update(
            trigger: triggerEvent(generation: 12, .activated(DisplayID(rawValue: 22))),
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )
        let noDwellEventYet = coordinator.update(
            trigger: nil,
            resolution: nil,
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )
        let deactivated = coordinator.update(
            trigger: triggerEvent(generation: 12, .deactivated(DisplayID(rawValue: 22))),
            resolution: nil,
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: nil
        )

        guard case let .present(target) = first,
              case let .dismiss(dismissed, reason) = deactivated
        else {
            return XCTFail("Expected dismissal only after the Dwell Module emitted deactivation")
        }
        XCTAssertEqual(noDwellEventYet, .unchanged)
        XCTAssertEqual(dismissed, target)
        XCTAssertEqual(reason, .triggerDeactivated)
    }

    func testOversizedChooserIsFittedAndOffScreenPreviewIsNotPresented() {
        var coordinator = CrossDisplayDragCoordinator()
        let display = display(
            id: 51,
            frame: CGRect(x: -500, y: -200, width: 320, height: 240),
            visibleFrame: CGRect(x: -500, y: -180, width: 320, height: 220),
            scale: 1.25,
            trigger: CGRect(x: -390, y: 24, width: 100, height: 16)
        )
        let topology = available(generation: 20, displays: [display], primary: display.id)
        let offScreenPreview = preview(
            displayID: 51,
            frame: CGRect(x: -700, y: -300, width: 400, height: 300)
        )

        let transition = coordinator.update(
            trigger: triggerEvent(generation: 20, .activated(display.id)),
            resolution: resolution(displayID: 51),
            topology: topology,
            chooserSize: CGSize(width: 640, height: 480),
            preview: offScreenPreview
        )

        guard case let .present(target) = transition else {
            return XCTFail("Expected a safe chooser presentation")
        }
        XCTAssertEqual(target.chooserFrame, display.visibleFrame)
        XCTAssertNil(target.preview)
    }

    func testEquivalentObservationDoesNotRecreateTheSurface() {
        var coordinator = CrossDisplayDragCoordinator()
        let topology = mixedScaleTopology(generation: 30)
        let targetPreview = preview(
            displayID: 22,
            frame: CGRect(x: 500, y: 25, width: 500, height: 775)
        )

        _ = coordinator.update(
            trigger: triggerEvent(generation: 30, .activated(DisplayID(rawValue: 22))),
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: targetPreview
        )
        let repeated = coordinator.update(
            trigger: nil,
            resolution: resolution(displayID: 22),
            topology: topology,
            chooserSize: CGSize(width: 360, height: 220),
            preview: targetPreview
        )

        XCTAssertEqual(repeated, .unchanged)
    }
}

private extension DisplayTopologyState {
    var snapshot: DisplayTopologySnapshot? {
        guard case let .available(versioned) = self else { return nil }
        return versioned.topology
    }
}

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

private func assertContains(
    _ candidate: CGRect,
    inside container: CGRect,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(candidate.minX, container.minX, file: file, line: line)
    XCTAssertGreaterThanOrEqual(candidate.minY, container.minY, file: file, line: line)
    XCTAssertLessThanOrEqual(candidate.maxX, container.maxX, file: file, line: line)
    XCTAssertLessThanOrEqual(candidate.maxY, container.maxY, file: file, line: line)
}
