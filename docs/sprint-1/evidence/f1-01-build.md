# F1-01 — Xcode project foundation evidence

Status: `PASS — INDEPENDENT REVIEW COMPLETE`

## Environment

- Date: 2026-08-24
- macOS: 26.5.2 (25F84), Apple Silicon arm64
- Xcode: 26.6 (17F113)
- SDK: macOS 26.5
- Deployment target: macOS 14.0
- Swift language mode: Swift 6 with complete strict concurrency
- Signing during local verification: disabled; Hardened Runtime remains enabled in app target settings

## Project shape

- Shared scheme: `MyMacX`
- Production target: `MyMacX` (`com.apple.product-type.application`)
- Unit-test target: `MyMacXTests`
- Configurations: `Debug`, `Release`, backed by shared `.xcconfig` files
- Local bundle identifier: provisional `dev.mymacx.app`
- Initial production groups: `AppShell`, `CommandKit`

## TDD tracer

Confirmed seam/source: approved `WindowActionPerforming` contract and its stable `ActionID` domain value.

1. Red: `ActionIDTests.testActionIDRoundTripsThroughCodable` failed because `ActionID` did not exist.
2. Green: added only the `ActionID` value type required by the approved contract.
3. Result: one XCTest executed with zero failures; Codable round-trip preserves `layout.left-half` exactly.

The first red attempt also revealed missing Debug testability configuration. `ENABLE_TESTABILITY = YES` was fixed before accepting the domain-level red result.

## Verification

| Check | Result |
|---|---|
| Xcode project lists app + test targets, Debug + Release, shared scheme | Pass |
| Debug arm64 build with signing disabled | `BUILD SUCCEEDED` |
| Release arm64 build with signing disabled | `BUILD SUCCEEDED` |
| Hosted macOS unit tests | `TEST SUCCEEDED` |
| Generated Release app validates | Pass |
| Release `Info.plist` minimum macOS | 14.0 |
| Repository whitespace check | Pass after `.gitignore` cleanup |

Independent sub-agent review found no blocker, High or Medium issue. Its only Low finding was duplicate project/target ownership of the shared `.xcconfig` files, which duplicated `DEBUG=1`. The target-level references were removed; resolved Debug settings now contain one `DEBUG=1`, followed by successful Debug build, Release build and test reruns.

Build products and `.xcresult` were written under `/private/tmp` and are not repository artifacts.

## Known gaps

- Signing team, Developer ID identity, notarization and final reverse-DNS bundle ID remain human/release configuration work.
- F1-01 proves the project skeleton and test host; it does not prove menu-bar behavior, permission UX or Accessibility production behavior.
- Initial source groups are materialized only when a task begins; empty module folders are not created speculatively.
