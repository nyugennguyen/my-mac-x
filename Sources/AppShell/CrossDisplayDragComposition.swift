import AppKit
import CoreGraphics
import Foundation

enum SnappingRuntimeTrigger: Equatable, Sendable {
    case notch
    case topCenter
}

struct SnappingRuntimeSettings: Equatable, Sendable {
    var isEnabled: Bool
    var trigger: SnappingRuntimeTrigger
    var dwellMilliseconds: UInt32
    var showsPlacementPreview: Bool
    var usesReducedEffects: Bool

    static let defaults = SnappingRuntimeSettings(
        isEnabled: true,
        trigger: .notch,
        dwellMilliseconds: 150,
        showsPlacementPreview: true,
        usesReducedEffects: false
    )
}

/// Hot-reload Settings seam. Composition reads one coherent snapshot per pointer event.
@MainActor
protocol SnappingRuntimeSettingsProviding: AnyObject {
    func currentSnappingSettings() -> SnappingRuntimeSettings
}

/// Production Adapter backed by the application's canonical Settings runtime.
@MainActor
final class ProductionSnappingRuntimeSettingsAdapter: SnappingRuntimeSettingsProviding {
    private let load: @MainActor () -> SnappingRuntimeSettings

    init(load: @escaping @MainActor () -> SnappingRuntimeSettings) {
        self.load = load
    }

    func currentSnappingSettings() -> SnappingRuntimeSettings { load() }
}

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
    private let snappingSettings: any SnappingRuntimeSettingsProviding
    private let performance: ProductionPerformanceInstrumentation
    private let previewPlanner = PlacementPreviewPlanner()

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
        actionRegistry: ActionRegistry = .builtIn,
        windowActions: WindowActionEngine = WindowActionEngine(),
        snappingSettings: any SnappingRuntimeSettingsProviding =
            ProductionSnappingRuntimeSettingsAdapter(load: { .defaults }),
        performance: ProductionPerformanceInstrumentation = ProductionPerformanceInstrumentation()
    ) {
        self.overlay = overlay
        self.dwellEngine = triggerEngine
        self.actionRegistry = actionRegistry
        self.snappingSettings = snappingSettings
        self.performance = performance

        self.windowActions = windowActions
        self.stateMachine = SnapInteractionStateMachine(windowActions: windowActions)
        self.pointerMonitor = pointerMonitor ?? PointerDragMonitor.system()

        // Wire chooser events from overlay → state machine
        overlay.onEvent = { [weak self] event in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                switch event {
                case .selectionChanged(let action):
                    let result = await self.stateMachine.consume(.chooser(.selectionChanged(action: action)))
                    self.presentPreview(from: result)
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
        performance.recordDisplayChange()
        currentTopology = topology
        if case .available(let versioned) = topology {
            currentTopologySnapshot = versioned.topology
        } else {
            currentTopologySnapshot = nil
        }
    }

    // MARK: - Pointer drag → notch trigger → dwell

    private func startPointerMonitor() {
        let pointerMonitor = pointerMonitor
        pointerTask = Task { [weak self, pointerMonitor] in
            let status = await pointerMonitor.start()
            print("[NotchSnap] PointerDragMonitor.start() → \(status)")
            guard status == .active else { return }
            let events = pointerMonitor.events
            for await event in events {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.handlePointerEvent(event)
            }
        }
    }

    private func handlePointerEvent(_ event: PointerDragEvent) async {
        let settings = snappingSettings.currentSnappingSettings()
        applyPresentationPolicy(settings)
        if let configuration = try? TriggerDwellConfiguration(
            dwellDuration: .milliseconds(settings.dwellMilliseconds)
        ) {
            await dwellEngine.updateConfiguration(configuration)
        }

        guard settings.isEnabled else {
            if isDragging {
                isDragging = false
                await dwellEngine.update(.outside)
                overlay.dismiss()
                let interaction: InteractionID?
                switch event {
                case .began(let context), .moved(let context):
                    interaction = context.interaction
                case .released(let value), .cancelled(let value):
                    interaction = value
                }
                if let interaction {
                    _ = await stateMachine.consume(
                        .pointer(.cancelled(interaction: interaction))
                    )
                }
            }
            return
        }
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
                    // Every Display exposes one resolved Notch Trigger. On hardware
                    // without a notch, ScreenKit intentionally resolves that same
                    // domain concept to the top-center fallback. Do not discard the
                    // fallback when the persisted preference is `.notch`.
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
            overlay.dismiss()

        case .cancelled(let interaction):
            isDragging = false
            await dwellEngine.update(.outside)
            _ = await stateMachine.consume(.pointer(.cancelled(interaction: interaction)))
            overlay.dismiss()
        }
    }

    private func applyPresentationPolicy(_ settings: SnappingRuntimeSettings) {
        let workspace = NSWorkspace.shared
        overlay.updateAccessibilityPreferences(.init(
            reduceMotion: settings.usesReducedEffects || workspace.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: settings.usesReducedEffects || workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        ))
    }

    private func presentPreview(from result: WindowActionResult?) {
        guard snappingSettings.currentSnappingSettings().showsPlacementPreview,
              let result,
              case let .success(presentation) = previewPlanner.presentation(from: result)
        else { return }
        _ = overlay.showPreview(presentation)
    }

    // MARK: - Dwell events → overlay

    private func observeDwellEvents() {
        let dwellEvents = dwellEngine.events
        stateTask = Task { [weak self, dwellEvents] in
            for await event in dwellEvents {
                guard !Task.isCancelled else { break }
                guard let self else { break }
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

            var choices: [OverlayLayoutChoice] = []
            _ = performance.measureOverlayPreviewCalculation {
                choices = actionRegistry.actions
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
            }

            // Align flush below the notch trigger so dragging from notch into chooser is seamless
            let chooserFrame = CGRect(
                x: display.notchTrigger.region.midX - chooserSize.width / 2,
                y: display.notchTrigger.region.minY - chooserSize.height,
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
