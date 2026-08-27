# H3-02 — Stable ActionRegistry evidence

Date: 2026-08-26

## Confirmed seam

`ActionRegistry` is a read-only discovery module. It exposes a stable `ActionID`,
display-safe metadata (`title` and SF Symbol name), and typed availability. It
does not import Accessibility or AppKit, resolve layouts, or execute actions.

`HotkeyActionDispatcher` is deliberately a small orchestration adapter: it maps
one `HotkeyInvocation(bindingID, actionID)` to exactly one
`WindowActionPerforming.perform(.commit(action:source:))` call with
`.hotkey(bindingID:)`. It contains no registration or accessibility behavior.

## Vertical slices

1. The registry exposes each built-in bindable Window Action once with an
   asserted stable raw `ActionID`.
2. A caller can still discover an unavailable action and distinguish its typed
   reason from an available action.
3. Metadata remains value-only and presentation-framework-free.
4. A hotkey event preserves both its binding identity and `ActionID` as it
   crosses the existing Window Action Interface.

## Validation

The source target typechecked successfully under Swift 6 strict concurrency:

```text
xcrun swiftc -target arm64-apple-macos14.0 -swift-version 6 \
  -strict-concurrency=complete -module-cache-path /private/tmp/h3-02-green/module-cache \
  -parse-as-library -enable-testing -emit-module \
  -emit-module-path /private/tmp/h3-02-green/MyMacX.swiftmodule \
  -module-name MyMacX Sources/AppShell/*.swift Sources/AXWindowKit/*.swift \
  Sources/CommandKit/*.swift Sources/CycleKit/*.swift Sources/DiagnosticsKit/*.swift \
  Sources/DisplayMoveKit/*.swift Sources/GeometryKit/*.swift Sources/HistoryKit/*.swift \
  Sources/InputKit/*.swift Sources/LayoutKit/*.swift Sources/PermissionKit/*.swift \
  Sources/ScreenKit/*.swift Sources/WindowActionKit/*.swift
```

After root target integration, the focused XCTest passed:

```text
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX \
  -only-testing:MyMacXTests/ActionRegistryTests

Executed 4 tests, with 0 failures
** TEST SUCCEEDED **
```

## Required root integration

The root owner integrated these files into the app/test targets:

- `Sources/CommandKit/ActionRegistry.swift` → `MyMacX` target
- `Tests/MyMacXTests/CommandKit/ActionRegistryTests.swift` → `MyMacXTests` target
- `xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -only-testing:MyMacXTests/ActionRegistryTests`
