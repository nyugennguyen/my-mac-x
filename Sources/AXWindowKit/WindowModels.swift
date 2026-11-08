import Foundation

/// Opaque identity captured for one Accessibility window.
///
/// The value deliberately carries no title or document metadata. The system Adapter
/// owns the association between this token and the underlying Accessibility element.
public struct WindowIdentity: Hashable, Sendable {
    public let processID: pid_t
    private let rawValue: UUID

    public init(processID: pid_t = 0) {
        self.processID = processID
        rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.processID = 0
        self.rawValue = rawValue
    }

    public init(processID: pid_t, rawValue: UUID) {
        self.processID = processID
        self.rawValue = rawValue
    }
}

/// Knowledge available for the Native Full Screen state.
///
/// Accessibility exposes no documented state attribute for another application's
/// Native Full Screen window. `unavailable` keeps that platform limitation explicit.
enum NativeFullScreenState: Equatable, Sendable {
    case active
    case inactive
    case unavailable
}

/// Knowledge available for the standard minimized window attribute.
///
/// Some Accessibility providers do not expose a value. `unavailable` prevents
/// absence of support from being mistaken for a known inactive state.
enum WindowMinimizedState: Equatable, Sendable {
    case active
    case inactive
    case unavailable
}

/// Internal Accessibility classification for an Eligible Window.
///
/// This deliberately uses only documented roles and subroles. It never derives a kind
/// from a window title, parent relationship, geometry, or private state.
enum WindowKind: Equatable, Sendable {
    case standard
    case dialog
    case sheet
}

struct WindowCapabilities: Equatable, Sendable {
    let isMovable: Bool
    let isResizable: Bool
    let minimized: WindowMinimizedState
    let nativeFullScreen: NativeFullScreenState

    init(
        isMovable: Bool,
        isResizable: Bool,
        minimized: WindowMinimizedState,
        nativeFullScreen: NativeFullScreenState
    ) {
        self.isMovable = isMovable
        self.isResizable = isResizable
        self.minimized = minimized
        self.nativeFullScreen = nativeFullScreen
    }
}

struct EligibleWindow: Equatable, Sendable {
    let identity: WindowIdentity
    let kind: WindowKind
    let capabilities: WindowCapabilities

    init(
        identity: WindowIdentity,
        kind: WindowKind = .standard,
        capabilities: WindowCapabilities
    ) {
        self.identity = identity
        self.kind = kind
        self.capabilities = capabilities
    }
}

enum FocusedWindowFailure: Error, Equatable, Sendable {
    case permissionRequired
    case noEligibleWindow
    case temporarilyUnavailable
    case systemUnavailable
}

enum FocusedWindowResult: Equatable, Sendable {
    case found(EligibleWindow)
    case unavailable(FocusedWindowFailure)
}

protocol FocusedWindowProviding: Sendable {
    func focusedWindow() async -> FocusedWindowResult
}
