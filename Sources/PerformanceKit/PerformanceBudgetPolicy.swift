import Dispatch
import Darwin
import Foundation

public struct PerformanceDuration: Equatable, Hashable, Comparable, Sendable {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public static func milliseconds(_ value: UInt64) -> Self {
        let result = value.multipliedReportingOverflow(by: 1_000_000)
        return Self(nanoseconds: result.overflow ? .max : result.partialValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

/// Monotonic time seam used only around explicitly selected work; it never starts polling.
public protocol PerformanceClock: Sendable {
    func nowNanoseconds() -> UInt64
}

public struct MonotonicPerformanceClock: PerformanceClock {
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

public struct PerformanceMeter: Sendable {
    private let clock: any PerformanceClock

    public init(clock: any PerformanceClock = MonotonicPerformanceClock()) {
        self.clock = clock
    }

    public func measure(_ operation: () throws -> Void) rethrows -> PerformanceDuration {
        let start = clock.nowNanoseconds()
        try operation()
        let end = clock.nowNanoseconds()
        return PerformanceDuration(nanoseconds: end >= start ? end - start : 0)
    }
}

public protocol PerformanceSystemSampling: Sendable {
    func residentMemoryBytes() -> UInt64
    func observerCount() -> Int
}

public struct ProcessPerformanceSystemSampler: PerformanceSystemSampling {
    private let observers: @Sendable () -> Int

    public init(observers: @escaping @Sendable () -> Int = { 0 }) {
        self.observers = observers
    }

    public func residentMemoryBytes() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return UInt64(max(0, usage.ru_maxrss))
    }

    public func observerCount() -> Int { max(0, observers()) }
}

/// Thread-safe production measurement harness. Runtime call sites record only typed timings and
/// counters; no window, input, application, or machine identity enters the observation.
public final class ProductionPerformanceInstrumentation: @unchecked Sendable {
    private struct State {
        var idleCPU: [Double] = []
        var eventStarts: [PerformanceDuration] = []
        var overlayCalculations: [PerformanceDuration] = []
        var actions = 0
        var displayChanges = 0
    }

    private let lock = NSLock()
    private let clock: any PerformanceClock
    private let system: any PerformanceSystemSampling
    private let memoryBefore: UInt64
    private let observersBefore: Int
    private var state = State()

    public init(
        clock: any PerformanceClock = MonotonicPerformanceClock(),
        system: any PerformanceSystemSampling = ProcessPerformanceSystemSampler()
    ) {
        self.clock = clock
        self.system = system
        memoryBefore = system.residentMemoryBytes()
        observersBefore = system.observerCount()
    }

    public func recordIdleCPU(percent: Double) {
        lock.withLock { state.idleCPU.append(percent) }
    }

    public func eventTimestamp() -> UInt64 { clock.nowNanoseconds() }

    public func recordEventToActionStart(eventReceivedAt: UInt64) {
        let now = clock.nowNanoseconds()
        lock.withLock {
            state.eventStarts.append(PerformanceDuration(nanoseconds: now >= eventReceivedAt ? now - eventReceivedAt : 0))
        }
    }

    @discardableResult
    public func measureOverlayPreviewCalculation(_ operation: () -> Void) -> PerformanceDuration {
        let duration = PerformanceMeter(clock: clock).measure(operation)
        lock.withLock { state.overlayCalculations.append(duration) }
        return duration
    }

    public func recordCompletedAction() { lock.withLock { state.actions += 1 } }
    public func recordDisplayChange() { lock.withLock { state.displayChanges += 1 } }

    public func observation() -> PerformanceObservation {
        let snapshot = lock.withLock { state }
        return PerformanceObservation(
            idleCPUPercent: snapshot.idleCPU,
            eventToActionStart: snapshot.eventStarts,
            overlayPreviewCalculation: snapshot.overlayCalculations,
            residentMemoryBytesBefore: memoryBefore,
            residentMemoryBytesAfter: system.residentMemoryBytes(),
            completedActions: snapshot.actions,
            completedDisplayChanges: snapshot.displayChanges,
            observerCountBefore: observersBefore,
            observerCountAfter: system.observerCount()
        )
    }
}

public enum PerformanceMetric: String, Codable, Equatable, Hashable, Sendable {
    case idleCPU
    case eventToActionStart
    case overlayPreviewCalculation
    case residentMemoryGrowth
    case observerGrowth
}

public enum PerformanceBudgetFailure: Equatable, Hashable, Sendable {
    case missing(PerformanceMetric)
    case invalid(PerformanceMetric)
    case exceeded(PerformanceMetric)
    case insufficientWorkload(
        requiredActions: Int,
        completedActions: Int,
        requiredDisplayChanges: Int,
        completedDisplayChanges: Int
    )
}

public struct PerformanceObservation: Equatable, Sendable {
    public let idleCPUPercent: [Double]
    public let eventToActionStart: [PerformanceDuration]
    public let overlayPreviewCalculation: [PerformanceDuration]
    public let residentMemoryBytesBefore: UInt64
    public let residentMemoryBytesAfter: UInt64
    public let completedActions: Int
    public let completedDisplayChanges: Int
    public let observerCountBefore: Int
    public let observerCountAfter: Int

    public init(
        idleCPUPercent: [Double],
        eventToActionStart: [PerformanceDuration],
        overlayPreviewCalculation: [PerformanceDuration],
        residentMemoryBytesBefore: UInt64,
        residentMemoryBytesAfter: UInt64,
        completedActions: Int,
        completedDisplayChanges: Int,
        observerCountBefore: Int,
        observerCountAfter: Int
    ) {
        self.idleCPUPercent = idleCPUPercent
        self.eventToActionStart = eventToActionStart
        self.overlayPreviewCalculation = overlayPreviewCalculation
        self.residentMemoryBytesBefore = residentMemoryBytesBefore
        self.residentMemoryBytesAfter = residentMemoryBytesAfter
        self.completedActions = completedActions
        self.completedDisplayChanges = completedDisplayChanges
        self.observerCountBefore = observerCountBefore
        self.observerCountAfter = observerCountAfter
    }
}

public struct PerformanceBudgetEvaluation: Equatable, Sendable {
    public let failures: [PerformanceBudgetFailure]

    public var isWithinBudget: Bool {
        failures.isEmpty
    }

    public init(failures: [PerformanceBudgetFailure]) {
        self.failures = failures
    }
}

/// Evaluates a complete performance workload in one call and reports every missed budget.
public struct PerformanceBudgetPolicy: Equatable, Sendable {
    public let maximumIdleCPUPercentP95: Double
    public let maximumEventToActionStartP95: PerformanceDuration
    public let maximumOverlayPreviewCalculationP95: PerformanceDuration
    public let maximumResidentMemoryGrowthBytes: UInt64
    public let requiredActionsForMemoryBudget: Int
    public let requiredDisplayChangesForObserverBudget: Int

    /// Operational public-beta thresholds for the project-plan targets.
    ///
    /// Idle CPU is capped at 1%. Event-to-action-start and pure preview calculation use the
    /// design's exclusive 100 ms and 8 ms targets. The 500-action/100-display-change soak
    /// permits at most 5 MiB resident-memory growth and no observer growth before investigation.
    public static let publicBeta = Self(
        maximumIdleCPUPercentP95: 1,
        maximumEventToActionStartP95: .milliseconds(100),
        maximumOverlayPreviewCalculationP95: .milliseconds(8),
        maximumResidentMemoryGrowthBytes: 5 * 1_024 * 1_024,
        requiredActionsForMemoryBudget: 500,
        requiredDisplayChangesForObserverBudget: 100
    )

    public init(
        maximumIdleCPUPercentP95: Double,
        maximumEventToActionStartP95: PerformanceDuration,
        maximumOverlayPreviewCalculationP95: PerformanceDuration,
        maximumResidentMemoryGrowthBytes: UInt64,
        requiredActionsForMemoryBudget: Int,
        requiredDisplayChangesForObserverBudget: Int
    ) {
        self.maximumIdleCPUPercentP95 = maximumIdleCPUPercentP95
        self.maximumEventToActionStartP95 = maximumEventToActionStartP95
        self.maximumOverlayPreviewCalculationP95 = maximumOverlayPreviewCalculationP95
        self.maximumResidentMemoryGrowthBytes = maximumResidentMemoryGrowthBytes
        self.requiredActionsForMemoryBudget = requiredActionsForMemoryBudget
        self.requiredDisplayChangesForObserverBudget = requiredDisplayChangesForObserverBudget
    }

    public func evaluate(_ observation: PerformanceObservation) -> PerformanceBudgetEvaluation {
        var failures: [PerformanceBudgetFailure] = []

        assessCPU(observation.idleCPUPercent, failures: &failures)
        assessDurations(
            observation.eventToActionStart,
            metric: .eventToActionStart,
            maximum: maximumEventToActionStartP95,
            maximumIsExclusive: true,
            failures: &failures
        )
        assessDurations(
            observation.overlayPreviewCalculation,
            metric: .overlayPreviewCalculation,
            maximum: maximumOverlayPreviewCalculationP95,
            maximumIsExclusive: true,
            failures: &failures
        )
        assessSoak(observation, failures: &failures)

        return PerformanceBudgetEvaluation(failures: failures)
    }

    private func assessCPU(
        _ samples: [Double],
        failures: inout [PerformanceBudgetFailure]
    ) {
        guard !samples.isEmpty else {
            failures.append(.missing(.idleCPU))
            return
        }
        guard samples.allSatisfy({ $0.isFinite && $0 >= 0 }),
              maximumIdleCPUPercentP95.isFinite,
              maximumIdleCPUPercentP95 >= 0
        else {
            failures.append(.invalid(.idleCPU))
            return
        }
        if percentile95(samples) > maximumIdleCPUPercentP95 {
            failures.append(.exceeded(.idleCPU))
        }
    }

    private func assessDurations(
        _ samples: [PerformanceDuration],
        metric: PerformanceMetric,
        maximum: PerformanceDuration,
        maximumIsExclusive: Bool,
        failures: inout [PerformanceBudgetFailure]
    ) {
        guard !samples.isEmpty else {
            failures.append(.missing(metric))
            return
        }
        let observed = percentile95(samples)
        if observed > maximum || (maximumIsExclusive && observed == maximum) {
            failures.append(.exceeded(metric))
        }
    }

    private func assessSoak(
        _ observation: PerformanceObservation,
        failures: inout [PerformanceBudgetFailure]
    ) {
        let memoryInputIsValid = requiredActionsForMemoryBudget > 0
            && observation.completedActions >= 0
        let observerInputIsValid = requiredDisplayChangesForObserverBudget > 0
            && observation.completedDisplayChanges >= 0
            && observation.observerCountBefore >= 0
            && observation.observerCountAfter >= 0

        if !memoryInputIsValid {
            failures.append(.invalid(.residentMemoryGrowth))
        }
        if !observerInputIsValid {
            failures.append(.invalid(.observerGrowth))
        }
        guard memoryInputIsValid, observerInputIsValid else {
            return
        }
        guard observation.completedActions >= requiredActionsForMemoryBudget,
              observation.completedDisplayChanges >= requiredDisplayChangesForObserverBudget
        else {
            failures.append(
                .insufficientWorkload(
                    requiredActions: requiredActionsForMemoryBudget,
                    completedActions: observation.completedActions,
                    requiredDisplayChanges: requiredDisplayChangesForObserverBudget,
                    completedDisplayChanges: observation.completedDisplayChanges
                )
            )
            return
        }

        let growth = observation.residentMemoryBytesAfter > observation.residentMemoryBytesBefore
            ? observation.residentMemoryBytesAfter - observation.residentMemoryBytesBefore
            : 0
        if growth > maximumResidentMemoryGrowthBytes {
            failures.append(.exceeded(.residentMemoryGrowth))
        }
        if observation.observerCountAfter > observation.observerCountBefore {
            failures.append(.exceeded(.observerGrowth))
        }
    }

    private func percentile95<Value: Comparable>(_ samples: [Value]) -> Value {
        let sorted = samples.sorted()
        let rank = Int(ceil(Double(sorted.count) * 0.95))
        return sorted[max(0, rank - 1)]
    }
}
