# Window Action Interface

This document defines the external seam selected in [ADR-0003](../adr/0003-intent-driven-window-action-module.md). It is an interface contract for Sprint 0, not production implementation.

## Interface

```swift
import CoreGraphics
import Foundation

public protocol WindowActionPerforming: Sendable {
    func perform(_ intent: WindowIntent) async -> WindowActionResult
}

public struct ActionID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct InteractionID: Hashable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct UndoToken: Hashable, Sendable {
    fileprivate let rawValue: UUID
}

public enum ActionSource: Hashable, Sendable {
    case hotkey(bindingID: UUID)
    case notch
    case superMode
    case menuBar
    case settingsTest
}

public enum WindowIntent: Sendable {
    case preview(action: ActionID, interaction: InteractionID)
    case commit(action: ActionID, source: ActionSource)
    case commitPreview(interaction: InteractionID)
    case cancelPreview(interaction: InteractionID)
    case undo(token: UndoToken?, source: ActionSource)
}

public struct WindowActionResult: Sendable {
    public let disposition: Disposition
    public let effect: Effect
    public let undoToken: UndoToken?
    public let warnings: [Warning]

    public enum Disposition: Sendable {
        case succeeded
        case rejected(WindowActionFailure)
        case superseded
        case cancelled
    }

    public enum Effect: Sendable {
        case none
        case preview(frame: CGRect, displayID: UInt32, constrained: Bool)
        case committed(actualFrame: CGRect, constrained: Bool)
        case undone(actualFrame: CGRect)
    }

    public enum Warning: Sendable {
        case constrainedByApplication
        case targetDisplayChanged
        case rollbackIncomplete
    }
}

public enum WindowActionFailure: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case noFocusedWindow
    case unknownAction(ActionID)
    case actionDisabled(ActionID)
    case windowNotMovable
    case windowNotResizable
    case windowDisappeared
    case displayUnavailable
    case constraintsUnsatisfiable
    case mutationRejected
    case verificationTimedOut
    case previewMissingOrExpired
    case rollbackIncomplete
}
```

Built-in `ActionID` values are declared as static constants, while the raw value remains stable for persisted custom bindings and layouts.

## Caller examples

```swift
let result = await windowActions.perform(
    .commit(action: binding.actionID, source: .hotkey(bindingID: binding.id))
)

let preview = await windowActions.perform(
    .preview(action: hoveredActionID, interaction: dragInteractionID)
)

let committed = await windowActions.perform(
    .commitPreview(interaction: dragInteractionID)
)
```

Callers render `WindowActionResult` through a UI-owned feedback mapper. No AppKit or SwiftUI presentation type crosses this seam.

## Invariants

1. A direct commit resolves and captures the Focused Window exactly once when execution starts.
2. The first preview binds its `InteractionID` to one Captured Window and one display snapshot.
3. `commitPreview` targets the bound Captured Window; it never falls back to a newly Focused Window.
4. Preview does not mutate Accessibility state or write history.
5. Results from superseded hover calculations return `.superseded` and no visible effect.
6. Commit validates action, permission, capability, display and constraints before mutation.
7. The Module stages a Window Snapshot before the first mutation.
8. Success is returned only after Accessibility read-back verifies the actual frame.
9. History is committed only after successful read-back; an `UndoToken` identifies that exact entry.
10. Partial mutation performs bounded recovery. A failed rollback is reported explicitly.
11. Transactions for the same Captured Window are serialized; ordering across different windows is unspecified.
12. Runtime failures are values in `WindowActionResult`; AX objects and raw AX errors never cross the seam.
13. Result payloads contain no typed text, window title or document title.

## Performance contract

- Preview after the first interaction bind is pure calculation and targets p95 below 8 ms.
- Direct commit begins Accessibility mutation within p95 below 100 ms on the lowest supported test machine.
- Standard mutation/read-back has a finite deadline; Native Full Screen owns a separate longer policy.
- The Interface never runs on `MainActor`; UI rendering returns to `MainActor` after the result.
- No polling is part of the Interface contract.

## Hidden implementation

The Module owns action resolution, window identity, eligibility, include/exclude rules, cycle state, screen selection, coordinate conversion, Layout calculation, constraints, gaps, history, mutation ordering, retry, read-back, rollback, cancellation and privacy-safe diagnostics.

Internal seams exist only where two real Adapters are required:

| Dependency | Production Adapter | Test Adapter |
|---|---|---|
| macOS Accessibility | `SystemWindowAdapter` | `ScriptedWindowAdapter` |
| Screen topology | `SystemScreenAdapter` | `FixtureScreenAdapter` |
| Action catalog | Versioned local adapter | In-memory catalog adapter |
| Window history | Bounded local/session adapter | In-memory history adapter |
| Monotonic time | `ContinuousClock` | Controllable test clock |

Layout calculation, constraint resolution and result mapping are in-process implementation, not public ports.

## Deferred extension

A declarative multi-window transaction program is not part of this Interface in v1. It can be reconsidered when a real batch/tiling caller exists; until then, adding it would enlarge the Interface and introduce program schema migrations without current Leverage.
