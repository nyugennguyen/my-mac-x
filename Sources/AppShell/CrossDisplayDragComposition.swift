import CoreGraphics
import Foundation

/// Wires the complete Notch Snap pipeline: pointer drag → notch trigger → dwell →
/// cross-Display coordinator → overlay presentation → chooser selection → preview/commit.
///
/// This composition owns no Accessibility, frame calculation, or Window Action commit logic.
/// It connects the existing Modules into a working runtime pipeline.
@MainActor
final class CrossDisplayDragComposition {
    private static let notchSnapActions: Set<ActionID> = [
        .maximize,
        .leftHalf,
        .rightHalf,
        .topHalf,
        .bottomHalf,
        .topLeftQuarter,
        .topRightQuarter,
        .bottomLeftQuarter,
        .bottomRightQuarter,
    ]

    private let overlay: OverlayCoordinator
    private let stateMachine: SnapInteractionStateMachine
    private let windowActions: WindowActionEngine
    private let pointerMonitor: PointerDragMonitor
    private let notchEngine = NotchTriggerEngine()
    private let dwellEngine: TriggerDwellEngine
    private let actionRegistry: ActionRegistry

    private var coordinator = CrossDisplayDragCoordinator()
    private let chooserSize = CGSize(width: 360, height: 220)
    private var currentTopology: DisplayTopologyState = .unavailable(
        generation: .init(rawValue: 0),
        failure: .systemUnavailable
    )
    private var currentTopologySnapshot: DisplayTopologySnapshot?
    private var isDragging = false

    private var topologyTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var pointerTask: Task<Void, Never>?

    init(
        overlay: OverlayCoordinator,
        topologyObserving: any DisplayTopologyObserving,
        triggerEngine: TriggerDwellEngine,
        pointerMonitor: PointerDragMonitor? = nil,
        actionRegistry: ActionRegistry = .builtIn
    ) {
        self.overlay = overlay
        self.dwellEngine = triggerEngine
        self.actionRegistry = actionRegistry

        let engine = WindowActionEngine()
        self.windowActions = engine
        self.stateMachine = SnapInteractionStateMachine(windowActions: engine)
        self.pointerMonitor = pointerMonitor ?? PointerDragMonitor.system()

        // Wire chooser events from overlay → state machine
        overlay.onEvent = { [weak self] event in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                switch event {
                case .selectionChanged(let action):
                    _ = await self.stateMachine.consume(.chooser(.selectionChanged(action: action)))
                case .confirmed(let action):
                    _ = await self.stateMachine.consume(.chooser(.confirmed(action: action)))
                case .cancelled:
                    _ = await self.stateMachine.consume(.chooser(.cancelled))
                }
            }
        }

        observeTopology(topologyObserving)
        observeDwellEvents()
        startPointerMonitor()
    }

    deinit {
        topologyTask?.cancel()
        stateTask?.cancel()
        pointerTask?.cancel()
    }

    // MARK: - Topology

    private func observeTopology(_ observing: any DisplayTopologyObserving) {
        topologyTask = Task { [weak self] in
            let stream = await observing.updates()
            for await topology in stream {
                guard !Task.isCancelled else { break }
                self?.applyTopology(topology)
            }
        }
    }

    private func applyTopology(_ topology: DisplayTopologyState) {
        currentTopology = topology
        if case .available(let versioned) = topology {
            currentTopologySnapshot = versioned.topology
        } else {
            currentTopologySnapshot = nil
        }
    }

    // MARK: - Pointer drag → notch trigger → dwell

    private func startPointerMonitor() {
        pointerTask = Task { [weak self] in
            guard let self else { return }
            let status = await self.pointerMonitor.start()
            print("[NotchSnap] PointerDragMonitor.start() → \(status)")
            guard status == .active else { return }
            let events = self.pointerMonitor.events
            for await event in events {
                guard !Task.isCancelled else { break }
                await self.handlePointerEvent(event)
            }
        }
    }

    private func handlePointerEvent(_ event: PointerDragEvent) async {
        switch event {
        case .began(let context):
            print("[NotchSnap] drag → began")
            isDragging = true
            _ = await stateMachine.consume(.pointer(.began(context)))

        case .moved(let context):
            _ = await stateMachine.consume(.pointer(.moved(context)))
            if case let .insideChooser(displayID, _) = overlay.trackPointer(
                at: context.pointerLocation
            ) {
                await dwellEngine.update(.inside(displayID))
                return
            }
            // Resolve notch trigger and feed presence to dwell engine
            if isDragging, let snapshot = currentTopologySnapshot {
                if let resolution = notchEngine.resolve(
                    pointerLocation: context.pointerLocation,
                    topology: snapshot
                ) {
                    let presence: TriggerDwellPresence = resolution.pointerIsInsideTrigger
                        ? .inside(resolution.displayID)
                        : .outside
                    await dwellEngine.update(presence)
                }
            }

        case .released(let interaction):
            isDragging = false
            await dwellEngine.update(.outside)
            _ = await stateMachine.consume(.pointer(.released(interaction: interaction)))

        case .cancelled(let interaction):
            isDragging = false
            await dwellEngine.update(.outside)
            _ = await stateMachine.consume(.pointer(.cancelled(interaction: interaction)))
        }
    }

    // MARK: - Dwell events → overlay

    private func observeDwellEvents() {
        stateTask = Task { [weak self] in
            guard let self else { return }
            let dwellEvents = self.dwellEngine.events
            for await event in dwellEvents {
                guard !Task.isCancelled else { break }
                _ = await self.stateMachine.consume(.trigger(event))
                await self.handleTriggerEvent(event)
            }
        }
    }

    private func handleTriggerEvent(_ event: TriggerDwellEvent) async {
        switch event {
        case .activated(let displayID):
            print("[NotchSnap] dwell → activated")
            // Show the layout chooser with real choices
            guard case .available(let versioned) = currentTopology,
                  let display = versioned.topology.displays.first(where: { $0.id == displayID })
            else { return }

            let choices = actionRegistry.actions
                .filter {
                    $0.availability == .available
                        && Self.notchSnapActions.contains($0.id)
                }
                .map { descriptor in
                    OverlayLayoutChoice(
                        action: descriptor.id,
                        title: descriptor.title,
                        accessibilityLabel: descriptor.title
                    )
                }

            let chooserFrame = CGRect(
                x: display.notchTrigger.region.midX - chooserSize.width / 2,
                y: display.notchTrigger.region.minY - 12 - chooserSize.height,
                width: chooserSize.width,
                height: chooserSize.height
            )

            let presentation = OverlayChooserPresentation(
                displayID: displayID,
                panelFrame: chooserFrame,
                choices: choices,
                columnCount: 3,
                initialSelection: choices.first?.action
            )
            let result = overlay.presentChooser(presentation)
            print("[NotchSnap] chooser → \(result)")

        case .deactivated:
            overlay.dismiss()
        }
    }
}
