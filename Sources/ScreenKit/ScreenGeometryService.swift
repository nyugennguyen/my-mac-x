import CoreGraphics

public struct ScreenGeometryService: ScreenGeometryProviding, Sendable {
    /// Half a logical point absorbs harmless public-API rounding drift while remaining
    /// below the project's one-point geometry acceptance threshold.
    private static let logicalPointTolerance: CGFloat = 0.5

    private let adapter: any ScreenGeometryAdapting

    public init() {
        adapter = SystemScreenGeometryAdapter()
    }

    init(adapter: any ScreenGeometryAdapting) {
        self.adapter = adapter
    }

    public func displays() async -> ScreenGeometryResult {
        switch await adapter.captureDisplays() {
        case .failure:
            return .unavailable(.systemUnavailable)
        case .displays(let candidates):
            guard !candidates.isEmpty else {
                return .unavailable(.noDisplays)
            }

            var identifiedCandidates: [(id: DisplayID, candidate: DisplayGeometryCandidate)] = []
            identifiedCandidates.reserveCapacity(candidates.count)
            for candidate in candidates {
                guard let id = candidate.displayID,
                      id.rawValue != kCGNullDirectDisplay
                else {
                    return .unavailable(.displayIdentityUnavailable)
                }
                identifiedCandidates.append((id, candidate))
            }

            let primaryCandidates = identifiedCandidates.filter(\.candidate.isPrimary)
            guard let primaryDisplayID = primaryCandidates.first?.id else {
                return .unavailable(.primaryDisplayUnavailable)
            }
            guard primaryCandidates.count == 1 else {
                return .unavailable(.multiplePrimaryDisplays)
            }

            identifiedCandidates.sort {
                $0.id.rawValue < $1.id.rawValue
            }
            for index in identifiedCandidates.indices.dropFirst() {
                let previousID = identifiedCandidates[
                    identifiedCandidates.index(before: index)
                ].id
                if identifiedCandidates[index].id == previousID {
                    return .unavailable(.duplicateDisplayIdentity(previousID))
                }
            }
            var displays: [DisplaySnapshot] = []
            displays.reserveCapacity(identifiedCandidates.count)

            for (id, candidate) in identifiedCandidates {
                guard isValidNonEmptyRectangle(candidate.frame) else {
                    return .unavailable(.invalidFrame(id))
                }
                guard let visibleFrame = clampedRectangle(
                    candidate.visibleFrame,
                    inside: candidate.frame
                ) else {
                    return .unavailable(.invalidVisibleFrame(id))
                }
                guard candidate.backingScaleFactor.isFinite,
                      candidate.backingScaleFactor > 0
                else {
                    return .unavailable(.invalidBackingScale(id))
                }

                displays.append(DisplaySnapshot(
                    id: id,
                    frame: candidate.frame,
                    visibleFrame: visibleFrame,
                    backingScaleFactor: candidate.backingScaleFactor,
                    safeArea: candidate.safeArea,
                    notchTrigger: notchTrigger(
                        in: candidate.frame,
                        safeArea: candidate.safeArea
                    )
                ))
            }

            displays.sort {
                if $0.frame.minX < $1.frame.minX {
                    return true
                }
                if $0.frame.minX > $1.frame.minX {
                    return false
                }
                if $0.frame.minY < $1.frame.minY {
                    return true
                }
                if $0.frame.minY > $1.frame.minY {
                    return false
                }
                return $0.id.rawValue < $1.id.rawValue
            }

            return .available(DisplayTopologySnapshot(
                displays: displays,
                primaryDisplayID: primaryDisplayID
            ))
        }
    }

    private func isValidNonEmptyRectangle(_ rectangle: CGRect) -> Bool {
        rectangle.origin.x.isFinite
            && rectangle.origin.y.isFinite
            && rectangle.width.isFinite
            && rectangle.height.isFinite
            && rectangle.width > 0
            && rectangle.height > 0
            && rectangle.maxX.isFinite
            && rectangle.maxY.isFinite
    }

