# W2-09 — Special-window capability fallback

Date: 2026-08-24

Status: `PASS — PROJECT-INTEGRATED TESTS GREEN`

## Scope and Interfaces

This slice stays behind the two AXWindowKit seams agreed in the Sprint 2 design:

- `FocusedWindowProviding.focusedWindow()` captures one Eligible Window with an opaque
  identity, a `WindowKind`, and current public Accessibility capabilities.
- `WindowMutationPerforming.mutate(window:to:within:)` owns the central safe placement
  policy, fresh inspection, bounded writes, read-back, retry, and rollback.

No caller receives an `AXUIElement`, raw role/subrole string, window title, parent element,
or private window state. Dialogs and sheets retain their own captured `WindowIdentity`; the
Module never resolves or retargets a parent window.

## Public Accessibility classification

`WindowKind` models `.standard`, `.dialog`, and `.sheet` using only constants documented in
the public macOS SDK:

- `kAXWindowRole` plus `kAXStandardWindowSubrole` → `.standard`;
- `kAXWindowRole` plus `kAXDialogSubrole` or `kAXSystemDialogSubrole` → `.dialog`;
- `kAXSheetRole` → `.sheet`, including providers where the optional subrole is unavailable.

Other roles/subroles fail closed. Classification never reads a title, description, document
attribute, geometry heuristic, or parent relationship. Capture and every later mutation
inspection repeat this classification for the exact retained Accessibility element.

The system Adapter continues to publish `nativeFullScreen: .unavailable`. The public SDK has
no documented Native Full Screen state attribute for another application's window, so this
slice does not infer or claim that state. Synthetic known-active state is rejected by policy
and is not treated as a placement capability.

## Central safe-placement policy

The policy derives one effective target and a supported AX-axis set after a fresh inspection:

| Current capabilities | Effective placement |
| --- | --- |
| movable + resizable | Full requested position and size |
| movable only | Preserve current size; move to the requested origin, clamped so every edge remains in the allowed frame |
| resizable only | Preserve current origin; resize only when the resulting frame remains wholly in the allowed frame |
| neither | Reject before the first write |

Capability fallback returns the verified actual frame with `constrained: true` when it cannot
fulfill the complete requested frame. A request that changes only an unsupported axis keeps
the existing typed `windowNotMovable` or `windowNotResizable` result.

The mutation Adapter revalidates kind, minimized state, and the settable status of every
requested AX attribute before performing any attribute write. It checks all requested axes
before the first write, so an unsupported second axis cannot leave a capability-induced
partial mutation. Any later write failure still uses the existing verified best-effort
rollback path.

Read-back inspection revalidates minimized state and capabilities before success or retry.
If move/resize support changes, the next retry is replanned with only the currently supported
axes. A newly minimized window rolls back without another target write. A stale identity
returns `windowDisappeared`; it is never replaced with a newly Focused Window.

## TDD evidence

Tests cross only the agreed capture and mutation Interfaces, with the scripted Accessibility
Adapter at the system seam.

1. **Window-kind tracer — red.** The first tests failed to compile because `WindowKind`,
   kind-bearing capture, and public role/subrole classification did not exist.
2. **Window-kind tracer — green.** Added role/subrole classification and exact-identity
   propagation for standard windows, dialogs, and sheets. A production Debug build passed.
3. **Capability-policy tracers — red.** The scoped run executed 38 tests with nine expected
   failures: known minimized and synthetic Native Full Screen windows were still eligible;
   move-only and resize-only full placements rejected instead of falling back; and invalid
   special-window placements reached the old failure/rollback paths.
4. **Capability-policy tracers — green.** Central planning made the same 40-test AX selection
   pass, including conservative sheet/dialog fallback, no unsupported-axis write, no-write
   rejection, and standard-window regression cases.
5. **Retry revalidation tracer — red.** Two new tests failed because a second attempt reused
   stale axes and a newly minimized read-back attempted the scripted next write instead of
   rolling back.
6. **Retry revalidation tracer — green.** Replanning after capability changes and minimized
   read-back rejection made the final AX selection pass 44/44.

The retained automated cases demonstrate:

- an Eligible Window must have at least one safe placement capability and must not be known
  minimized or in synthetic known-active Native Full Screen state;
- standard/dialog/sheet classification uses only public constants;
- a move-only sheet receives a position-only write with size preservation and safe clamping;
- a resize-only dialog receives a size-only write with origin preservation;
- an invalid resize-only origin, neither capability, and a newly minimized or stale window
  reject before target mutation;
- retry capability loss removes the now-unsupported axis from the next request;
- a rejected full write is recovered through verified rollback;
- all pre-existing standard-window verification, retry, clamp, deadline, and rollback behavior
  remains green.

## Final verification

- Scoped AXWindowKit selection: **44/44 tests passed**.
- Complete integrated XCTest suite: **102/102 tests passed**.
- Release production build with Swift 6 complete strict concurrency:
  `SWIFT_STRICT_CONCURRENCY=complete`: **passed**.
- Owned-file whitespace validation: **passed**.

## Remaining gates

- Real sheet/dialog/non-resizable/minimized behavior across Finder, Safari, Terminal, Xcode,
  Chrome, Electron, and System Settings remains the W2-12 human/device compatibility gate.
- Public Accessibility providers can change settable status between any two system calls.
  The Adapter minimizes that race by preflighting all requested axes immediately before the
  write sequence and preserves the verified rollback/error contract if a later call fails.
- Native Full Screen action observation and deadlines remain W2-10; W2-09 makes no verified
  Native Full Screen success claim.
