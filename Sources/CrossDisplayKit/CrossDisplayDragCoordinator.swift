import CoreGraphics

/// A Dwell transition bound to the topology generation from which its trigger presence came.
/// Raw Display identity is meaningful only inside this generation.
struct CrossDisplayTriggerEvent: Equatable, Sendable {
    let generation: DisplayTopologyGeneration
    let event: TriggerDwellEvent
}

/// One topology-scoped Overlay placement produced during a cross-Display Snap interaction.
///
/// Both surfaces belong to `displayID`. The Placement Preview is omitted when its Window Action
/// result belongs to another Display or falls materially outside this Display's usable area.
struct CrossDisplaySurfaceTarget: Equatable {
    let generation: DisplayTopologyGeneration
    let displayID: DisplayID
    let chooserFrame: CGRect
    let preview: OverlayPreviewPresentation?
}

enum CrossDisplayDismissReason: Equatable {
    case topologyUnavailable
    case topologyChanged
    case activeDisplayUnavailable
    case triggerDeactivated
    case invalidChooserSize
}

/// Atomic presentation work for the caller. A replacement always dismisses the complete old
/// chooser/preview pair before presenting the new target, preventing an orphaned surface.
enum CrossDisplaySurfaceTransition: Equatable {
    case unchanged
    case present(CrossDisplaySurfaceTarget)
    /// Updates only the Placement Preview while preserving the chooser already on this Display.
    case updatePreview(displayID: DisplayID, preview: OverlayPreviewPresentation?)
    case replace(
        dismissing: CrossDisplaySurfaceTarget,
        presenting: CrossDisplaySurfaceTarget
    )
    case dismiss(CrossDisplaySurfaceTarget, reason: CrossDisplayDismissReason)
}

/// Resolves Trigger Dwell and topology observations into safe cross-Display Overlay work.
///
/// TriggerDwellKit remains the sole owner of dwell and exit hysteresis. The current trigger
/// resolution is used only to distinguish a cross-Display handoff from an ordinary deactivation:
/// the old surface stays visible while the new Display completes dwell, then one replacement
/// dismisses the old chooser/preview pair and presents the new target atomically.
struct CrossDisplayDragCoordinator {
    private static let chooserGap: CGFloat = 12
    private static let logicalPointTolerance: CGFloat = 1

    private var activeTarget: CrossDisplaySurfaceTarget?
    private var pendingDisplayID: DisplayID?

    init() {}

    /// `resolution` must come from the supplied available topology capture. A nil `trigger`
    /// means TriggerDwellKit emitted no transition for this observation; it never means exit.
    mutating func update(
        trigger: CrossDisplayTriggerEvent?,
        resolution: NotchTriggerResolution?,
        topology: DisplayTopologyState,
        chooserSize: CGSize,
        preview: OverlayPreviewPresentation?
    ) -> CrossDisplaySurfaceTransition {
        guard Self.isValid(size: chooserSize) else {
            return dismissIfNeeded(reason: .invalidChooserSize)
        }
        guard case let .available(versionedTopology) = topology else {
            return dismissIfNeeded(reason: .topologyUnavailable)
        }

        let generation = versionedTopology.generation
        if let previous = activeTarget, previous.generation != generation {
            guard let trigger,
                  trigger.generation == generation,
                  case let .activated(displayID) = trigger.event
            else {
                return dismissIfNeeded(reason: .topologyChanged)
            }
            pendingDisplayID = nil
            return activate(
                displayID: displayID,
                in: versionedTopology,
                chooserSize: chooserSize,
                preview: preview
            )
        }

        if let trigger, trigger.generation != generation {
            return .unchanged
        }

        switch trigger?.event {
        case .activated(let displayID):
            pendingDisplayID = nil
            return activate(
                displayID: displayID,
                in: versionedTopology,
                chooserSize: chooserSize,
                preview: preview
            )

        case .deactivated(let displayID):
            guard let activeTarget, activeTarget.displayID == displayID else {
                return .unchanged
            }
            if let resolution,
               resolution.pointerIsInsideTrigger,
               resolution.displayID != displayID,
               versionedTopology.topology.displays.contains(where: {
                   $0.id == resolution.displayID
               }) {
                pendingDisplayID = resolution.displayID
                return .unchanged
            }
            pendingDisplayID = nil
            return dismissIfNeeded(reason: .triggerDeactivated)

        case nil:
            if let pendingDisplayID {
                guard let resolution,
                      resolution.pointerIsInsideTrigger,
                      resolution.displayID == pendingDisplayID
                else {
                    self.pendingDisplayID = nil
                    return dismissIfNeeded(reason: .triggerDeactivated)
                }
                return .unchanged
            }
            return refresh(
                in: versionedTopology,
                preview: preview
            )
        }
    }

