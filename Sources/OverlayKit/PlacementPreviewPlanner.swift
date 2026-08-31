import CoreGraphics

/// Typed reasons a Window Action result cannot drive a Placement Preview safely.
enum PlacementPreviewFailure: Error, Equatable, Sendable {
    case previewUnavailable(WindowActionResult.Disposition)
    case unexpectedPreviewEffect
    case invalidDisplayIdentity
    case invalidPreviewFrame
    case commitUnavailable(WindowActionResult.Disposition)
    case unexpectedCommittedEffect
    case invalidCommittedFrame
    case frameMismatch(maximumDelta: CGFloat)
}

/// Observable comparison between the presented frame and verified final read-back.
struct PlacementPreviewVerification: Equatable, Sendable {
    let maximumFrameDelta: CGFloat
    let previewWasConstrained: Bool
    let committedWasConstrained: Bool
}

/// Pure translation from Window Action output into Overlay-owned presentation data.
///
/// WindowActionKit remains the sole owner of Layout calculation. This Module preserves the
/// exact preview frame and constraint state returned through `WindowActionPerforming`.
struct PlacementPreviewPlanner: Sendable {
    private static let verificationTolerance: CGFloat = 1

    init() {}

    func presentation(
        from result: WindowActionResult
    ) -> Result<OverlayPreviewPresentation, PlacementPreviewFailure> {
        guard result.disposition == .succeeded else {
            return .failure(.previewUnavailable(result.disposition))
        }
        guard case let .preview(frame, rawDisplayID, constrained) = result.effect else {
            return .failure(.unexpectedPreviewEffect)
        }
        guard rawDisplayID != 0 else {
            return .failure(.invalidDisplayIdentity)
        }
        guard Self.isValid(frame) else {
            return .failure(.invalidPreviewFrame)
        }

        return .success(OverlayPreviewPresentation(
            displayID: DisplayID(rawValue: rawDisplayID),
            targetFrame: frame,
            isConstrainedByMinimumSize: constrained
        ))
    }

    /// Compares against `committed(actualFrame:)`, which is WindowActionKit's verified
    /// Accessibility read-back rather than a locally calculated target.
    func verify(
        _ presentation: OverlayPreviewPresentation,
        against result: WindowActionResult
    ) -> Result<PlacementPreviewVerification, PlacementPreviewFailure> {
        guard Self.isValid(presentation.targetFrame) else {
            return .failure(.invalidPreviewFrame)
        }
        guard result.disposition == .succeeded else {
            return .failure(.commitUnavailable(result.disposition))
        }
        guard case let .committed(actualFrame, committedConstrained) = result.effect else {
            return .failure(.unexpectedCommittedEffect)
        }
        guard Self.isValid(actualFrame) else {
            return .failure(.invalidCommittedFrame)
        }

        let previewFrame = presentation.targetFrame
        let maximumDelta = [
            abs(previewFrame.minX - actualFrame.minX),
            abs(previewFrame.minY - actualFrame.minY),
            abs(previewFrame.width - actualFrame.width),
            abs(previewFrame.height - actualFrame.height),
        ].max()!
        guard maximumDelta <= Self.verificationTolerance else {
            return .failure(.frameMismatch(maximumDelta: maximumDelta))
        }

        return .success(PlacementPreviewVerification(
            maximumFrameDelta: maximumDelta,
            previewWasConstrained: presentation.isConstrainedByMinimumSize,
            committedWasConstrained: committedConstrained
        ))
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.size.width > 0
            && frame.size.height > 0
            && frame.maxX.isFinite
            && frame.maxY.isFinite
    }
}
