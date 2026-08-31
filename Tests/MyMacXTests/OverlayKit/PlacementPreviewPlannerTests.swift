import CoreGraphics
import XCTest

@testable import MyMacX

final class PlacementPreviewPlannerTests: XCTestCase {
    func testBuildsPresentationFromExactSuccessfulPreviewEffect() throws {
        let frame = CGRect(x: -1_440, y: 25, width: 720, height: 875)
        let result = WindowActionResult(
            disposition: .succeeded,
            effect: .preview(frame: frame, displayID: 7, constrained: true),
            undoToken: nil,
            warnings: []
        )

        let presentation = try PlacementPreviewPlanner()
            .presentation(from: result)
            .get()

        XCTAssertEqual(
            presentation,
            OverlayPreviewPresentation(
                displayID: DisplayID(rawValue: 7),
                targetFrame: frame,
                isConstrainedByMinimumSize: true
            )
        )
    }

    func testVerifiesFinalReadBackWithinOneLogicalPointOfThePreview() throws {
        let presentation = OverlayPreviewPresentation(
            displayID: DisplayID(rawValue: 7),
            targetFrame: CGRect(x: -1_440, y: 25, width: 720, height: 875),
            isConstrainedByMinimumSize: true
        )
        let committed = WindowActionResult(
            disposition: .succeeded,
            effect: .committed(
                actualFrame: CGRect(x: -1_439, y: 24.5, width: 719.25, height: 876),
                constrained: true
            ),
            undoToken: nil,
            warnings: [.constrainedByApplication]
        )

        let verification = try PlacementPreviewPlanner()
            .verify(presentation, against: committed)
            .get()

        XCTAssertEqual(
            verification,
            PlacementPreviewVerification(
                maximumFrameDelta: 1,
                previewWasConstrained: true,
                committedWasConstrained: true
            )
        )
    }

    func testReportsConstraintStateAddedByVerifiedApplicationReadBack() throws {
        let frame = CGRect(x: 100, y: 100, width: 640, height: 480)
        let presentation = OverlayPreviewPresentation(
            displayID: DisplayID(rawValue: 9),
            targetFrame: frame,
            isConstrainedByMinimumSize: false
        )
        let committed = WindowActionResult(
            disposition: .succeeded,
            effect: .committed(actualFrame: frame, constrained: true),
            undoToken: nil,
            warnings: [.constrainedByApplication]
        )

        let verification = try PlacementPreviewPlanner()
            .verify(presentation, against: committed)
            .get()

        XCTAssertEqual(
            verification,
            PlacementPreviewVerification(
                maximumFrameDelta: 0,
                previewWasConstrained: false,
                committedWasConstrained: true
            )
        )
    }

    func testRejectsFinalReadBackBeyondOneLogicalPoint() {
        let presentation = OverlayPreviewPresentation(
            displayID: DisplayID(rawValue: 7),
            targetFrame: CGRect(x: -1_440, y: 25, width: 720, height: 875),
            isConstrainedByMinimumSize: false
        )
        let committed = WindowActionResult(
            disposition: .succeeded,
            effect: .committed(
                actualFrame: CGRect(x: -1_438.999, y: 25, width: 720, height: 875),
                constrained: false
            ),
            undoToken: nil,
            warnings: []
        )

        guard case let .failure(.frameMismatch(maximumDelta)) =
            PlacementPreviewPlanner().verify(presentation, against: committed)
        else {
            return XCTFail("Expected an over-tolerance frame mismatch")
        }
        XCTAssertEqual(maximumDelta, 1.001, accuracy: 0.000_000_001)
    }

    func testRejectsUnavailableOrNonPreviewWindowActionResults() {
        let frame = CGRect(x: 0, y: 0, width: 720, height: 450)
        let planner = PlacementPreviewPlanner()
        let unavailable = WindowActionResult(
            disposition: .superseded,
            effect: .none,
            undoToken: nil,
            warnings: []
        )
        let wrongEffect = WindowActionResult(
            disposition: .succeeded,
            effect: .committed(actualFrame: frame, constrained: false),
            undoToken: nil,
            warnings: []
        )

        XCTAssertEqual(
            planner.presentation(from: unavailable),
            .failure(.previewUnavailable(.superseded))
        )
        XCTAssertEqual(
            planner.presentation(from: wrongEffect),
            .failure(.unexpectedPreviewEffect)
        )
    }

    func testRejectsInvalidPreviewDisplayIdentityAndFrames() {
        let planner = PlacementPreviewPlanner()
        let validFrame = CGRect(x: 0, y: 0, width: 720, height: 450)
        let nullDisplay = WindowActionResult(
            disposition: .succeeded,
            effect: .preview(frame: validFrame, displayID: 0, constrained: false),
            undoToken: nil,
            warnings: []
        )

        XCTAssertEqual(
            planner.presentation(from: nullDisplay),
            .failure(.invalidDisplayIdentity)
        )

        for frame in [
            CGRect(x: CGFloat.nan, y: 0, width: 720, height: 450),
            CGRect(x: 0, y: 0, width: 0, height: 450),
            CGRect(x: 0, y: 0, width: 720, height: CGFloat.infinity),
        ] {
            XCTAssertEqual(
                planner.presentation(from: WindowActionResult(
                    disposition: .succeeded,
                    effect: .preview(frame: frame, displayID: 7, constrained: false),
                    undoToken: nil,
                    warnings: []
                )),
                .failure(.invalidPreviewFrame)
            )
        }
    }

    func testRejectsUnavailableNonCommittedAndInvalidFinalResults() {
        let planner = PlacementPreviewPlanner()
        let presentation = OverlayPreviewPresentation(
            displayID: DisplayID(rawValue: 7),
            targetFrame: CGRect(x: 0, y: 0, width: 720, height: 450),
            isConstrainedByMinimumSize: false
        )
        let unavailable = WindowActionResult(
            disposition: .cancelled,
            effect: .none,
            undoToken: nil,
            warnings: []
        )
        let wrongEffect = WindowActionResult(
            disposition: .succeeded,
            effect: .preview(
                frame: presentation.targetFrame,
                displayID: 7,
                constrained: false
            ),
            undoToken: nil,
            warnings: []
        )
        let invalidFrame = WindowActionResult(
            disposition: .succeeded,
            effect: .committed(
                actualFrame: CGRect(x: 0, y: 0, width: -1, height: 450),
                constrained: false
            ),
            undoToken: nil,
            warnings: []
        )

        XCTAssertEqual(
            planner.verify(presentation, against: unavailable),
            .failure(.commitUnavailable(.cancelled))
        )
        XCTAssertEqual(
            planner.verify(presentation, against: wrongEffect),
            .failure(.unexpectedCommittedEffect)
        )
        XCTAssertEqual(
            planner.verify(presentation, against: invalidFrame),
            .failure(.invalidCommittedFrame)
        )
    }
}
