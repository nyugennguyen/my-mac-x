/// One normalized input stream for the complete Snap interaction.
///
/// Composition preserves source ordering when forwarding Pointer Drag, Trigger Dwell, and
/// Layout Chooser events. The Module serializes concurrent callers before reducing them, so an
/// in-flight preview cannot be overtaken by mouse-up or cancellation.
enum SnapInteractionEvent: Equatable, Sendable {
    case pointer(PointerDragEvent)
    case trigger(TriggerDwellEvent)
    case chooser(OverlayChooserEvent)
}

/// Owns the lifetime of one Window Action preview transaction.
///
/// This actor is the Snap Interaction Module's single Interface. Callers provide typed events and
/// receive the Window Action result only when an event crossed `WindowActionPerforming`. All
/// preview, commit, and cancellation intents retain the `InteractionID` captured by Pointer Drag.
actor SnapInteractionStateMachine {
    private struct Binding: Sendable {
        let interaction: InteractionID
        let capturedWindow: WindowIdentity
    }

    private struct PendingEvent {
        let event: SnapInteractionEvent
        let continuation: CheckedContinuation<WindowActionResult?, Never>
    }

    private enum State: Sendable {
        case idle
        case tracking(Binding)
        case choosing(Binding, displayID: DisplayID)
        case previewed(
            Binding,
            displayID: DisplayID,
            action: ActionID
        )

        var binding: Binding? {
            switch self {
            case .idle:
                nil
            case .tracking(let binding),
                 .choosing(let binding, _),
                 .previewed(let binding, _, _):
                binding
            }
        }

        var interaction: InteractionID? { binding?.interaction }
    }

    private let windowActions: any WindowActionPerforming
    private var state = State.idle
    private var pendingEvents: [PendingEvent] = []
    private var isDraining = false

    init(windowActions: any WindowActionPerforming) {
        self.windowActions = windowActions
    }

    func consume(_ event: SnapInteractionEvent) async -> WindowActionResult? {
        await withCheckedContinuation { continuation in
            pendingEvents.append(PendingEvent(event: event, continuation: continuation))
            guard !isDraining else { return }
            isDraining = true
            Task { await self.drainPendingEvents() }
        }
    }

    private func drainPendingEvents() async {
        while !pendingEvents.isEmpty {
            let pending = pendingEvents.removeFirst()
            let result = await reduce(pending.event)
            pending.continuation.resume(returning: result)
        }
        isDraining = false
    }

    private func reduce(_ event: SnapInteractionEvent) async -> WindowActionResult? {
        switch event {
        case .pointer(.began(let context)):
            return await begin(context)

        case .pointer(.moved(let context)):
            guard state.interaction == context.interaction else { return nil }
            return nil

        case .pointer(.released(let interaction)):
            return await release(interaction)

        case .pointer(.cancelled(let interaction)):
            return await cancel(interaction)

        case .trigger(.activated(let displayID)):
            guard case .tracking(let binding) = state else { return nil }
            state = .choosing(binding, displayID: displayID)
            return nil

        case .trigger(.deactivated(let displayID)):
            guard case .choosing(let binding, let activeDisplayID) = state,
                  activeDisplayID == displayID
            else {
                if case .previewed(
                    let binding,
                    let activeDisplayID,
                    _
                ) = state, activeDisplayID == displayID {
                    return await cancel(binding.interaction)
                }
                return nil
            }
            return await cancel(binding.interaction)

        case .chooser(.selectionChanged(let action)):
            return await preview(action)

        case .chooser(.confirmed(let action)):
            return await confirm(action)

        case .chooser(.cancelled):
            guard let interaction = state.interaction else { return nil }
            return await cancel(interaction)
        }
    }

    private func begin(_ context: PointerDragContext) async -> WindowActionResult? {
        let binding = Binding(
            interaction: context.interaction,
            capturedWindow: context.capturedWindow
        )
        guard let activeBinding = state.binding else {
            state = .tracking(binding)
            return nil
        }
        guard activeBinding.interaction != binding.interaction else { return nil }

        state = .idle
        let cancellation = await windowActions.perform(
            .cancelPreview(interaction: activeBinding.interaction)
        )
        state = .tracking(binding)
        return cancellation
    }

    private func preview(_ action: ActionID) async -> WindowActionResult? {
        let binding: Binding
        let displayID: DisplayID
        switch state {
        case let .choosing(currentBinding, currentDisplayID),
             let .previewed(currentBinding, currentDisplayID, _):
            binding = currentBinding
            displayID = currentDisplayID
        case .idle, .tracking:
            return nil
        }

        let result = await windowActions.perform(
            .preview(
                action: action,
                interaction: binding.interaction,
                capturedWindow: binding.capturedWindow,
                targetDisplay: displayID
            )
        )
        guard result.disposition == .succeeded,
              case .preview = result.effect
        else {
            state = .idle
            _ = await windowActions.perform(
                .cancelPreview(interaction: binding.interaction)
            )
            return result
        }

        state = .previewed(
            binding,
            displayID: displayID,
            action: action
        )
        return result
    }

    private func release(_ interaction: InteractionID) async -> WindowActionResult? {
        guard state.interaction == interaction else { return nil }

        if case .previewed = state {
            state = .idle
            return await windowActions.perform(.commitPreview(interaction: interaction))
        }
        return await cancel(interaction)
    }

    private func confirm(_ action: ActionID) async -> WindowActionResult? {
        if case let .previewed(binding, _, previewedAction) = state,
           previewedAction == action {
            return await release(binding.interaction)
        }

        guard let previewResult = await preview(action) else { return nil }
        guard previewResult.disposition == .succeeded,
              case .preview = previewResult.effect,
              let interaction = state.interaction
        else {
            return previewResult
        }
        return await release(interaction)
    }

    private func cancel(_ interaction: InteractionID) async -> WindowActionResult? {
        guard state.interaction == interaction else { return nil }
        state = .idle
        return await windowActions.perform(.cancelPreview(interaction: interaction))
    }
}
