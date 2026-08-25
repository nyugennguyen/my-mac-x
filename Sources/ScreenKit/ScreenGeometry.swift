import CoreGraphics
import Foundation

public struct DisplayID: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public struct DisplayEdgeInsets: Equatable, Sendable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct DisplaySafeArea: Equatable, Sendable {
    public let insets: DisplayEdgeInsets
    public let auxiliaryTopLeftArea: CGRect?
    public let auxiliaryTopRightArea: CGRect?

    public init(
        insets: DisplayEdgeInsets,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) {
        self.insets = insets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }
}

public enum NotchTriggerClassification: Equatable, Sendable {
    case notch
    case topCenterFallback
}

public struct NotchTrigger: Equatable, Sendable {
    public let classification: NotchTriggerClassification
    public let inferredNotchRegion: CGRect?
    public let region: CGRect

    public init(
        classification: NotchTriggerClassification,
        inferredNotchRegion: CGRect?,
        region: CGRect
    ) {
        self.classification = classification
        self.inferredNotchRegion = inferredNotchRegion
        self.region = region
    }
}

public struct DisplaySnapshot: Equatable, Sendable {
    public let id: DisplayID
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let backingScaleFactor: CGFloat
    public let safeArea: DisplaySafeArea
    public let notchTrigger: NotchTrigger

    public init(
        id: DisplayID,
        frame: CGRect,
        visibleFrame: CGRect,
        backingScaleFactor: CGFloat,
        safeArea: DisplaySafeArea,
        notchTrigger: NotchTrigger
    ) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.safeArea = safeArea
        self.notchTrigger = notchTrigger
    }
}

public enum ScreenGeometryFailure: Error, Equatable, Sendable {
    case noDisplays
    case displayIdentityUnavailable
    case duplicateDisplayIdentity(DisplayID)
    case primaryDisplayUnavailable
    case multiplePrimaryDisplays
    case invalidFrame(DisplayID)
    case invalidVisibleFrame(DisplayID)
    case invalidBackingScale(DisplayID)
    case systemUnavailable
}

/// One validated screen-parameter capture.
///
/// Display ordering is spatial and does not encode primary status. `primaryDisplayID` is
/// captured explicitly from the same system read as `displays` before spatial sorting.
public struct DisplayTopologySnapshot: Equatable, Sendable {
    public let displays: [DisplaySnapshot]
    public let primaryDisplayID: DisplayID

    init(displays: [DisplaySnapshot], primaryDisplayID: DisplayID) {
        self.displays = displays
        self.primaryDisplayID = primaryDisplayID
    }
}

/// One atomic, validated view of the currently connected physical Displays.
///
/// Available Displays are ordered by global `frame.minX`, then `frame.minY`, then
/// topology-scoped display identity. Geometry that exceeds a Display by at most half a
/// logical point is accepted as rounding drift and clamped to its frame; a single
/// materially invalid candidate fails the whole snapshot so callers never act on a
/// partial or internally inconsistent topology. Display identities must not be used to
/// correlate a Display across disconnect/reconnect.
public enum ScreenGeometryResult: Equatable, Sendable {
    case available(DisplayTopologySnapshot)
    case unavailable(ScreenGeometryFailure)
}

public protocol ScreenGeometryProviding: Sendable {
    /// Captures fresh geometry; callers must not cache it across screen-parameter changes.
    func displays() async -> ScreenGeometryResult
}

/// A monotonically increasing identifier scoped to one topology-observation session.
///
/// It has no meaning after that session ends and is never persisted.
struct DisplayTopologyGeneration: RawRepresentable, Equatable, Comparable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct VersionedDisplayTopology: Equatable, Sendable {
    let generation: DisplayTopologyGeneration
    let topology: DisplayTopologySnapshot
}

/// One material state observed from fresh atomic geometry captures.
enum DisplayTopologyState: Equatable, Sendable {
    case available(VersionedDisplayTopology)
    case unavailable(generation: DisplayTopologyGeneration, failure: ScreenGeometryFailure)

    var generation: DisplayTopologyGeneration {
        switch self {
        case .available(let versioned):
            versioned.generation
        case .unavailable(let generation, _):
            generation
        }
    }
}

/// Internal ScreenKit Interface for an initial topology and subsequent material changes.
/// Each returned stream is one independent in-session generation scope.
protocol DisplayTopologyObserving: Sendable {
    func updates() async -> AsyncStream<DisplayTopologyState>
}

struct DisplayGeometryCandidate: Equatable, Sendable {
    let displayID: DisplayID?
    let isPrimary: Bool
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat
    let safeArea: DisplaySafeArea
}

enum ScreenGeometryCapture: Equatable, Sendable {
    case displays([DisplayGeometryCandidate])
    case failure
}

protocol ScreenGeometryAdapting: Sendable {
    func captureDisplays() async -> ScreenGeometryCapture
}

/// System-notification seam. Production observes AppKit; tests drive a deterministic stream.
protocol ScreenParameterChangeAdapting: Sendable {
    func changes() async -> AsyncStream<Void>
}
