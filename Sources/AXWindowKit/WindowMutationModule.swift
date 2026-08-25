import CoreGraphics
import Foundation

/// The internal Window Mutation Interface. Both frames use Accessibility's global,
/// top-left logical-point coordinate space. The allowed frame is the caller's current
/// placement bound and is required before a stable application clamp can succeed.
protocol WindowMutationPerforming: Sendable {
    func mutate(
        window: WindowIdentity,
        to targetFrame: AXGlobalTopLeftFrame,
        within allowedFrame: AXGlobalTopLeftFrame
    ) async -> WindowMutationResult
}

enum WindowMutationFailure: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case windowNotMovable
    case windowNotResizable
    case windowDisappeared
    case mutationRejected
    case verificationTimedOut
    case rollbackIncomplete
}

enum WindowMutationResult: Equatable, Sendable {
    case applied(actualFrame: AXGlobalTopLeftFrame, constrained: Bool)
    case failed(WindowMutationFailure)
}

protocol AccessibilityWindowMutationAdapting: Sendable {
    func inspectWindow(_ identity: WindowIdentity) async -> AccessibilityWindowInspectionResult
    func writeFrame(
        _ request: AccessibilityFrameWriteRequest,
        to identity: WindowIdentity
    ) async -> AccessibilityWindowWriteResult
}

struct AccessibilityWindowInspection: Equatable, Sendable {
    let frame: AXGlobalTopLeftFrame
    let kind: WindowKind
    let capabilities: WindowCapabilities

    init(
        frame: CGRect,
        kind: WindowKind = .standard,
        capabilities: WindowCapabilities
    ) {
        self.frame = AXGlobalTopLeftFrame(frame)
        self.kind = kind
        self.capabilities = capabilities
    }
}

enum AccessibilityWindowInspectionResult: Sendable {
    case available(AccessibilityWindowInspection)
    case failure(AccessibilityWindowOperationFailure)
}

enum AccessibilityWindowOperationFailure: Sendable {
    case permissionRequired
    case windowDisappeared
    case temporarilyUnavailable
    case rejected
}

struct AccessibilityFrameAxes: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let position = Self(rawValue: 1 << 0)
    static let size = Self(rawValue: 1 << 1)
    static let all: Self = [.position, .size]
}

enum AccessibilityWindowWriteMode: Equatable, Sendable {
    case target
    case rollback
}

/// `axes` contains only attributes that differ by more than the verification tolerance and
/// were confirmed settable by the immediately preceding inspection.
struct AccessibilityFrameWriteRequest: Equatable, Sendable {
    let frame: AXGlobalTopLeftFrame
    let axes: AccessibilityFrameAxes
    let mode: AccessibilityWindowWriteMode
}

enum AccessibilityWindowWriteResult: Sendable {
    case accepted
    case failure(AccessibilityWindowOperationFailure)
}

protocol WindowMutationClock: Sendable {
    func now() async -> Duration
}

struct ContinuousWindowMutationClock: WindowMutationClock {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    func now() -> Duration {
        origin.duration(to: clock.now)
    }
}

struct WindowMutationPolicy: Sendable {
    static let standard = Self(maximumAttemptCount: 3, deadline: .seconds(12))

    let maximumAttemptCount: Int
    let deadline: Duration

    init(maximumAttemptCount: Int, deadline: Duration) {
        precondition(maximumAttemptCount > 0)
        precondition(deadline > .zero)
        self.maximumAttemptCount = maximumAttemptCount
        self.deadline = deadline
    }
}