    private func clampedRectangle(_ rectangle: CGRect, inside frame: CGRect) -> CGRect? {
        guard isValidNonEmptyRectangle(rectangle),
              rectangle.minX >= frame.minX - Self.logicalPointTolerance,
              rectangle.minY >= frame.minY - Self.logicalPointTolerance,
              rectangle.maxX <= frame.maxX + Self.logicalPointTolerance,
              rectangle.maxY <= frame.maxY + Self.logicalPointTolerance
        else {
            return nil
        }

        let clamped = rectangle.intersection(frame)
        return isValidNonEmptyRectangle(clamped) ? clamped : nil
    }

    private func approximatelyEqual(_ first: CGFloat, _ second: CGFloat) -> Bool {
        abs(first - second) <= Self.logicalPointTolerance
    }

    private func notchTrigger(in frame: CGRect, safeArea: DisplaySafeArea) -> NotchTrigger {
        let insets = safeArea.insets
        guard insets.top.isFinite, insets.left.isFinite,
              insets.bottom.isFinite, insets.right.isFinite,
              insets.top > 0, insets.top <= frame.height,
              insets.left >= 0, insets.bottom >= 0, insets.right >= 0,
              insets.left <= frame.width + Self.logicalPointTolerance,
              insets.right <= frame.width + Self.logicalPointTolerance,
              insets.bottom <= frame.height + Self.logicalPointTolerance,
              insets.left + insets.right <= frame.width + Self.logicalPointTolerance,
              insets.top + insets.bottom <= frame.height + Self.logicalPointTolerance,
              let left = safeArea.auxiliaryTopLeftArea,
              let right = safeArea.auxiliaryTopRightArea,
              let clampedLeft = clampedRectangle(left, inside: frame),
              let clampedRight = clampedRectangle(right, inside: frame),
              approximatelyEqual(left.maxY, frame.maxY),
              approximatelyEqual(right.maxY, frame.maxY),
              approximatelyEqual(left.minY, frame.maxY - insets.top),
              approximatelyEqual(right.minY, frame.maxY - insets.top),
              clampedLeft.maxX < clampedRight.minX,
              clampedLeft.maxX <= frame.midX + Self.logicalPointTolerance,
              clampedRight.minX >= frame.midX - Self.logicalPointTolerance
        else {
            return topCenterFallback(in: frame)
        }

        let notch = CGRect(
            x: clampedLeft.maxX,
            y: frame.maxY - insets.top,
            width: clampedRight.minX - clampedLeft.maxX,
            height: insets.top
        ).intersection(frame)
        let expandedTrigger = CGRect(
            x: notch.minX - 32,
            y: notch.minY - 20,
            width: notch.width + 64,
            height: notch.height + 20
        )

        return NotchTrigger(
            classification: .notch,
            inferredNotchRegion: notch,
            region: expandedTrigger.intersection(frame)
        )
    }

    private func topCenterFallback(in frame: CGRect) -> NotchTrigger {
        let width = min(180, frame.width * 0.25)
        let height = min(16, frame.height)
        let region = CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        ).intersection(frame)

        return NotchTrigger(
            classification: .topCenterFallback,
            inferredNotchRegion: nil,
            region: region
        )
    }
}

/// Captures one fresh atomic topology for the initial state and after every AppKit
/// screen-parameter notification. Equivalent captures do not advance the generation.
struct DisplayTopologyObserver: DisplayTopologyObserving, Sendable {
    private let geometry: any ScreenGeometryProviding
    private let changes: any ScreenParameterChangeAdapting

    init() {
        geometry = ScreenGeometryService()
        changes = SystemScreenParameterChangeAdapter()
    }

    init(
        geometry: any ScreenGeometryProviding,
        changes: any ScreenParameterChangeAdapting
    ) {
        self.geometry = geometry
        self.changes = changes
    }

