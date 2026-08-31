import CoreGraphics
import Foundation

public protocol WindowActionPerforming: Sendable {
    func perform(_ intent: WindowIntent) async -> WindowActionResult
}

public struct InteractionID: Hashable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum ActionSource: Hashable, Sendable {
    case hotkey(bindingID: UUID)
    case notch
    case superMode
    case menuBar
    case settingsTest
}

public enum WindowIntent: Sendable {
    /// Starts or revises a non-mutating preview transaction.
    ///
    /// Pointer interactions provide `capturedWindow` so focus changes cannot retarget the Snap.
    /// `nil` preserves focused-window capture for non-pointer preview callers.
    case preview(
        action: ActionID,
        interaction: InteractionID,
        capturedWindow: WindowIdentity? = nil,
        targetDisplay: DisplayID? = nil
    )
    case commit(action: ActionID, source: ActionSource)
    case commitPreview(interaction: InteractionID)
    case cancelPreview(interaction: InteractionID)
    case undo(token: UndoToken?, source: ActionSource)
}

public struct WindowActionResult: Equatable, Sendable {
    public let disposition: Disposition
    public let effect: Effect
    public let undoToken: UndoToken?
    public let warnings: [Warning]

    public init(
        disposition: Disposition,
        effect: Effect,
        undoToken: UndoToken?,
        warnings: [Warning]
    ) {
        self.disposition = disposition
        self.effect = effect
        self.undoToken = undoToken
        self.warnings = warnings
    }

    public enum Disposition: Equatable, Sendable {
        case succeeded
        case rejected(WindowActionFailure)
        case superseded
        case cancelled
    }

    public enum Effect: Equatable, Sendable {
        case none
        case preview(frame: CGRect, displayID: UInt32, constrained: Bool)
        case committed(actualFrame: CGRect, constrained: Bool)
        case undone(actualFrame: CGRect)
    }

    public enum Warning: Equatable, Sendable {
        case constrainedByApplication
        case targetDisplayChanged
        case rollbackIncomplete
    }
}

extension WindowActionResult {
    static func rejected(
        _ failure: WindowActionFailure,
        warnings: [Warning] = []
    ) -> Self {
        Self(
            disposition: .rejected(failure),
            effect: .none,
            undoToken: nil,
            warnings: warnings
        )
    }

    static let superseded = Self(
        disposition: .superseded,
        effect: .none,
        undoToken: nil,
        warnings: []
    )

    static let cancelled = Self(
        disposition: .cancelled,
        effect: .none,
        undoToken: nil,
        warnings: []
    )
}