actor WindowMutationModule: WindowMutationPerforming {
    private static let verificationTolerance: CGFloat = 1

    private struct MutationPlan {
        let targetFrame: AXGlobalTopLeftFrame
        let axes: AccessibilityFrameAxes
        let usesCapabilityFallback: Bool
    }

    private let adapter: any AccessibilityWindowMutationAdapting
    private let clock: any WindowMutationClock
    private let policy: WindowMutationPolicy

    init(
        adapter: any AccessibilityWindowMutationAdapting,
        clock: any WindowMutationClock = ContinuousWindowMutationClock(),
        policy: WindowMutationPolicy = .standard
    ) {
        self.adapter = adapter
        self.clock = clock
        self.policy = policy
    }

    func mutate(
        window identity: WindowIdentity,
        to targetFrame: AXGlobalTopLeftFrame,
        within allowedFrame: AXGlobalTopLeftFrame
    ) async -> WindowMutationResult {
        let target = targetFrame.cgRect
        let allowed = allowedFrame.cgRect
        guard Self.isValidFrame(target),
              Self.isValidFrame(allowed),
              Self.contains(allowed, target) else {
            return .failed(.mutationRejected)
        }

        let deadline = await clock.now() + policy.deadline

        var capturedInspection: AccessibilityWindowInspection?
        inspectionLoop: for attempt in 0..<policy.maximumAttemptCount {
            if attempt > 0 {
                guard await clock.now() < deadline else {
                    return .failed(.verificationTimedOut)
                }
            }
            switch await adapter.inspectWindow(identity) {
            case .available(let value):
                capturedInspection = value
                break inspectionLoop
            case .failure(.temporarilyUnavailable):
                continue
            case .failure(let failure):
                return .failed(map(failure))
            }
        }
        guard let inspection = capturedInspection else {
            return .failed(.mutationRejected)
        }

        let original = inspection.frame.cgRect
        guard Self.isValidFrame(original) else {
            return .failed(.mutationRejected)
        }
        guard await clock.now() < deadline else {
            return .failed(.verificationTimedOut)
        }

        guard inspection.capabilities.minimized != .active,
              inspection.capabilities.nativeFullScreen != .active else {
            return .failed(.mutationRejected)
        }

        var plan: MutationPlan
        switch mutationPlan(
            from: inspection.frame,
            toward: targetFrame,
            within: allowedFrame,
            capabilities: inspection.capabilities
        ) {
        case .success(let value):
            plan = value
        case .failure(let failure):
            return .failed(failure)
        }

        if plan.axes.isEmpty {
            return .applied(
                actualFrame: inspection.frame,
                constrained: plan.usesCapabilityFallback
            )
        }

        var currentCapabilities = inspection.capabilities
        var rollbackAxes: AccessibilityFrameAxes = []
        var usedCapabilityFallback = plan.usesCapabilityFallback
        var previousMismatch: CGRect?

        for _ in 0..<policy.maximumAttemptCount {
            guard await clock.now() < deadline else {
                guard !rollbackAxes.isEmpty else {
                    return .failed(.verificationTimedOut)
                }
                return await failAfterRollback(
                    .verificationTimedOut,
                    originalFrame: inspection.frame,
                    axes: rollbackAxes,
                    identity: identity
                )
            }

            let targetRequest = AccessibilityFrameWriteRequest(
                frame: plan.targetFrame,
                axes: plan.axes,
                mode: .target
            )
            rollbackAxes.formUnion(plan.axes)
            let writeResult = await adapter.writeFrame(targetRequest, to: identity)
            guard await clock.now() < deadline else {
                return await failAfterRollback(
                    .verificationTimedOut,
                    originalFrame: inspection.frame,
                    axes: rollbackAxes,
                    identity: identity
                )
            }

            switch writeResult {
            case .accepted:
                break
            case .failure(.temporarilyUnavailable):
                continue
            case .failure(let failure):
                return await failAfterRollback(
                    map(failure),
                    originalFrame: inspection.frame,
                    axes: rollbackAxes,
                    identity: identity
                )
            }

            let readBackResult = await adapter.inspectWindow(identity)
            guard await clock.now() < deadline else {
                return await failAfterRollback(
                    .verificationTimedOut,
                    originalFrame: inspection.frame,
                    axes: rollbackAxes,
                    identity: identity
                )
            }

            switch readBackResult {
            case .available(let readBack):
                let actual = readBack.frame.cgRect
                guard Self.isValidFrame(actual) else {
                    return await failAfterRollback(
                        .mutationRejected,
                        originalFrame: inspection.frame,
                        axes: rollbackAxes,
                        identity: identity
                    )
                }
                guard readBack.capabilities.minimized != .active,
                      readBack.capabilities.nativeFullScreen != .active else {
                    return await failAfterRollback(
                        .mutationRejected,
                        originalFrame: inspection.frame,
                        axes: rollbackAxes,
                        identity: identity
                    )
                }

                let effectiveTarget = plan.targetFrame.cgRect
                if framesMatch(actual, effectiveTarget) {
                    return .applied(
                        actualFrame: readBack.frame,
                        constrained: usedCapabilityFallback
                    )
                }
                if let stableMismatch = previousMismatch,
                   framesMatch(stableMismatch, actual),
                   isSafeApplicationClamp(
                       actual,
                       from: original,
                       toward: effectiveTarget,
                       within: allowed
                   ) {
                    return .applied(actualFrame: readBack.frame, constrained: true)
                }
                if let stableMismatch = previousMismatch,
                   framesMatch(stableMismatch, actual),
                   let reconciled = reconciledApplicationClamp(
                       actual,
                       from: original,
                       toward: effectiveTarget,
                       within: allowed
                   ) {
                    plan = MutationPlan(
                        targetFrame: AXGlobalTopLeftFrame(reconciled),
                        axes: changedAxes(from: actual, to: reconciled),
                        usesCapabilityFallback: true
                    )
                    usedCapabilityFallback = true
                    previousMismatch = nil
                    continue
                }
                previousMismatch = actual

                let capabilitiesChanged = readBack.capabilities.isMovable
                    != currentCapabilities.isMovable
                    || readBack.capabilities.isResizable
                    != currentCapabilities.isResizable
                if capabilitiesChanged {
                    let previousTarget = plan.targetFrame
                    switch mutationPlan(
                        from: readBack.frame,
                        toward: targetFrame,
                        within: allowedFrame,
                        capabilities: readBack.capabilities
                    ) {
                    case .success(let revalidatedPlan):
                        plan = revalidatedPlan
                        currentCapabilities = readBack.capabilities
                        usedCapabilityFallback = usedCapabilityFallback
                            || revalidatedPlan.usesCapabilityFallback
                        if revalidatedPlan.targetFrame != previousTarget {
                            previousMismatch = nil
                        }
                        if revalidatedPlan.axes.isEmpty {
                            return .applied(
                                actualFrame: readBack.frame,
                                constrained: usedCapabilityFallback
                            )
                        }
                    case .failure(let failure):
                        return await failAfterRollback(
                            failure,
                            originalFrame: inspection.frame,
                            axes: rollbackAxes,
                            identity: identity
                        )
                    }
                }
            case .failure(.temporarilyUnavailable):
                continue
            case .failure(let failure):
                return await failAfterRollback(
                    map(failure),
                    originalFrame: inspection.frame,
                    axes: rollbackAxes,
                    identity: identity
                )
            }
        }

        return await failAfterRollback(
            .verificationTimedOut,
            originalFrame: inspection.frame,
            axes: rollbackAxes,
            identity: identity
        )
    }

    private func mutationPlan(
        from originalFrame: AXGlobalTopLeftFrame,
        toward requestedFrame: AXGlobalTopLeftFrame,
        within allowedFrame: AXGlobalTopLeftFrame,
        capabilities: WindowCapabilities
    ) -> Result<MutationPlan, WindowMutationFailure> {
        let original = originalFrame.cgRect
        let requested = requestedFrame.cgRect
        let allowed = allowedFrame.cgRect
        let requestedAxes = changedAxes(from: original, to: requested)

        switch (capabilities.isMovable, capabilities.isResizable) {
        case (true, true):
            return .success(
                MutationPlan(
                    targetFrame: requestedFrame,
                    axes: requestedAxes,
                    usesCapabilityFallback: false
                )
            )

        case (true, false):
            guard requestedAxes.contains(.position) else {
                return requestedAxes.contains(.size)
                    ? .failure(.windowNotResizable)
                    : .success(
                        MutationPlan(
                            targetFrame: originalFrame,
                            axes: [],
                            usesCapabilityFallback: false
                        )
                    )
            }
            guard original.width <= allowed.width,
                  original.height <= allowed.height else {
                return .failure(.mutationRejected)
            }

            let maximumX = allowed.maxX - original.width
            let maximumY = allowed.maxY - original.height
            let fallback = CGRect(
                x: min(max(requested.minX, allowed.minX), maximumX),
                y: min(max(requested.minY, allowed.minY), maximumY),
                width: original.width,
                height: original.height
            )
            return .success(
                MutationPlan(
                    targetFrame: AXGlobalTopLeftFrame(fallback),
                    axes: changedAxes(from: original, to: fallback),
                    usesCapabilityFallback: requestedAxes.contains(.size)
                        || !originsMatch(fallback, requested)
                )
            )

        case (false, true):
            guard requestedAxes.contains(.size) else {
                return requestedAxes.contains(.position)
                    ? .failure(.windowNotMovable)
                    : .success(
                        MutationPlan(
                            targetFrame: originalFrame,
                            axes: [],
                            usesCapabilityFallback: false
                        )
                    )
            }

            let fallback = CGRect(origin: original.origin, size: requested.size)
            guard Self.contains(allowed, fallback) else {
                return .failure(.mutationRejected)
            }
            return .success(
                MutationPlan(
                    targetFrame: AXGlobalTopLeftFrame(fallback),
                    axes: changedAxes(from: original, to: fallback),
                    usesCapabilityFallback: requestedAxes.contains(.position)
                )
            )

        case (false, false):
            return requestedAxes.isEmpty
                ? .success(
                    MutationPlan(
                        targetFrame: originalFrame,
                        axes: [],
                        usesCapabilityFallback: false
                    )
                )
                : .failure(.mutationRejected)
        }
    }

    private func changedAxes(from original: CGRect, to target: CGRect) -> AccessibilityFrameAxes {
        var axes: AccessibilityFrameAxes = []
        if !originsMatch(original, target) { axes.insert(.position) }
        if !sizesMatch(original, target) { axes.insert(.size) }
        return axes
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        originsMatch(lhs, rhs) && sizesMatch(lhs, rhs)
    }

    private func originsMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= Self.verificationTolerance
            && abs(lhs.origin.y - rhs.origin.y) <= Self.verificationTolerance
    }

    private func sizesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.size.width - rhs.size.width) <= Self.verificationTolerance
            && abs(lhs.size.height - rhs.size.height) <= Self.verificationTolerance
    }

    private func isSafeApplicationClamp(
        _ actual: CGRect,
        from original: CGRect,
        toward target: CGRect,
        within allowed: CGRect
    ) -> Bool {
        guard Self.contains(allowed, actual),
              isApplicationClampCandidate(
                  actual,
                  from: original,
                  toward: target
              ) else {
            return false
        }

        return true
    }

    private func reconciledApplicationClamp(
        _ actual: CGRect,
        from original: CGRect,
        toward target: CGRect,
        within allowed: CGRect
    ) -> CGRect? {
        guard isApplicationClampCandidate(actual, from: original, toward: target),
              actual.width <= allowed.width + Self.verificationTolerance,
              actual.height <= allowed.height + Self.verificationTolerance else {
            return nil
        }

        let fitted = CGRect(
            x: min(max(actual.minX, allowed.minX), allowed.maxX - actual.width),
            y: min(max(actual.minY, allowed.minY), allowed.maxY - actual.height),
            width: actual.width,
            height: actual.height
        )
        guard Self.contains(allowed, fitted), !framesMatch(actual, fitted) else {
            return nil
        }
        return fitted
    }

    private func isApplicationClampCandidate(
        _ actual: CGRect,
        from original: CGRect,
        toward target: CGRect
    ) -> Bool {
        guard !framesMatch(actual, original), !framesMatch(actual, target) else {
            return false
        }

        return isBetween(actual.origin.x, original.origin.x, target.origin.x)
            && isBetween(actual.origin.y, original.origin.y, target.origin.y)
            && isBetween(actual.size.width, original.size.width, target.size.width)
            && isBetween(actual.size.height, original.size.height, target.size.height)
    }

    private func isBetween(_ value: CGFloat, _ first: CGFloat, _ second: CGFloat) -> Bool {
        let lowerBound = min(first, second) - Self.verificationTolerance
        let upperBound = max(first, second) + Self.verificationTolerance
        return lowerBound...upperBound ~= value
    }

    private func failAfterRollback(
        _ primaryFailure: WindowMutationFailure,
        originalFrame: AXGlobalTopLeftFrame,
        axes: AccessibilityFrameAxes,
        identity: WindowIdentity
    ) async -> WindowMutationResult {
        let request = AccessibilityFrameWriteRequest(
            frame: originalFrame,
            axes: axes,
            mode: .rollback
        )
        switch await adapter.writeFrame(request, to: identity) {
        case .accepted:
            break
        case .failure(.windowDisappeared) where primaryFailure == .windowDisappeared:
            return .failed(primaryFailure)
        case .failure:
            return .failed(.rollbackIncomplete)
        }

        switch await adapter.inspectWindow(identity) {
        case .available(let inspection)
                where Self.isValidFrame(inspection.frame.cgRect)
                && framesMatch(inspection.frame.cgRect, originalFrame.cgRect):
            return .failed(primaryFailure)
        case .failure(.windowDisappeared) where primaryFailure == .windowDisappeared:
            return .failed(primaryFailure)
        case .available, .failure:
            return .failed(.rollbackIncomplete)
        }
    }

    private func map(_ failure: AccessibilityWindowOperationFailure) -> WindowMutationFailure {
        switch failure {
        case .permissionRequired:
            return .accessibilityPermissionRequired
        case .windowDisappeared:
            return .windowDisappeared
        case .temporarilyUnavailable, .rejected:
            return .mutationRejected
        }
    }

    private static func isValidFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.size.width > 0
            && frame.size.height > 0
            && frame.maxX.isFinite
            && frame.maxY.isFinite
    }

    private static func contains(_ bounds: CGRect, _ frame: CGRect) -> Bool {
        frame.minX >= bounds.minX
            && frame.minY >= bounds.minY
            && frame.maxX <= bounds.maxX
            && frame.maxY <= bounds.maxY
    }
}