    func updates() async -> AsyncStream<DisplayTopologyState> {
        let notifications = await changes.changes()

        return AsyncStream { continuation in
            let producer = Task.detached {
                var lastResult: ScreenGeometryResult?
                var generation: UInt64 = 0

                func publish(_ result: ScreenGeometryResult) -> Bool {
                    guard result != lastResult else { return true }
                    guard generation < UInt64.max else { return false }

                    generation += 1
                    lastResult = result
                    let currentGeneration = DisplayTopologyGeneration(rawValue: generation)
                    switch result {
                    case .available(let topology):
                        continuation.yield(.available(VersionedDisplayTopology(
                            generation: currentGeneration,
                            topology: topology
                        )))
                    case .unavailable(let failure):
                        continuation.yield(.unavailable(
                            generation: currentGeneration,
                            failure: failure
                        ))
                    }
                    return true
                }

                let initialResult = await geometry.displays()
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                guard publish(initialResult) else {
                    continuation.finish()
                    return
                }

                for await _ in notifications {
                    guard !Task.isCancelled else { break }
                    let result = await geometry.displays()
                    guard !Task.isCancelled else { break }
                    guard publish(result) else { break }
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }
    }
}

struct RestoreTargetReconciliation: Equatable, Sendable {
    let frame: CGRect
    let wasAdjusted: Bool
}

enum RestoreTargetReconciliationFailure: Error, Equatable, Sendable {
    case invalidRestoreTarget
    case noCurrentDisplay
}

/// Pure topology-change policy used by the Window Action Engine.
///
/// Restore targets are reconciled from canonical geometry alone. No previous `DisplayID`
/// enters this Interface, so reconnects cannot be correlated by topology-scoped identity.
struct DisplayTopologyReconciler: Sendable {
    static func previewRemainsValid(
        capturedAt generation: DisplayTopologyGeneration,
        current: DisplayTopologyState
    ) -> Bool {
        guard case .available(let versioned) = current else { return false }
        return versioned.generation == generation
    }

    static func restoreTarget(
        _ target: CGRect,
        in topology: DisplayTopologySnapshot
    ) -> Result<RestoreTargetReconciliation, RestoreTargetReconciliationFailure> {
        guard isValidNonEmptyFrame(target) else {
            return .failure(.invalidRestoreTarget)
        }

        let displays = topology.displays.filter {
            isValidNonEmptyFrame($0.visibleFrame)
        }
        guard let destination = displays.min(by: { left, right in
            destinationOrder(
                left,
                right,
                for: target,
                primaryDisplayID: topology.primaryDisplayID
            )
        }) else {
            return .failure(.noCurrentDisplay)
        }

        let reconciled = clamp(target, inside: destination.visibleFrame)
        return .success(RestoreTargetReconciliation(
            frame: reconciled,
            wasAdjusted: reconciled != target
        ))
    }

    private static func destinationOrder(
        _ left: DisplaySnapshot,
        _ right: DisplaySnapshot,
        for target: CGRect,
        primaryDisplayID: DisplayID
    ) -> Bool {
        let leftIntersection = intersectionArea(target, left.visibleFrame)
        let rightIntersection = intersectionArea(target, right.visibleFrame)
        if leftIntersection != rightIntersection {
            return leftIntersection > rightIntersection
        }

        let leftDistance = squaredDistance(target.center, left.visibleFrame.center)
        let rightDistance = squaredDistance(target.center, right.visibleFrame.center)
        if leftDistance != rightDistance {
            return leftDistance < rightDistance
        }

        if left.id == primaryDisplayID, right.id != primaryDisplayID {
            return true
        }
        if right.id == primaryDisplayID, left.id != primaryDisplayID {
            return false
        }
        if left.visibleFrame.minX != right.visibleFrame.minX {
            return left.visibleFrame.minX < right.visibleFrame.minX
        }
        if left.visibleFrame.minY != right.visibleFrame.minY {
            return left.visibleFrame.minY < right.visibleFrame.minY
        }
        return left.id.rawValue < right.id.rawValue
    }

    private static func clamp(_ frame: CGRect, inside visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }

    private static func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private static func isValidNonEmptyFrame(_ frame: CGRect) -> Bool {
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

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
