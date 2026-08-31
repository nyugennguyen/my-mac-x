# H3-01 — Global Hotkey lifecycle evidence

Status: `PASS`

## Human gate result — 2026-08-27

The user confirmed the remaining real global-hotkey and sleep/wake checks passed.

## Confirmed Interface

The user confirmed the proposed `GlobalHotkeyManaging` test seam on 2026-08-26. The Module
accepts complete desired binding snapshots through an idempotent reconcile operation and
publishes privacy-safe `HotkeyInvocation` values through `AsyncStream`.

## Red → green evidence

1. The initial targeted test failed to compile because the Interface, binding model,
   invocation model, Module and system Adapter did not exist.
2. The first minimal implementation passed the observable registration/invocation case.
3. The idempotence test then failed with two system registration passes for the same desired
   snapshot (`2 != 1`).
4. Caching the last successfully applied snapshot made both tests pass.
5. The failed-replacement test then failed to compile because typed registration failures,
   degraded snapshots and Adapter rollback controls did not exist.
6. Typed system reconciliation made the failed replacement report its binding-specific
   failure while the deterministic Adapter retained the prior active binding.
7. Replacement/removal tests proved that old binding identities no longer emit through the
   public event stream. Empty reconciliation returned an empty active snapshot and emitted
   nothing for the released binding.
8. The sleep/wake test failed to compile before lifecycle observation existed. A single
   internal lifecycle callback plus state guards made first sleep release and first wake
   restore exactly one effective registration; repeated reconciliation and repeated wake
   remained no-ops.
9. A rollback-cache tracer then failed because reconciling the prior valid snapshot returned
   the last degraded attempt. Retaining the last successful snapshot fixed the result without
   another system registration pass.

Targeted command:

```text
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/mymacx-s3-h301 \
  -only-testing:MyMacXTests/GlobalHotkeyManagerTests
```

Result: 7 tests executed, 0 failures on 2026-08-26. Covered cases are initial invocation,
unchanged idempotence, replacement, empty release, typed rollback, restoration of the prior
valid snapshot, and sleep/wake plus repeated-start/wake idempotence.

## Production macOS Adapter

[`h3-01-carbon-api-research.md`](h3-01-carbon-api-research.md) records the primary-source
API decision and limitations. `MacOSGlobalHotkeySystem` uses only public AppKit and
`Carbon.HIToolbox` APIs:

- all non-thread-safe Carbon registration/event-handler calls are main-actor isolated;
- one application event handler extracts only the owned `EventHotKeyID` and publishes the
  matching binding identity and Action ID;
- project modifiers are explicitly translated to Carbon modifier masks;
- unchanged physical chords retain their registration while metadata changes;
- new chords are staged before obsolete registrations are released, and a failed stage rolls
  back all staged references while preserving typed `OSStatus` failures;
- `eventHotKeyExistsErr` maps to the binding-specific unavailable-chord failure while other
  registration/release/handler failures remain distinguishable; and
- `NSWorkspace.willSleepNotification` / `.didWakeNotification` drive the Module's defensive
  release/restore lifecycle.

Compile-and-link verification before project integration:

```text
xcrun swiftc -target arm64-apple-macos14.0 -swift-version 6 \
  -strict-concurrency=complete -warnings-as-errors -parse-as-library -emit-library \
  Sources/CommandKit/ActionID.swift Sources/InputKit/GlobalHotkeyManager.swift \
  Sources/InputKit/MacOSGlobalHotkeySystem.swift -o <temporary dylib>
```

Result: succeeded; output was an arm64 Mach-O dynamic library on 2026-08-26. This is compile,
strict-concurrency and linker evidence, not a live hotkey or hardware lifecycle pass.

The orchestrator then integrated `MacOSGlobalHotkeySystem.swift` into the app target and ran
the full project gates on 2026-08-26:

- Debug test suite: 173 tests executed, 2 skipped, 0 failures.
- Release build: succeeded under the project's Swift 6 settings.

## Proven so far

- A reconciled binding can publish its exact binding identity and Action ID.
- Invocation values contain no raw key event, character, typed text or window metadata.
- Reconciling an unchanged desired snapshot does not repeat the registration pass.
- Replacement, removal, rollback and automated sleep/wake state transitions behave through
  the confirmed Interface.
- The production Adapter imports and links only public SDK frameworks for the macOS 14 target.
- The integrated app target passes the full Debug test suite and Release build.

## AppShell composition

Root integrated `MacOSGlobalHotkeySystem` and `GlobalHotkeyManager` through an AppShell-owned
runtime coordinator. App startup reconciles the four approved product-mockup defaults and
routes the single retained event stream through `HotkeyActionDispatcher` into
`WindowActionPerforming`. The App lifecycle start-once tracer passed 3/3 focused tests and the
integrated Debug app build succeeded on 2026-08-26.

## Required before DONE

- A human must verify a real global chord and real device sleep/wake cycle. No hardware or
  lifecycle manual pass is claimed here.
