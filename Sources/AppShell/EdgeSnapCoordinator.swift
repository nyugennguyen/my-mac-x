import AppKit
import CoreGraphics
import Foundation

/// Presentation model for Edge Snap Placement Previews.
public struct PlacementPreviewPresentation: Equatable, Sendable {
    public let displayID: DisplayID
    public let targetFrame: CGRect
    public let isConstrainedByMinimumSize: Bool

    public init(displayID: DisplayID, targetFrame: CGRect, isConstrainedByMinimumSize: Bool = false) {
        self.displayID = displayID
        self.targetFrame = targetFrame
        self.isConstrainedByMinimumSize = isConstrainedByMinimumSize
    }
}

/// Token returned when an Edge Snap preview is shown.
public struct OverlayPreviewToken: Equatable, Sendable {
    public let displayID: DisplayID

    public init(displayID: DisplayID) {
        self.displayID = displayID
    }
}

/// Protocol for presenting Edge Snap Placement Previews.
@MainActor
public protocol EdgeSnapOverlayPresenting: AnyObject, Sendable {
    @discardableResult
    func showPreview(_ presentation: PlacementPreviewPresentation) -> OverlayPreviewToken
    func dismiss()
}

/// Conformance allowing OverlayCoordinator to present Edge Snap previews.
@MainActor
extension OverlayCoordinator: EdgeSnapOverlayPresenting {
    @discardableResult
    public func showPreview(_ presentation: PlacementPreviewPresentation) -> OverlayPreviewToken {
        let internalPresentation = OverlayPreviewPresentation(
            displayID: presentation.displayID,
            targetFrame: presentation.targetFrame,
            isConstrainedByMinimumSize: presentation.isConstrainedByMinimumSize
        )
        _ = showPreview(internalPresentation)
        return OverlayPreviewToken(displayID: presentation.displayID)
    }
}

