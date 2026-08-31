import Foundation

/// A monotonic-clock seam used by the Trigger Dwell Module.
///
/// Production uses `ContinuousTriggerDwellClock`; tests advance an in-memory Adapter. An Adapter
/// must not return from `sleep(until:)` before the requested monotonic deadline.
protocol TriggerDwellClock: Sendable {
    func now() async -> Duration
    func sleep(until deadline: Duration) async throws
}

struct ContinuousTriggerDwellClock: TriggerDwellClock {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    func now() -> Duration {
        origin.duration(to: clock.now)
    }

    func sleep(until deadline: Duration) async throws {
        let remaining = deadline - now()
        guard remaining > .zero else { return }
        try await clock.sleep(for: remaining)
    }
}

enum TriggerDwellConfigurationError: Error, Equatable, Sendable {
    case dwellDurationOutsideSupportedRange
}

/// Interaction timing accepted by the Notch Trigger flow.
///
/// Product scope deliberately bounds dwell to 120...180 ms. Settings code can reject invalid
/// values before constructing this Module instead of silently changing user intent.
struct TriggerDwellConfiguration: Equatable, Sendable {
    static let minimumDwellDuration = Duration.milliseconds(120)
    static let maximumDwellDuration = Duration.milliseconds(180)
    /// Short exit grace that absorbs boundary jitter without leaving an old chooser visible.
    static let exitHysteresisDuration = Duration.milliseconds(80)

    let dwellDuration: Duration

    init(dwellDuration: Duration) throws {
        guard dwellDuration >= Self.minimumDwellDuration,
              dwellDuration <= Self.maximumDwellDuration
        else {
            throw TriggerDwellConfigurationError.dwellDurationOutsideSupportedRange
        }
        self.dwellDuration = dwellDuration
    }
}

/// A topology-scoped observation derived from `NotchTriggerResolution`.
///
/// The caller maps a resolution inside its trigger to `inside(displayID)` and every other
/// resolution to `outside`. No pointer coordinates or geometry need to cross this Interface.
enum TriggerDwellPresence: Equatable, Sendable {
    case inside(DisplayID)
    case outside
}

enum TriggerDwellEvent: Equatable, Sendable {
    case activated(DisplayID)
    case deactivated(DisplayID)
}

/// Turns noisy Notch Trigger presence samples into stable activation events.
///
/// Repeated samples for the same Display are structurally debounced: they do not restart the
/// first-entry dwell deadline and cannot emit duplicate activation events.
actor TriggerDwellEngine {
    let events: AsyncStream<TriggerDwellEvent>

    private enum State: Sendable {
        case idle
        case dwelling(displayID: DisplayID)
        case active(displayID: DisplayID)
        case leaving(displayID: DisplayID)
    }

    private let configuration: TriggerDwellConfiguration
    private let clock: any TriggerDwellClock
    private let continuation: AsyncStream<TriggerDwellEvent>.Continuation

    private var state = State.idle
    private var timerTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        configuration: TriggerDwellConfiguration,
        clock: any TriggerDwellClock = ContinuousTriggerDwellClock()
    ) {
        let channel = AsyncStream.makeStream(
            of: TriggerDwellEvent.self,
            // Activation is dwell-bounded and repeated samples are structurally debounced.
            // Preserve every transition so a slow consumer cannot miss the deactivation that
            // dismisses a Layout Chooser.
            bufferingPolicy: .unbounded
        )
        events = channel.stream
        continuation = channel.continuation
        self.configuration = configuration
        self.clock = clock
    }

    deinit {
        timerTask?.cancel()
        continuation.finish()
    }

    func update(_ presence: TriggerDwellPresence) async {
        switch presence {
        case .outside:
            switch state {
            case .idle, .leaving:
                return
            case .dwelling:
                cancelTimer()
                state = .idle
            case .active(let displayID):
                await beginExitHysteresis(for: displayID)
            }

        case .inside(let displayID):
            switch state {
            case .idle:
                await beginDwell(for: displayID)

            case .dwelling(let currentDisplayID):
                guard currentDisplayID != displayID else { return }
                await beginDwell(for: displayID)

            case .active(let currentDisplayID):
                guard currentDisplayID != displayID else { return }
                continuation.yield(.deactivated(currentDisplayID))
                await beginDwell(for: displayID)

            case .leaving(let currentDisplayID):
                cancelTimer()
                if currentDisplayID == displayID {
                    state = .active(displayID: displayID)
                } else {
                    continuation.yield(.deactivated(currentDisplayID))
                    await beginDwell(for: displayID)
                }
            }
        }
    }

    private func beginDwell(for displayID: DisplayID) async {
        cancelTimer()
        state = .dwelling(displayID: displayID)
        generation &+= 1
        let activeGeneration = generation
        let deadline = await clock.now() + configuration.dwellDuration
        let clock = self.clock

        timerTask = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.dwellCompleted(
                for: displayID,
                generation: activeGeneration
            )
        }
    }

    private func beginExitHysteresis(for displayID: DisplayID) async {
        cancelTimer()
        state = .leaving(displayID: displayID)
        generation &+= 1
        let activeGeneration = generation
        let deadline = await clock.now() + TriggerDwellConfiguration.exitHysteresisDuration
        let clock = self.clock

        timerTask = Task { [weak self] in
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.exitHysteresisCompleted(
                for: displayID,
                generation: activeGeneration
            )
        }
    }

    private func dwellCompleted(
        for displayID: DisplayID,
        generation completedGeneration: UInt64
    ) {
        guard completedGeneration == generation,
              case .dwelling(let currentDisplayID) = state,
              currentDisplayID == displayID
        else {
            return
        }

        timerTask = nil
        state = .active(displayID: displayID)
        continuation.yield(.activated(displayID))
    }

    private func exitHysteresisCompleted(
        for displayID: DisplayID,
        generation completedGeneration: UInt64
    ) {
        guard completedGeneration == generation,
              case .leaving(let currentDisplayID) = state,
              currentDisplayID == displayID
        else {
            return
        }

        timerTask = nil
        state = .idle
        continuation.yield(.deactivated(displayID))
    }

    private func cancelTimer() {
        generation &+= 1
        timerTask?.cancel()
        timerTask = nil
    }
}