    private mutating func activate(
        displayID: DisplayID,
        in topology: VersionedDisplayTopology,
        chooserSize: CGSize,
        preview: OverlayPreviewPresentation?
    ) -> CrossDisplaySurfaceTransition {
        guard let display = topology.topology.displays.first(where: { $0.id == displayID }) else {
            return dismissIfNeeded(reason: .activeDisplayUnavailable)
        }
        return transition(
            to: target(
                display: display,
                generation: topology.generation,
                chooserSize: chooserSize,
                preview: preview
            )
        )
    }

    private mutating func refresh(
        in topology: VersionedDisplayTopology,
        preview: OverlayPreviewPresentation?
    ) -> CrossDisplaySurfaceTransition {
        guard let activeTarget else { return .unchanged }
        guard let display = topology.topology.displays.first(where: {
            $0.id == activeTarget.displayID
        }) else {
            return dismissIfNeeded(reason: .activeDisplayUnavailable)
        }
        return transition(to: CrossDisplaySurfaceTarget(
            generation: topology.generation,
            displayID: display.id,
            chooserFrame: activeTarget.chooserFrame,
            preview: Self.safePreview(preview, on: display)
        ))
    }

    private func target(
        display: DisplaySnapshot,
        generation: DisplayTopologyGeneration,
        chooserSize: CGSize,
        preview: OverlayPreviewPresentation?
    ) -> CrossDisplaySurfaceTarget {
        CrossDisplaySurfaceTarget(
            generation: generation,
            displayID: display.id,
            chooserFrame: Self.chooserFrame(
                size: chooserSize,
                trigger: display.notchTrigger.region,
                visibleFrame: display.visibleFrame
            ),
            preview: Self.safePreview(preview, on: display)
        )
    }

    private mutating func transition(
        to target: CrossDisplaySurfaceTarget
    ) -> CrossDisplaySurfaceTransition {
        guard let previous = activeTarget else {
            activeTarget = target
            return .present(target)
        }
        guard previous != target else {
            return .unchanged
        }
        if previous.generation == target.generation,
           previous.displayID == target.displayID,
           previous.chooserFrame == target.chooserFrame {
            activeTarget = target
            return .updatePreview(displayID: target.displayID, preview: target.preview)
        }

        activeTarget = target
        return .replace(dismissing: previous, presenting: target)
    }

    private mutating func dismissIfNeeded(
        reason: CrossDisplayDismissReason
    ) -> CrossDisplaySurfaceTransition {
        pendingDisplayID = nil
        guard let previous = activeTarget else { return .unchanged }
        activeTarget = nil
        return .dismiss(previous, reason: reason)
    }

    private static func chooserFrame(
        size: CGSize,
        trigger: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let fittedSize = CGSize(
            width: min(size.width, visibleFrame.width),
            height: min(size.height, visibleFrame.height)
        )
        let proposed = CGRect(
            x: trigger.midX - fittedSize.width / 2,
            y: trigger.minY - chooserGap - fittedSize.height,
            width: fittedSize.width,
            height: fittedSize.height
        )
        return CGRect(
            x: min(
                max(proposed.minX, visibleFrame.minX),
                visibleFrame.maxX - fittedSize.width
            ),
            y: min(
                max(proposed.minY, visibleFrame.minY),
                visibleFrame.maxY - fittedSize.height
            ),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private static func safePreview(
        _ preview: OverlayPreviewPresentation?,
        on display: DisplaySnapshot
    ) -> OverlayPreviewPresentation? {
        guard let preview,
              preview.displayID == display.id,
              isValid(frame: preview.targetFrame),
              contains(
                  preview.targetFrame,
                  inside: display.visibleFrame,
                  tolerance: logicalPointTolerance
              )
        else {
            return nil
        }
        return preview
    }

    private static func contains(
        _ candidate: CGRect,
        inside container: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        candidate.minX >= container.minX - tolerance
            && candidate.minY >= container.minY - tolerance
            && candidate.maxX <= container.maxX + tolerance
            && candidate.maxY <= container.maxY + tolerance
    }

    private static func isValid(size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
    }

    private static func isValid(frame: CGRect) -> Bool {
        frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
            && frame.maxX.isFinite
            && frame.maxY.isFinite
    }
}