/// Thread-safe box holding the current monotonic generation identifier.
private final class GenerationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func set(_ newValue: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Coordinates live Edge Snap pointer drags, window-server sampling, geometry resolution,
/// seam gating, coexistence stand-down, and preview/commit transactions.
@MainActor
final class EdgeSnapCoordinator: Sendable {
    private let pointerEvents: any PointerEventAdapting
    private let overlayPresenter: any EdgeSnapOverlayPresenting
    private let stateMachine: SnapInteractionStateMachine
    private let windowSampler: any WindowServerWindowSampling
    private let targetResolver: EdgeSnapTargetResolver
    private let topologyProvider: (@MainActor @Sendable () -> DisplayTopologySnapshot?)?
    private let systemTilingStateProvider: @MainActor @Sendable () -> SystemTilingState?
    private let zoneConfigurationProvider: @MainActor @Sendable () -> EdgeSnapZoneConfiguration
    private let isEnabledProvider: @MainActor @Sendable () -> Bool

    private let classifier = WindowDragClassifier()
    private let seamGator = DisplaySeamGator()
    private let coexistenceDetector = SystemTilingCoexistenceDetector()
    private let geometryResolver = EdgeSnapGeometryResolver()

    private let generationBox = GenerationBox()
    private var pointerTask: Task<Void, Never>?
    private var topologyTask: Task<Void, Never>?
    private var currentTopologySnapshot: DisplayTopologySnapshot?
    private var generationCounter: UInt64 = 0
    private var activeRun: ActiveRun?

    var hasActiveRun: Bool {
        activeRun != nil
    }

    private struct ActiveRun {
        let interaction: InteractionID
        let generation: UInt64
        let startLocation: CGPoint
        var currentLocation: CGPoint
        var filter: WindowDragFilter
        var trail: PointerTrail
        var isConfirmedMoving: Bool
        var isCancelled: Bool
        var target: ResolvedEdgeSnapCandidate?
        var targetResolutionTask: Task<Result<ResolvedEdgeSnapCandidate, TargetResolutionFailure>, Never>?
        var currentZone: EdgeSnapZone?
        var lastSampleTimestampNanoseconds: UInt64
        var lastSampledWindowBounds: CGRect?
        var initialWindowBounds: CGRect?
        var windowID: CGWindowID?
        var cachedSystemTilingState: SystemTilingState?
    }

    init(
        pointerEvents: any PointerEventAdapting = MacOSPointerEventAdapter(),
        overlayPresenter: any EdgeSnapOverlayPresenting,
        stateMachine: SnapInteractionStateMachine,
        windowSampler: any WindowServerWindowSampling = MacOSWindowServerSampler(),
        targetResolver: EdgeSnapTargetResolver,
        topologyProvider: (@MainActor @Sendable () -> DisplayTopologySnapshot?)? = nil,
        topologyObserving: (any DisplayTopologyObserving)? = nil,
        systemTilingStateProvider: (@MainActor @Sendable () -> SystemTilingState?)? = nil,
        zoneConfigurationProvider: (@MainActor @Sendable () -> EdgeSnapZoneConfiguration)? = nil,
        isEnabledProvider: (@MainActor @Sendable () -> Bool)? = nil
    ) {
        self.pointerEvents = pointerEvents
        self.overlayPresenter = overlayPresenter
        self.stateMachine = stateMachine
        self.windowSampler = windowSampler
        self.targetResolver = targetResolver
        self.topologyProvider = topologyProvider
        self.systemTilingStateProvider = systemTilingStateProvider ?? {
            SystemTilingPreferenceReader().readState()
        }
        self.zoneConfigurationProvider = zoneConfigurationProvider ?? {
            EdgeSnapZoneConfiguration()
        }
        self.isEnabledProvider = isEnabledProvider ?? { true }

        if let topologyObserving {
            self.topologyTask = Task { [weak self] in
                let stream = await topologyObserving.updates()
                for await state in stream {
                    guard !Task.isCancelled else { break }
                    if case let .available(versioned) = state {
                        self?.currentTopologySnapshot = versioned.topology
                    } else {
                        self?.currentTopologySnapshot = nil
                    }
                }
            }
        }
    }

    deinit {
        pointerTask?.cancel()
        topologyTask?.cancel()
    }

    func start() async {
        let startResult = await pointerEvents.start()
        guard case .active(let stream) = startResult else { return }

        pointerTask = Task { [weak self] in
            for await signal in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.consumeSignal(signal)
            }
        }
    }

    func stop() async {
        pointerTask?.cancel()
        pointerTask = nil
        await pointerEvents.stop()
        if let run = activeRun {
            activeRun = nil
            overlayPresenter.dismiss()
            _ = await stateMachine.consume(.pointer(.cancelled(interaction: run.interaction)))
        }
    }

    func consumeSignal(_ signal: PointerPlatformSignal) async {
        guard isEnabledProvider() else {
            if let run = activeRun {
                activeRun = nil
                overlayPresenter.dismiss()
                _ = await stateMachine.consume(.pointer(.cancelled(interaction: run.interaction)))
            }
            return
        }

        switch signal {
        case .leftButtonPressed(let location, let timestamp):
            await handleButtonPressed(at: location, timestamp: timestamp)

        case .leftButtonDragged(let location, let timestamp):
            await handleButtonDragged(at: location, timestamp: timestamp)

        case .leftButtonReleased(let location, let timestamp):
            await handleButtonReleased(at: location, timestamp: timestamp)

        case .interrupted:
            await handleInterrupted()
        }
    }

    // MARK: - Private Signal Handlers

    private func handleButtonPressed(at location: CGPoint, timestamp: UInt64) async {
        guard isEnabledProvider() else { return }
        generationCounter &+= 1
        let generation = generationCounter
        generationBox.set(generation)

        var trail = PointerTrail()
        trail.append(point: location, timestampNano: timestamp)

        let resolver = targetResolver
        let box = generationBox
        let task = Task { () -> Result<ResolvedEdgeSnapCandidate, TargetResolutionFailure> in
            await resolver.resolveTarget(
                at: location,
                generation: generation,
                activeGeneration: { box.get() }
            )
        }

        activeRun = ActiveRun(
            interaction: InteractionID(),
            generation: generation,
            startLocation: location,
            currentLocation: location,
            filter: WindowDragFilter(),
            trail: trail,
            isConfirmedMoving: false,
            isCancelled: false,
            target: nil,
            targetResolutionTask: task,
            currentZone: nil,
            lastSampleTimestampNanoseconds: timestamp,
            lastSampledWindowBounds: nil,
            initialWindowBounds: nil,
            windowID: nil
        )
    }

    private func handleButtonDragged(at location: CGPoint, timestamp: UInt64) async {
        guard var run = activeRun, !run.isCancelled else { return }

        run.trail.append(point: location, timestampNano: timestamp)
        run.currentLocation = location

        if run.target == nil, let task = run.targetResolutionTask {
            let resolution = await task.value
            guard activeRun?.generation == run.generation else { return }
            switch resolution {
            case .success(let target):
                run.target = target
                run.windowID = target.windowID
                run.initialWindowBounds = target.initialFrame
                run.lastSampledWindowBounds = target.initialFrame
            case .failure:
                run.isCancelled = true
                activeRun = run
                return
            }
        }

        guard let target = run.target,
              let initialFrame = run.initialWindowBounds,
              let windowID = run.windowID
        else {
            activeRun = run
            return
        }

        let timeDeltaNs = timestamp >= run.lastSampleTimestampNanoseconds
            ? (timestamp - run.lastSampleTimestampNanoseconds)
            : 0

        let currentBounds: CGRect
        if run.lastSampledWindowBounds == nil || timeDeltaNs >= 15_000_000 {
            if let sampled = await windowSampler.windowBounds(windowID: windowID) {
                currentBounds = sampled
                run.lastSampledWindowBounds = sampled
                run.lastSampleTimestampNanoseconds = timestamp
            } else {
                currentBounds = run.lastSampledWindowBounds ?? initialFrame
            }
        } else {
            currentBounds = run.lastSampledWindowBounds ?? initialFrame
        }
        guard activeRun?.generation == run.generation else { return }

        let pointerDelta = CGVector(
            dx: location.x - run.startLocation.x,
            dy: location.y - run.startLocation.y
        )
        let classification = classifier.classify(
            pressPoint: run.startLocation,
            initialFrame: initialFrame,
            currentFrame: currentBounds,
            pointerDelta: pointerDelta
        )

        let dragState = run.filter.update(with: classification)
        if dragState == .cancelled || run.filter.isCancelled {
            run.isCancelled = true
            if run.currentZone != nil {
                run.currentZone = nil
                overlayPresenter.dismiss()
                _ = await stateMachine.consume(.edge(.zoneExited))
                guard activeRun?.generation == run.generation else { return }
            }
            activeRun = run
            return
        }

        if !run.isConfirmedMoving && (dragState == .moving || run.filter.isConfirmedMoving) {
            run.isConfirmedMoving = true
            let context = PointerDragContext(
                interaction: run.interaction,
                capturedWindow: target.windowIdentity,
                pointerLocation: location
            )
            _ = await stateMachine.consume(.pointer(.began(context)))
            guard activeRun?.generation == run.generation else { return }
        }

        guard run.isConfirmedMoving else {
            guard activeRun?.generation == run.generation else { return }
            activeRun = run
            return
        }

        guard let topology = topologyProvider?() ?? currentTopologySnapshot else {
            guard activeRun?.generation == run.generation else { return }
            activeRun = run
            return
        }

        let zoneConfig = zoneConfigurationProvider()
        let resolvedSnapTarget = geometryResolver.resolve(
            pointerLocation: location,
            topology: topology,
            configuration: zoneConfig
        )

        if let snapTarget = resolvedSnapTarget {
            let systemState = run.cachedSystemTilingState ?? (systemTilingStateProvider() ?? SystemTilingPreferenceReader().readState())
            run.cachedSystemTilingState = systemState
            guard let display = topology.displays.first(where: { $0.id == snapTarget.displayID }) else {
                guard activeRun?.generation == run.generation else { return }
                activeRun = run
                return
            }

            let gating = seamGator.evaluate(
                zone: snapTarget.zone,
                on: display,
                in: topology,
                trail: run.trail,
                evaluationTime: timestamp > 0 ? (TimeInterval(timestamp) / 1_000_000_000.0) : nil
            )

            let isSharedSeam: Bool
            switch gating.boundary {
            case .sharedSeam:
                isSharedSeam = true
            case .outerWall:
                isSharedSeam = false
            }

            let stoodDown = coexistenceDetector.standsDown(
                for: snapTarget.zone,
                isSharedSeam: isSharedSeam,
                state: systemState
            )

            if stoodDown {
                if run.currentZone != nil {
                    run.currentZone = nil
                    overlayPresenter.dismiss()
                    _ = await stateMachine.consume(.edge(.zoneExited))
                    guard activeRun?.generation == run.generation else { return }
                }
                activeRun = run
                return
            }

            if !gating.isAllowed {
                if run.currentZone != nil {
                    run.currentZone = nil
                    overlayPresenter.dismiss()
                    _ = await stateMachine.consume(.edge(.zoneExited))
                    guard activeRun?.generation == run.generation else { return }
                }
                activeRun = run
                return
            }

            if run.currentZone != snapTarget.zone {
                run.currentZone = snapTarget.zone
                let actionResult = await stateMachine.consume(
                    .edge(.zoneEntered(action: snapTarget.action, displayID: snapTarget.displayID))
                )
                guard activeRun?.generation == run.generation else { return }
                if let actionResult, actionResult.disposition == .succeeded,
                   case let .preview(frame, rawDisplayID, constrained) = actionResult.effect {
                    let presentation = PlacementPreviewPresentation(
                        displayID: DisplayID(rawValue: rawDisplayID),
                        targetFrame: frame,
                        isConstrainedByMinimumSize: constrained
                    )
                    overlayPresenter.showPreview(presentation)
                }
            }
        } else {
            if run.currentZone != nil {
                run.currentZone = nil
                overlayPresenter.dismiss()
                _ = await stateMachine.consume(.edge(.zoneExited))
                guard activeRun?.generation == run.generation else { return }
            }
        }

        guard activeRun?.generation == run.generation else { return }
        activeRun = run
    }

    private func handleButtonReleased(at location: CGPoint, timestamp: UInt64) async {
        guard let run = activeRun else { return }
        activeRun = nil
        overlayPresenter.dismiss()

        if run.isConfirmedMoving && !run.isCancelled && !run.filter.isCancelled && run.currentZone != nil {
            _ = await stateMachine.consume(.pointer(.released(interaction: run.interaction)))
        } else {
            _ = await stateMachine.consume(.pointer(.cancelled(interaction: run.interaction)))
        }
    }

    private func handleInterrupted() async {
        guard let run = activeRun else { return }
        activeRun = nil
        overlayPresenter.dismiss()
        _ = await stateMachine.consume(.pointer(.cancelled(interaction: run.interaction)))
    }
}
