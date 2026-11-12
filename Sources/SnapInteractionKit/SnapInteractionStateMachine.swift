/// One normalized input stream for the complete Snap interaction.
///
/// Composition preserves source ordering when forwarding Pointer Drag, Trigger Dwell, and
/// Layout Chooser events. The Module serializes concurrent callers before reducing them, so an
/// in-flight preview cannot be overtaken by mouse-up or cancellation.
enum EdgeSnapInteractionEvent: Equatable, Sendable {
    case zoneEntered(action: ActionID, displayID: DisplayID)
    case zoneExited
}

enum SnapInteractionEvent: Equatable, Sendable {
    case pointer(PointerDragEvent)
    case trigger(TriggerDwellEvent)
    case chooser(OverlayChooserEvent)
    case edge(EdgeSnapInteractionEvent)
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
            action: ActionID,
            isEdge: Bool
        )

        var binding: Binding? {
            switch self {
            case .idle:
                nil
            case .tracking(let binding),
                 .choosing(let binding, _),
                 .previewed(let binding, _, _, _):
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
            // Dwell deactivation mid-drag dismisses the chooser; it does NOT end the
            // interaction. Keep the binding so a later .trigger(.activated) can re-enter
            // .choosing and the pointer release still commits.
            switch state {
            case .previewed(let binding, let activeDisplayID, _, _):
                guard activeDisplayID == displayID else { return nil }
                return await cancelPreview(interaction: binding.interaction)
            case .choosing(let binding, let activeDisplayID):
                guard activeDisplayID == displayID else { return nil }
                // No preview was live: cross no Window Intent, per the actor contract.
                state = .tracking(binding)
                return nil
            case .idle, .tracking:
                return nil
            }

        case .chooser(.selectionChanged(let action)):
            return await preview(action)

        case .chooser(.confirmed(let action)):
            return await confirm(action)

        case .chooser(.cancelled):
            guard let interaction = state.interaction else { return nil }
            return await cancel(interaction)

        case .edge(.zoneEntered(let action, let displayID)):
            return await previewEdge(action: action, displayID: displayID)

        case .edge(.zoneExited):
            guard let interaction = state.interaction else { return nil }
            if case .previewed = state {
                return await cancelPreview(interaction: interaction)
            }
            return nil
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
             let .previewed(currentBinding, currentDisplayID, _, _):
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
            action: action,
            isEdge: false
        )
        return result
    }

    private func previewEdge(action: ActionID, displayID: DisplayID) async -> WindowActionResult? {
        let binding: Binding
        switch state {
        case .tracking(let currentBinding):
            binding = currentBinding
        case let .previewed(currentBinding, currentDisplayID, currentAction, _):
            if currentDisplayID == displayID && currentAction == action {
                return nil
            }
            binding = currentBinding
        case .idle, .choosing:
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
            state = .tracking(binding)
            _ = await windowActions.perform(
                .cancelPreview(interaction: binding.interaction)
            )
            return result
        }

        state = .previewed(
            binding,
            displayID: displayID,
            action: action,
            isEdge: true
        )
        return result
    }

    private func cancelPreview(interaction: InteractionID) async -> WindowActionResult? {
        guard let binding = state.binding, binding.interaction == interaction else { return nil }
        state = .tracking(binding)
        return await windowActions.perform(.cancelPreview(interaction: interaction))
    }

    private func release(_ interaction: InteractionID) async -> WindowActionResult? {
        guard state.interaction == interaction else { return nil }

        if case let .previewed(binding, _, _, isEdge) = state {
            state = .idle
            let policy: EdgeSnapAcceptancePolicy? = isEdge ? EdgeSnapAcceptancePolicy() : nil
            return await windowActions.perform(.commitPreview(interaction: interaction, acceptancePolicy: policy))
        }
        return await cancel(interaction)
    }

    private func confirm(_ action: ActionID) async -> WindowActionResult? {
        if case let .previewed(binding, _, previewedAction, _) = state,
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
