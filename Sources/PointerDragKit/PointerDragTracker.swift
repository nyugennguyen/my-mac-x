import CoreGraphics

/// Normalized, privacy-safe input for one pointer interaction.
///
/// Platform Adapters enqueue these values after observing the corresponding CoreGraphics or
/// Accessibility event. Raw event payloads and Accessibility objects never cross this Interface.
enum PointerDragSignal: Sendable {
    case leftButtonPressed(
        interaction: InteractionID,
        capturedWindow: WindowIdentity,
        location: CGPoint
    )
    case pointerMoved(location: CGPoint)
    case leftButtonDragged(location: CGPoint)
    case leftButtonReleased(location: CGPoint)
    case capturedWindowMoved(WindowIdentity)
    case cancelled
}

/// The information downstream trigger and Window Action callers need after a real drag begins.
///
/// The same `InteractionID` and Captured Window identity must be used for every preview and the
/// eventual preview commit or cancellation. The identity is opaque and only crosses into
/// `WindowActionPerforming`; callers still cannot use it for direct Accessibility work.
struct PointerDragContext: Equatable, Sendable {
    let interaction: InteractionID
    let capturedWindow: WindowIdentity
    let pointerLocation: CGPoint
}

enum PointerDragEvent: Equatable, Sendable {
    case began(PointerDragContext)
    case moved(PointerDragContext)
    case released(interaction: InteractionID)
    case cancelled(interaction: InteractionID)
}

/// Correlates pointer and Accessibility movement without polling or doing I/O.
///
/// This actor is the Pointer Drag Module's single Interface. A left-button interaction binds one
/// opaque Captured Window identity. The Module emits `began` exactly once, and only after it has
/// observed both a left-button drag and an AX moved signal for that same identity. Focus changes
/// and movement from any other window cannot retarget an armed interaction.
actor PointerDragTracker {
    private struct Candidate: Sendable {
        let interaction: InteractionID
        let capturedWindow: WindowIdentity
        var pointerLocation: CGPoint
        var observedLeftButtonDrag = false
        var observedCapturedWindowMove = false
    }

    private enum State: Sendable {
        case idle
        case armed(Candidate)
        case dragging(PointerDragContext)
    }

    private var state: State = .idle

    func consume(_ signal: PointerDragSignal) -> PointerDragEvent? {
        switch signal {
        case let .leftButtonPressed(interaction, capturedWindow, location):
            state = .armed(
                Candidate(
                    interaction: interaction,
                    capturedWindow: capturedWindow,
                    pointerLocation: location
                )
            )
            return nil

        case .pointerMoved:
            return nil

        case .leftButtonDragged(let location):
            switch state {
            case .armed(var candidate):
                candidate.pointerLocation = location
                candidate.observedLeftButtonDrag = true
                return advance(candidate)
            case .dragging(let context):
                let updated = PointerDragContext(
                    interaction: context.interaction,
                    capturedWindow: context.capturedWindow,
                    pointerLocation: location
                )
                state = .dragging(updated)
                return .moved(updated)
            case .idle:
                return nil
            }

        case .leftButtonReleased:
            guard case .dragging(let context) = state else {
                state = .idle
                return nil
            }
            state = .idle
            return .released(interaction: context.interaction)

        case .capturedWindowMoved(let window):
            guard case .armed(var candidate) = state,
                  candidate.capturedWindow == window
            else { return nil }
            candidate.observedCapturedWindowMove = true
            return advance(candidate)

        case .cancelled:
            let event: PointerDragEvent?
            if case .dragging(let context) = state {
                event = .cancelled(interaction: context.interaction)
            } else {
                event = nil
            }
            state = .idle
            return event
        }
    }

    private func advance(_ candidate: Candidate) -> PointerDragEvent? {
        guard candidate.observedLeftButtonDrag,
              candidate.observedCapturedWindowMove
        else {
            state = .armed(candidate)
            return nil
        }

        let context = PointerDragContext(
            interaction: candidate.interaction,
            capturedWindow: candidate.capturedWindow,
            pointerLocation: candidate.pointerLocation
        )
        state = .dragging(context)
        return .began(context)
    }
}
