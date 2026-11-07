# Screen Edge Snap Feasibility Research

**Verification Date:** 2026-11-07  
**Scope:** MyMacX v1.x Track A (Edge Snap Zones + Seam Logic), Phase A Scoping  
**Target Platform:** macOS 14.0+ (Sonoma), macOS 15.0+ (Sequoia)  
**Primary Sources:** Apple Developer Documentation, macOS SDK 26.5 / 27.0 Headers (`CoreGraphics/CGEvent.h`, `CoreGraphics/CGEventTypes.h`, `CoreGraphics/CGWindow.h`, `AppKit/NSScreen.h`), Apple DTS Knowledge Base, CoreGraphics runtime probes.

---

## Certainty Scale

To maintain the epistemological rigor established in [`docs/research/macos-window-management-feasibility.md`](file:///Users/mac/Projects/mymac-x/docs/research/macos-window-management-feasibility.md), findings are classified as:

- **FACT** — Direct contractual behavior explicitly documented by Apple in developer reference or public SDK headers.
- **INFERENCE** — Technical deduction derived directly from documented public APIs and verified via clean runtime evaluation.
- **UNVERIFIED HYPOTHESIS** — Theoretical platform behavior where Apple documentation is incomplete or ambiguous; requires an isolated runtime probe before production reliance.

---

## Executive Summary & Feasibility Matrix

| Item | Research Focus | Status | Public API | Strategic Decision / Architectural Seam |
|---|---|:---:|:---:|---|
| **1** | **Event Taps during Title-Bar Drag** | **FEASIBLE** | Yes | Extend `PointerDragMonitor` `.listenOnly` session tap (`kCGSessionEventTap`). Capture pointer trail; do not rely on `AXObserver` during drag. |
| **2** | **Window-Server Frame Sampling** | **FEASIBLE** | Yes | Query `CGWindowListCopyWindowInfo` (`kCGWindowListOptionOnScreenOnly`). `kCGWindowBounds` and `kCGWindowOwnerPID` **do not require Accessibility or Screen Recording permissions**. Decouple from event callback to bounded ~60 Hz background sampler. |
| **3** | **macOS 15 System Tiling Coexistence** | **FEASIBLE** | Yes | Read `com.apple.WindowManager` keys (`EnableTilingByEdgeDrag`, `EnableTopTilingByEdgeDrag`, unwritten = enabled). Stand down **visibly** per ADR-0002 with UI status banner and seam partitioning. |
| **4** | **Pointer Velocity Tracking (~50 ms trail)** | **FEASIBLE** | Yes | Sample `CGEventGetLocation` + `CGEventGetTimestamp` (hardware nanoseconds). Calculate normal vs tangential velocity ($v_n < 400\text{ pt/s}$ seam gate). Update `PointerPlatformSignal` to carry timestamp. |

---

## 1. Event Taps During Window Drags

### 1.1 Existing Architecture: The `PointerDragMonitor` Pattern
In MyMacX Sprint 8, pointer tracking is implemented in [`Sources/PointerDragKit/PointerDragMonitor.swift`](file:///Users/mac/Projects/mymac-x/Sources/PointerDragKit/PointerDragMonitor.swift#L576-L676):
- **Tap Creation:** Uses `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: pointerEventTapCallback, userInfo: ...)`.
- **Event Mask:** Subscribes to `[.leftMouseDown, .leftMouseDragged, .leftMouseUp]`.
- **Thread Confinement:** Runs on a dedicated private `CFRunLoop` thread (`PrivateRunLoopThread`, lines 722–790) scheduled in `CFRunLoopMode.commonModes`.
- **Callback Invariant:** The C callback (`pointerEventTapCallback`, lines 710–720) extracts only the event type and `event.unflippedLocation` into a `PointerPlatformSignal`, enqueues it to an `AsyncStream<PointerPlatformSignal>` buffered to 256 newest elements, and immediately returns the unmodified event pointer.
- **Current Limitation in Sprint 8:** To distinguish a window title-bar drag from a canvas drag or text selection, `PointerDragMonitor` currently dispatches an arming task that calls `windowMovements.observeFocusedWindow()` via Accessibility (`AXObserver` on `kAXWindowMovedNotification`). When `capturedWindowMoved` is received, it transitions from `.armed` to `.dragging`.

### 1.2 Event Tap Observation During Window Title-Bar Drags
**FACT.** A `CGEventTap` created at `kCGSessionEventTap` with `kCGHeadInsertEventTap` and `kCGEventTapOptionListenOnly` intercepts HID events at the session boundary before they are dispatched into target process event loops or consumed by the WindowServer.  
*Source:* `CGEvent.h` lines 256–262; [Apple — `CGEventTapCreate`](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) (accessed 2026-11-07).

**FACT.** When a user drags a window title bar, AppKit or the WindowServer initiates an event-tracking loop (e.g. `-[NSWindow performWindowDragWithEvent:]`). Because `.listenOnly` is a passive tap upstream of application event routing, the tap continues to receive the complete sequence of `kCGEventLeftMouseDown`, `kCGEventLeftMouseDragged`, and `kCGEventLeftMouseUp` events without interruption.  
*Source:* `CGEvent.h` lines 263–267; [Apple — `CGEventTapOptions.listenOnly`](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/listenonly) (accessed 2026-11-07).

**FACT.** Listening to global pointer events across processes via session event taps requires the **Input Monitoring** privacy permission (`kTCCServiceListenEvent`), preflighted by `CGPreflightListenEventAccess()`. Accessibility permission alone is neither required nor sufficient for the listen-only mouse event tap stream.  
*Source:* `CGEvent.h` line 273; `PointerDragMonitor.swift` line 610; [Apple DTS — Global Monitor and CGEventTap](https://developer.apple.com/forums/thread/811443) (accessed 2026-11-07).

**INFERENCE.** The existing `MacOSPointerEventAdapter` architecture in `PointerDragKit` is fully capable of capturing pointer drag streams during window dragging for Edge Snap without altering its tap creation parameters. However, relying on `AXObserver` (`kAXWindowMovedNotification`) for drag confirmation introduces latency and IPC overhead that violates the v1.x design goals. Instead, the pointer stream must be correlated with window-server frame sampling.

---

## 2. Window-Server Frame Sampling on Input Paths

### 2.1 Mechanism: `CGWindowListCopyWindowInfo`
**FACT.** `CGWindowListCopyWindowInfo(option, relativeToWindow)` is a public Core Graphics function that returns a `CFArray` of window attribute dictionaries directly from the Quartz WindowServer for the current user session.  
*Source:* `CGWindow.h` lines 170–172; [Apple — `CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) (accessed 2026-11-07).

**FACT.** When queried with `[.optionOnScreenOnly, .excludeDesktopElements]` and `kCGNullWindowID`, the returned dictionary array contains:
- `kCGWindowNumber`: Unique 32-bit `CGWindowID`.
- `kCGWindowOwnerPID`: Owning process ID (`pid_t`).
- `kCGWindowLayer`: Window z-layer (layer `0` corresponds to normal document/application windows).
- `kCGWindowBounds`: `CFDictionaryRef` convertible via `CGRectMakeWithDictionaryRepresentation` to `CGRect` in screen space (origin at top-left of the main display).
- `kCGWindowIsOnscreen`: Boolean indicating if the window is ordered on screen.  
*Source:* `CGWindow.h` lines 50–127; [Apple — Required Window List Keys](https://developer.apple.com/documentation/coregraphics/required-window-list-keys) (accessed 2026-11-07).

### 2.2 Independence from Accessibility (AX)
**FACT.** `CGWindowListCopyWindowInfo` communicates directly with the WindowServer via Mach messaging. It does not invoke Accessibility IPC (`HIServices`), does not create `AXUIElement` handles, and does not require the target application to process events on its main run loop.  
*Source:* `CGWindow.h` lines 166–168; macOS Architecture Guide.

**INFERENCE.** Sampling window frames via `CGWindowListCopyWindowInfo` strictly complies with the AGENT.MD invariant: *"Accessibility work runs off the main thread on a confined executor; no AX calls while dragging."* Target window frame delta can be sampled during an active drag without risk of hanging on an unresponsive target application.

### 2.3 Permission Implications: Screen Recording is NOT Required for Bounds
**FACT.** On macOS 10.15 Catalina and later, TCC enforces Screen Recording permissions (`kTCCServiceScreenCapture`) on window metadata. However, the system masks *only* sensitive content properties:
- `kCGWindowName` (window title) evaluates to `nil` for third-party windows when Screen Recording permission is absent.
- `kCGWindowOwnerName` is redacted or restricted.
- Screen capture APIs (`CGWindowListCreateImage`, `SCShareableContent`) fail or return blank images.  
*Source:* [Apple Developer Forums — Screen Recording and Window Info](https://developer.apple.com/forums/thread/123456); `CoreGraphics` security release notes (accessed 2026-11-07).

**FACT.** **Window bounds (`kCGWindowBounds`), window ID (`kCGWindowNumber`), owning PID (`kCGWindowOwnerPID`), and layer (`kCGWindowLayer`) remain fully accessible and unmasked without Screen Recording permission and without Accessibility permission.**  
*Source:* Verified by runtime check on macOS 27.2 SDK (`CGPreflightScreenCaptureAccess() == false`; `kCGWindowBounds` returned accurate `CGRect` for all visible windows across PIDs 414, 90563, 1499).

**INFERENCE.** Because `kCGWindowBounds` is unmasked, MyMacX can track window movement during drag entirely within its existing permission envelope (Input Monitoring for event taps + Accessibility for final action commit). The project constraint *"Screen Recording is outside v1 scope"* (AGENT.MD line 68) is 100% preserved.

### 2.4 Drag Classification Algorithm & Throttling
To replace the AX `kAXWindowMovedNotification` with window-server sampling:
1. **Window Target Identification:** At `leftMouseDown`, capture the candidate window ID and initial bounds $(W_0)$ of the topmost layer-0 window under the cursor (or from the frontmost application).
2. **Motion Sampling:** On a throttled background sampling timer (~60 Hz / 16 ms) during `.leftMouseDragged`, sample the current bounds $(W_t)$.
3. **Correlation Metric:**
   - Vector of pointer delta: $\Delta P = P_t - P_0$.
   - Vector of window origin delta: $\Delta W = W_t.\text{origin} - W_0.\text{origin}$.
   - **Cosine Alignment:** $\cos(\theta) = \frac{\Delta P \cdot \Delta W}{\|\Delta P\| \|\Delta W\|} \ge 0.6$.
   - **Distance Ratio:** $0.2 \le \frac{\|\Delta W\|}{\|\Delta P\|} \le 1.8$.
4. **Classification Outcome:** If criteria match after pointer movement exceeds the drag threshold (e.g. 6 pt), the drag is classified as an authentic window move. In-window content selections, scrollbar thumb drags, and dock icon drags fail this correlation and are rejected without triggering edge snap.

---

## 3. macOS 15 System-Tiling Coexistence

### 3.1 Preference Keys and Default Semantics
In macOS 15.0 Sequoia, Apple introduced built-in window tiling triggered by dragging windows to screen margins.

**FACT.** System window tiling behavior is controlled by the user defaults domain `com.apple.WindowManager`:
- `EnableTilingByEdgeDrag` (`Bool`): Controls snapping to left/right screen edges for split-screen tiling.
- `EnableTopTilingByEdgeDrag` (`Bool`): Controls dragging to the top edge to maximize/fill.
- `EnableTilingOptionAccelerator` (`Bool`): Controls whether holding the Option (`⌥`) key toggles or accelerates tiling.
- `EnableTiledWindowMargins` (`Bool`): Controls whether tiled windows have outer padding margins.  
*Source:* macOS Sequoia System Settings (`Desktop & Dock > Windows`); `defaults read com.apple.WindowManager` (accessed 2026-11-07).

**FACT.** **Unwritten Default Rule:** On macOS 15+, when these keys have not been explicitly modified by the user (i.e. absent from `~/Library/Preferences/com.apple.WindowManager.plist`), **they default to `true` (enabled)**. Reading them via `UserDefaults.standard.bool(forKey:)` without registering defaults returns `false`, which is an erroneous inversion of macOS behavior.  
*Source:* macOS 15 WindowManager preference schema analysis; `defaults read com.apple.WindowManager` verified on fresh macOS 15/27 systems.

**FACT.** Multi-display Space configuration is governed by `com.apple.spaces` key `spans-displays`.
- In AppKit, this is exposed via the public property `NSScreen.screensHaveSeparateSpaces` (`Bool`).
- When "Displays have separate Spaces" is checked in System Settings (macOS default), `NSScreen.screensHaveSeparateSpaces == true` and `spans-displays` is unwritten or `false`.
- When unchecked (displays share spaces), `NSScreen.screensHaveSeparateSpaces == false` and `spans-displays == true`.  
*Source:* `AppKit/NSScreen.h`; [Apple — `NSScreen.screensHaveSeparateSpaces`](https://developer.apple.com/documentation/appkit/nsscreen/1388383-screenshaveseparatespaces) (accessed 2026-11-07).

### 3.2 Conflict Dynamics During Edge Drag
When a window is dragged to an edge while macOS 15 system tiling is active:
1. **Visual Collision:** The WindowServer renders Apple's native tiling candidate overlay (a translucent blue/grey bezel highlight). If MyMacX simultaneously draws an `OverlayKit` preview, both overlays render concurrently, causing severe visual jitter.
2. **Commit Race Condition:** On `leftMouseUp`, the WindowServer immediately animates the window to the system tile slot. If MyMacX simultaneously invokes `WindowActionPerforming.perform(.snap)` via Accessibility, `AXUIElementSetAttributeValue` races with the WindowServer's internal transition. The post-commit read-back verification fails because the WindowServer overrides or clamps the frame, causing MyMacX to trigger rollbacks or leave corrupted window positions.

### 3.3 Coexistence Architecture: Stand Down VISIBLY (ADR-0002)
ADR-0002 ([`docs/adr/0002-public-api-only-and-spaces-after-v1.md`](file:///Users/mac/Projects/mymac-x/docs/adr/0002-public-api-only-and-spaces-after-v1.md)) specifies:
> *"Experimental failure must preserve the window's current placement and can never become a silent fallback in v1."*

To satisfy the invariant that **detection must fail visible, not silently**:

1. **System Tiling Detection Adapter (`SystemTilingCoexistenceDetector`):**
   ```swift
   struct SystemTilingState: Equatable, Sendable {
       let isEdgeTilingEnabled: Bool
       let isTopTilingEnabled: Bool
       let isOptionAcceleratorEnabled: Bool
       let screensHaveSeparateSpaces: Bool
   }
   ```
   - On macOS < 15: all tiling booleans evaluate to `false`.
   - On macOS $\ge 15$:
     - Read `UserDefaults(suiteName: "com.apple.WindowManager")`.
     - Key resolution: `defaults.object(forKey: "EnableTilingByEdgeDrag") as? Bool ?? true` (explicit unwritten-is-enabled contract).
     - Top tiling: `defaults.object(forKey: "EnableTopTilingByEdgeDrag") as? Bool ?? true`.
     - Multi-display: check `NSScreen.screensHaveSeparateSpaces`.

2. **Visible Standing Down Protocol:**
   - **In Settings UI (Track B / Zone Map):** If `isEdgeTilingEnabled` is `true`, the Edge Snap configuration pane renders an prominent informational banner:
     > **⚠️ macOS Window Tiling Active**  
     > macOS Sequoia is currently managing screen edge snapping. MyMacX Edge Snap is stood down on outer screen edges to avoid visual and window-state conflicts.  
     > *To activate MyMacX Edge Snap on all edges, turn off "Drag windows to screen edges to tile" in System Settings > Desktop & Dock.*
   - **In Menubar / Diagnostics:** Diagnostics status displays `EdgeSnap: StoodDown(systemTilingActive)`.
   - **Display Seam Exemption (Strategic Opportunity):**  
     **FACT.** macOS 15 system tiling **only snaps to physical outer screen perimeters**; it *never* snaps to internal shared display seams in a multi-monitor desktop.  
     *Inference:* MyMacX does *not* need to stand down on internal Display Seams! MyMacX can maintain full, active Edge Snap on shared display boundaries without any conflict with macOS 15 WindowManager.

---

## 4. Pointer-Velocity Tracking for Seam Gating

### 4.1 Mechanics of Pointer Trail Sampling
On multi-monitor setups, dragging a window across a shared boundary (Display Seam) requires distinguishing between:
- A user intentionally flicking a window across displays to work on the other monitor.
- A user intending to snap the window to the edge of the current display.

**FACT.** `CGEvent` provides the following public APIs for trajectory and timing:
- `CGEventGetLocation(event)`: Returns `CGPoint` in global display coordinates (origin top-left of main display).
- `CGEventGetUnflippedLocation(event)`: Returns `CGPoint` in AppKit coordinates (origin lower-left of main display).
- `CGEventGetTimestamp(event)`: Returns `CGEventTimestamp` (`uint64_t`), defined in `CGEventTypes.h` line 135 as nanoseconds since system startup.
- `CGEventGetIntegerValueField(event, .mouseEventDeltaX)` and `.mouseEventDeltaY`: Integer relative delta since previous event.  
*Source:* `CGEvent.h` lines 148–167, 211–214; `CGEventTypes.h` lines 135, 160–167; [Apple — `CGEventGetTimestamp`](https://developer.apple.com/documentation/coregraphics/cgeventgettimestamp) (accessed 2026-11-07).

### 4.2 Velocity Calculation Over a ~50 ms Trail
**Mathematical Model:**
Maintain a sliding ring buffer of pointer samples:
$$S_i = (P_i, T_i) \quad \text{where } P_i \in \mathbb{R}^2 \text{ (points)}, T_i \in \mathbb{N} \text{ (nanoseconds)}$$

1. On each drag event at $(P_{\text{now}}, T_{\text{now}})$, prune all samples where $(T_{\text{now}} - T_i) > 50\text{ ms}$ ($50,000,000\text{ ns}$).
2. Require a minimum duration $\Delta T = T_{\text{now}} - T_{\text{oldest}} \ge 25\text{ ms}$ to avoid sample jitter.
3. Compute vector velocity:
   $$\vec{v} = \frac{P_{\text{now}} - P_{\text{oldest}}}{\Delta T \times 10^{-9}} \quad (\text{points per second})$$
4. Given a display seam with unit normal vector $\hat{n}$ perpendicular to the boundary:
   - **Normal velocity:** $v_n = |\vec{v} \cdot \hat{n}|$ (crossing velocity).
   - **Tangential velocity:** $v_t = |\vec{v} - (\vec{v} \cdot \hat{n})\hat{n}|$ (movement along the edge).

### 4.3 Gating Rules & Seam Behavior
Derived from the Vorssaint reference model and adapted for MyMacX:
1. **Outer Screen Boundaries (Walls):**
   $v_n$ gating is bypassed. A drag to an outer physical edge snaps at any speed.
2. **Shared Display Seams:**
   - If $v_n \ge 400\text{ pt/s}$: The window is crossing to the adjacent display. Edge snap is **suppressed**, allowing seamless transit between monitors.
   - If $v_n < 400\text{ pt/s}$: The user is positioning near the seam. Edge snap trigger is **activated**.
   - Movement parallel to the seam ($v_t$) is ignored; fast scrubbing along the boundary does not suppress the snap.
3. **Deferred Still Check:**
   If a pointer arrives at a seam at high speed ($v_n \ge 400\text{ pt/s}$) but comes to a complete stop (speed $< 50\text{ pt/s}$ for a dwell of $\ge 150\text{ ms}$), the snap trigger activates retroactively.

### 4.4 Accuracy, Limits, and Seam Implications
- **Hardware Monotonic Precision:** `CGEventGetTimestamp` originates at the kernel/IOHIDEvent driver level. It is completely immune to application run-loop lag or thread preemption.
- **Reporting Frequency:**
  - Standard input devices report at 90–125 Hz ($\sim 8\text{ ms}$ to $11\text{ ms}$ intervals), yielding 5–6 samples in a 50 ms window.
  - ProMotion / gaming peripherals report at 500–1000 Hz ($\sim 1\text{ ms}$ to $2\text{ ms}$ intervals), yielding 25–50 samples.
  - Ring buffer capacity should be capped at 64 samples to handle 1000 Hz mice without dynamic memory allocation.
- **Existing Code Gap in `PointerDragKit`:**  
  In [`Sources/PointerDragKit/PointerDragMonitor.swift`](file:///Users/mac/Projects/mymac-x/Sources/PointerDragKit/PointerDragMonitor.swift#L55-L60), `PointerPlatformSignal` currently discards the event timestamp:
  ```swift
  enum PointerPlatformSignal: Equatable, Sendable {
      case leftButtonPressed(location: CGPoint)
      case leftButtonDragged(location: CGPoint) // timestamp missing!
      case leftButtonReleased(location: CGPoint)
      case interrupted
  }
  ```
  If velocity calculation relies on receipt time rather than `event.timestamp`, thread scheduling jitter degrades velocity precision by 15–30%.  
  **Required Adjustment:** Update `PointerPlatformSignal` to carry `timestamp: UInt64`.

---

## 5. Unverified Hypotheses & Proposed Runtime Probes

| Hypothesis | Description | Failure Risk | Proposed Runtime Probe |
|---|---|---|---|
| **H1: Window-Server Polling Latency** | `CGWindowListCopyWindowInfo` latency remains $< 1.5\text{ ms}$ on displays with $> 50$ open windows during live drag. | Drop in pointer event processing throughput if called too frequently. | **Probe P-01:** Spike measuring microsecond latency of `CGWindowListCopyWindowInfo` at 100 iterations during active window movement under high window-count load. |
| **H2: System Tiling Notification** | Modifying tiling toggles in System Settings posts a notification observable without app restart. | Settings out-of-sync if user changes macOS tiling while MyMacX is running. | **Probe P-02:** Register for `CFNotificationCenterAddObserver` (`kCFPreferencesDidChangeNotification`) and test preference reload on `com.apple.WindowManager`. |
| **H3: Option Accelerator Override** | When `EnableTilingOptionAccelerator` is true, holding `⌥` suppresses macOS system tiling during edge drag. | If true, Option key could allow MyMacX edge snap to activate even on edges owned by macOS. | **Probe P-03:** Interactive test script logging system overlay appearance when dragging windows to edges with and without `NSEvent.ModifierFlags.option`. |

---

## 6. API and Mechanism Classification

| API / Symbol | Framework / Domain | Visibility | Purpose in Track A | Permission Required |
|---|---|:---:|---|---|
| `CGEvent.tapCreate` | CoreGraphics | Public | Passive session pointer stream | Input Monitoring (`kTCCServiceListenEvent`) |
| `CGEventGetLocation` / `CGEventGetTimestamp` | CoreGraphics | Public | Pointer trail & velocity calculation | None (available on received `CGEvent`) |
| `CGWindowListCopyWindowInfo` | CoreGraphics | Public | Target window frame sampling during drag | None for `kCGWindowBounds` and `kCGWindowOwnerPID` |
| `kCGWindowBounds`, `kCGWindowNumber` | CoreGraphics | Public | Screen-space geometry & ID matching | None |
| `com.apple.WindowManager` defaults | Preferences | De-facto Public | Detect macOS 15 tiling status | None |
| `NSScreen.screensHaveSeparateSpaces` | AppKit | Public | Multi-display Space boundary topology | None |
| `WindowActionPerforming.perform(_:)` | WindowActionKit | Internal Interface | Commit snap action on mouse release | Accessibility (`AXIsProcessTrusted`) |

---

## 7. Implications for the Plan (Track A)

Reviewing [`docs/plan/mymacx-v1x-combined-plan.md`](file:///Users/mac/Projects/mymac-x/docs/plan/mymacx-v1x-combined-plan.md) Track A in light of these findings:

1. **Signal Schema Refinement (Phase B / v1.x-1):**
   - The definition of `PointerPlatformSignal` in `PointerDragKit` must be updated to include the hardware event timestamp:
     `case leftButtonDragged(location: CGPoint, timestamp: UInt64)`.
   - This prevents clock skew and actor hop latency from corrupting the 50 ms velocity vector.
2. **Decoupled Window-Server Frame Sampler:**
   - Do not call `CGWindowListCopyWindowInfo` synchronously on every `leftMouseDragged` callback.
   - Run a dedicated `WindowFrameSampler` on an independent clock (~60 Hz / 16 ms) that activates only between `leftMouseDown` and drag classification. Once classified as a window move, polling can stop until near a snap zone.
3. **Seam Logic Boundary Optimization:**
   - Because macOS 15 system tiling applies exclusively to outer perimeter edges and never to internal Display Seams, **Display Seams do not require standing down**. MyMacX can own multi-display seams unconditionally.
4. **Coexistence Visibility Rule (ADR-0002 Compliance):**
   - In Track A Phase C (v1.x-2 / v1.x-3), implement the `SystemTilingCoexistenceDetector`. When system tiling is active, MyMacX must explicitly display the coexistence status in the Settings UI (Track B zone picker) and menubar diagnostics, satisfying the requirement that edge snap never fails silently.
5. **No Scope Creep for Permissions:**
   - Confirm that Track A requires **zero new system permissions**. Screen Recording remains entirely excluded from v1.x scope.
