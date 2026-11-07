# Prior art analysis — vorssaint-utils, GPL-3.0-or-later. Behavior re-expressed; no code reused. Cited as functional prior art; license gate resolved 2026-11-07 with clean-room reimplementation (see `docs/plan/v1x-license-gate-brief.md`).

## Overview & Methodology

This document extracts the executable behavioral specification of screen edge snapping from the prior art implementation in `vorssaint-utils` (repository: `vorssaint/vorssaint-utils`, GPL-3.0-or-later). The analysis builds upon the implementation in `Sources/Vorssaint/Services/WindowLayout/` and its unit and runtime test suites (~2,900 lines of behavioral assertions across `WindowLayoutFeatureTests.swift`, `WindowEdgeSnapRuntimeTests.swift`, `WindowEdgeSnapRestoreTests.swift`, and `WindowGestureTargetRuntimeTests.swift`).

### Clean-Room Posture
- All behaviors, geometric logic, timing cycles, and classification algorithms are re-expressed in original analytical language.
- Zero source code is copied or mechanically ported.
- Quotations are limited strictly to single-line identifier or comment citations where exact terminology is essential for cross-referencing upstream evidence.
- Each specification case is structured with:
  1. **What it does**: Exact observable behavior and operational mechanics.
  2. **Why (inferred)**: Architectural and UX rationale deduced from code structure, issue tracker citations, and commit history.
  3. **Evidence (file:line)**: Direct file and line citations from upstream source and test suites.

Cases are uniquely identified (`Z-01` to `Z-09` for Zone Model, `S-01` to `S-10` for Seam Rules, `D-01` to `D-11` for Drag Classification, `A-01` to `A-10` for Acceptance & Settle) to serve as traceability keys for upcoming implementation and test matrices in MyMacX Track A.

---

## 1. Zone Model and Fallbacks (Z-Cases)

### Z-01: Canonical 8-Zone Perimeter Topology and Corner Band Scaling
- **What it does**:
  The screen perimeter is divided into eight discrete drop zones: four straight edges (`top`, `bottom`, `left`, `right`) and four corners (`topLeft`, `topRight`, `bottomLeft`, `bottomRight`). The trigger boundary activates when the pointer comes within 12 pt (`activationDistance = 12`) of the physical screen frame.
  Corner zones occupy dynamic rectangular bands at each corner:
  - Corner width: `min(max(screenFrame.width * 0.18, 96), 180)` points.
  - Corner height: `min(max(screenFrame.height * 0.18, 80), 160)` points.
  The remaining interior edge length between the corner bands belongs to the straight edge zone.
- **Why (inferred)**:
  Static corner pixel dimensions fail on either small screens (where fixed large corners crowd out edge zones) or ultrawide displays (where fixed small corners become difficult to target). The 18% scaling with hard clamps (96–180 pt horizontal, 80–160 pt vertical) guarantees ergonomic hit targets across display aspect ratios from 16:10 laptops to 32:9 ultrawides.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:362-366` (enum declaration)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:617` (`static let activationDistance: CGFloat = 12`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:839-841` (vertical corner band clamp)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:902-904` (horizontal corner band clamp: `min(max(frame.width * 0.18, 96), 180)`)

### Z-02: Default Action Assignments
- **What it does**:
  By default, each zone maps directly to standard window placement actions:
  - `topLeft` &rarr; Top-Left Quarter (`.topLeft`)
  - `top` &rarr; Maximize (`.maximize`)
  - `topRight` &rarr; Top-Right Quarter (`.topRight`)
  - `left` &rarr; Left Half (`.leftHalf`)
  - `right` &rarr; Right Half (`.rightHalf`)
  - `bottomLeft` &rarr; Bottom-Left Quarter (`.bottomLeft`)
  - `bottom` &rarr; Bottom Half (`.bottomHalf`)
  - `bottomRight` &rarr; Bottom-Right Quarter (`.bottomRight`)
- **Why (inferred)**:
  Aligns with canonical window management expectations established by macOS tiling, Windows Snap, and third-party utilities.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:368-379` (`defaultAction` property)
  - `Tests/WindowLayoutFeatureTests.swift:791-802` (geometry validations for halves)

### Z-03: Straight Edge Multi-Area Partitioning (1 to 4 Areas)
- **What it does**:
  Straight edge zones (`top`, `bottom`, `left`, `right`) can be partitioned into 1, 2, 3, or 4 contiguous drop areas (`maximumParts = 4`). Corners are strictly single-area (`maximumParts = 1`).
  When an edge is split, default partition assignments automatically configure based on edge orientation:
  - Horizontal edges (`top`, `bottom`):
    - 1 part: default action (`maximize` or `bottomHalf`)
    - 2 parts: `leftHalf`, `rightHalf`
    - 3 parts: `leftThird`, `centerThird`, `rightThird`
    - 4 parts: `leftQuarter`, `leftMiddleQuarter`, `rightMiddleQuarter`, `rightQuarter`
  - Vertical edges (`left`, `right`):
    - 1 part: default action (`leftHalf` or `rightHalf`)
    - 2 parts: `topHalf`, `bottomHalf`
    - 3 parts: `topThird`, `middleThird`, `bottomThird`
    - 4 parts: `topQuarter`, `upperMiddleQuarter`, `lowerMiddleQuarter`, `bottomQuarter`
- **Why (inferred)**:
  Allows power users to snap into column thirds or quarters by dragging to specific segments of an edge without requiring secondary modifier keys or dedicated modal shortcuts.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:381-389` (`isHorizontalEdge`, `isVerticalEdge`, `maximumParts`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:457` (`static let maximumParts = 4`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:514-529` (`setPartCount(_:for:)`)

### Z-04: Fractional Sub-Area Selection Along Split Edges
- **What it does**:
  For an edge split into $N$ areas, the active area is selected by the pointer's normalized fractional position ($f \in [0.0, 1.0]$) along the straight edge segment (excluding corner bands):
  - For horizontal edges: $f = \frac{\text{pointer.x} - \text{minX} - \text{cornerWidth}}{\max(\text{width} - 2 \cdot \text{cornerWidth}, 1)}$
  - For vertical edges: $f = \frac{\text{maxY} - \text{cornerHeight} - \text{pointer.y}}{\max(\text{height} - 2 \cdot \text{cornerHeight}, 1)}$
  The active part index is calculated as $\text{clamp}(\lfloor f \cdot N \rfloor, 0, N - 1)$.
  As the user drags continuously along a split edge, the preview rectangle seamlessly shifts to match the sub-area currently under the cursor.
- **Why (inferred)**:
  Linear fractional indexing guarantees equal division of hit space across partitions and produces predictable visual transitions as the pointer slides along the bezel.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:494-499` (`action(for:along:)`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:877-886` (fractional calculation in `target(at:...)`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:925-942` ("sliding down a split edge previews each area in turn and drops into the one under the pointer")

### Z-05: Allowed Action Whitelist for Drop Areas
- **What it does**:
  Every action assigned to an edge or corner zone must belong to an explicitly permitted placement family:
  - Halves: `leftHalf`, `rightHalf`, `topHalf`, `bottomHalf`, `centerHalf`
  - Thirds: `leftThird`, `centerThird`, `rightThird`, `leftTwoThirds`, `rightTwoThirds`, `centerTwoThirds`, `topThird`, `middleThird`, `bottomThird`, `topTwoThirds`, `bottomTwoThirds`
  - Quarter Rows: `topQuarter`, `upperMiddleQuarter`, `lowerMiddleQuarter`, `bottomQuarter`
  - Quarter Columns: `leftQuarter`, `leftMiddleQuarter`, `rightMiddleQuarter`, `rightQuarter`
  - Sixths: `topLeftSixth`, `topCenterSixth`, `topRightSixth`, `bottomLeftSixth`, `bottomCenterSixth`, `bottomRightSixth`
  - Corners: `topLeft`, `topRight`, `bottomLeft`, `bottomRight`
  - Maximize: `maximize`, `marginMaximize`
  Relative actions, dynamic actions, or inter-display transfers (`center`, `restore`, `fullScreen`, `previousDisplay`, `nextDisplay`) are disallowed.
- **Why (inferred)**:
  Edge snap triggers require fixed, absolute screen placements that can be drawn as deterministic preview overlays before release. Actions that depend on existing window dimensions (like centering without resize) or that transition spaces/displays are ill-suited for edge-docking previews.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:413-450` (`WindowEdgeSnapPlacementGroup`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:546-549` (`accepts(_:for:)`)

### Z-06: Compact Persistence Schema and Delta Encoding
- **What it does**:
  Zone mappings are serialized as a comma-separated list of `zone=action` pairs. When an edge is partitioned, its sub-actions are joined by `+` (e.g. `right=topHalf+bottomHalf`).
  Crucially, delta encoding is applied: any zone configured with its default action (`actions == [zone.defaultAction]`) is omitted from storage. An unconfigured layout serializes to an empty string.
- **Why (inferred)**:
  Minimizes stored preferences footprint, prevents obsolete defaults from becoming hardcoded in user preferences, and allows system-wide default updates to take effect for uncustomized zones.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:482-486` (`storageValue` property)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:542-544` (`set(_:for:)`)
  - `Tests/SettingsFeatureTests.swift:259` (`DefaultsKey.windowEdgeSnapZoneActions`)

### Z-07: Resilient Fallback on Malformed, Unknown, or Future Zone Entries
- **What it does**:
  When deserializing zone configurations from string:
  1. Entries missing `=` or with invalid zone names are discarded.
  2. Action tokens unrecognized by the enum or not present in `WindowEdgeSnapPlacementGroup.placements` are rejected.
  3. Configurations exceeding the zone's `maximumParts` (e.g. >1 part for corners or >4 for edges) are rejected.
  4. If any sub-part of an edge fails validation, the entire zone entry is discarded, and the zone reverts cleanly to its built-in default action.
  5. Other valid zone entries in the same string remain fully functional.
- **Why (inferred)**:
  Prevents corrupt defaults or entries written by newer application versions (containing new zones or actions) from crashing the parser or breaking existing snapping behavior.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:464-479` (`init(storageValue:)`)

### Z-08: Per-Zone Disable Switches and Complete Standdown
- **What it does**:
  Users can disable specific zones individually. Disabled zones are persisted as a comma-separated list of zone raw values in `DefaultsKey.windowEdgeSnapDisabledZones`.
  When a pointer enters a disabled zone:
  - `target(at:...)` returns `nil`.
  - Any previously active snap preview is immediately dismissed.
  - Releasing the mouse button drops the window natively at the release coordinates without triggering any window management action or history entry.
- **Why (inferred)**:
  Enables users to disable zones that conflict with application UI (e.g. top edge near macOS menu bar / notch, or shared edges on multi-monitor configurations) while keeping other edges active.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:393-406` (`disabledZones`, `disabledZonesStorageValue`, `enabledZones`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:875` (`guard enabledZones.contains(zone) else { return nil }`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:1120-1129` ("a modifier move dropped on a switched-off zone shows no preview and stays where it was dropped")

### Z-09: macOS 15 Native Tiling Coexistence Gate
- **What it does**:
  Edge snapping evaluates macOS 15 WindowManager defaults keys:
  - `EnableTilingByEdgeDrag`
  - `EnableTilingOptionAccelerator`
  - `EnableTopTilingByEdgeDrag`
  If any of these preferences are unwritten (`nil`) or `true`, system tiling is considered enabled, and edge snapping stands down completely (`isSystemTilingEnabled == true`).
  **Exception**: If `com.apple.spaces spans-displays` is `true` (Separate Spaces disabled), macOS system tiling is inert regardless of preferences; in this specific condition, edge snapping is allowed to operate.
- **Why (inferred)**:
  In macOS 15 Sequoia, unwritten preferences default to enabled. Running an external edge snap monitor simultaneously with system tiling causes competing window animations, duplicate snapping sounds, and positioning conflicts.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:626-664` (`systemTilingKeys`, `isSystemTilingEnabled`, `systemTilingEnabled(...)`, `displaysSpan(...)`)
  - `Tests/WindowLayoutFeatureTests.swift:720-735` ("spanning displays make system tiling inert with missing or enabled keys", "separate Spaces still honor a written system tiling switch")

---

## 2. Seam Rules (S-Cases)

### S-01: Outer Display Wall Immediate Flick Snapping
- **What it does**:
  When a display edge borders physical empty space (no adjacent display lies past that edge), it is classified as an outer wall.
  Outer walls trigger snap detection at **any** pointer velocity:
  - A slow drag into the wall snaps.
  - A high-speed flick or throw against the wall triggers the preview immediately on arrival and snaps upon release.
- **Why (inferred)**:
  At an outer wall, the pointer cannot cross into another screen. The user has nowhere else to go; high cursor speed indicates deliberate intent to flick-to-dock against the screen edge.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:787-789` ("An edge with nothing beyond it is a wall that stops the pointer, so it counts at any speed...")
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:828-836` (`nearLeft`, `nearRight`, `nearTop`, `nearBottom` condition: `settledAcross || !open(...)`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:1008-1017` ("a window flung at an edge with no display past it previews on arrival and snaps when let go at once")

### S-02: Shared Display Seam Velocity Gating (400 pt/s Threshold)
- **What it does**:
  When another display exists directly across an edge (determined by geometric probe points placed 0.5 pt beyond the edge: `minX - 0.5`, `maxX + 0.5`, `minY - 0.5`, `maxY + 0.5`), the edge is classified as a shared display seam.
  A shared seam triggers snap detection **only** if the perpendicular velocity across the seam is less than or equal to 400 pt/s (`crossingSpeed = 400`):
  - For vertical seams (left/right): $|v_x| \le 400\text{ pt/s}$
  - For horizontal seams (top/bottom): $|v_y| \le 400\text{ pt/s}$
  If perpendicular velocity exceeds 400 pt/s, no snap target is returned, the preview remains hidden, and the window passes unimpeded to the adjacent display.
- **Why (inferred)**:
  Mirrors macOS pointer behavior. A user moving a window across displays typically sweeps across at high speed (>600 pt/s). Gating at 400 pt/s allows fluid multi-display window moving without accidentally docking windows at the boundary, while still allowing docking if the user intentionally slows down at the border.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:620-622` (`static let crossingSpeed: CGFloat = 400`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:801-802` (`settledAcross`, `settledUpDown`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:825-836` (probe point check `open(...)`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:1018-1027` ("a window carried through a seam at speed shows no preview and is not placed")

### S-03: Independence of Parallel Velocity Along the Seam
- **What it does**:
  Only the velocity vector normal to the seam is evaluated against `crossingSpeed`. Velocity parallel to the seam is ignored:
  - Moving up and down along a shared vertical seam ignores $v_y$.
  - Moving left and right along a shared horizontal seam ignores $v_x$.
- **Why (inferred)**:
  Users sliding a window along a side seam (e.g. moving between a half-screen dock and a corner dock) often travel quickly along the border. Evaluating total Euclidean speed would inappropriately abort the snap preview during vertical traversal.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:789-790` ("Speed along an edge never counts, so sliding from a half to a corner keeps the preview.")
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:801-802`
  - `Tests/WindowEdgeSnapRuntimeTests.swift:936-942`

### S-04: Multi-Sample Pointer Trail Buffer (50 ms Window, 20 ms Minimum Floor)
- **What it does**:
  Pointer velocity is calculated by maintaining a rolling time-stamped trail of pointer positions (`WindowEdgeSnapPointerTrail`):
  - Rolling time span: 0.05 s (`span = 0.05` / 50 ms).
  - Minimum divisor floor: 0.02 s (`minimumSpan = 0.02` / 20 ms).
  - Sample capacity: 512 entries (`capacity = 512`).
  - Velocity formula: $v = \frac{\text{point}_{\text{last}} - \text{point}_{\text{first}}}{\max(t_{\text{last}} - t_{\text{first}}, \text{minimumSpan})}$.
- **Why (inferred)**:
  Modern gaming and productivity mice report at 1,000 Hz to 8,000 Hz (intervals of 0.125–1 ms). Computing velocity across consecutive events causes extreme noise spikes. Averaging over 50 ms smooths jitter, while the 20 ms floor prevents division by near-zero time during button-release micro-movements.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:562-575` (`span`, `minimumSpan`, `stillAfter`, `capacity`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:607-613` (`velocity(at:)`)

### S-05: Raw Hardware Uptime Clock Stamping
- **What it does**:
  Trail samples are stamped using nanosecond hardware uptime (`clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` converted to seconds). When event timestamps are missing (timestamp == 0, common in synthetic test events or certain virtual mouse drivers), the system uptime clock stands in.
- **Why (inferred)**:
  CGEvent timestamps record the exact moment of physical hardware input. Using run loop delivery times would introduce scheduling latency and jitter caused by main-thread work.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1553-1563` (`seconds(of:)`, `uptimeSeconds`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:1079-1095` ("events posted with no timestamp are timed by the clock...")

### S-06: Trail Pause Reset (100 ms Still Detection)
- **What it does**:
  If the elapsed time between consecutive drag events reaches or exceeds 0.1 s (`stillAfter = 0.1` / 100 ms), the trail resets its history. It replaces previous samples with a single synthetic anchor: `[(time - minimumSpan, last.point)]`.
- **Why (inferred)**:
  If a pointer pauses on screen and then rapidly flicks, keeping older samples would dilute the flick calculation with the stationary period. Resetting after 100 ms ensures that a flick out of a resting state immediately registers as high velocity.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:570-571` (`static let stillAfter: TimeInterval = 0.1`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:585-590` (`append(_:at:)`)

### S-07: Deferred Still-Check Timer at Seams
- **What it does**:
  When a pointer arrives at a seam at high speed ($> 400$ pt/s) and suddenly stops moving, macOS stops delivering `leftMouseDragged` events. Because no new events arrive, velocity would remain calculated at the high flick speed indefinitely, and the preview would never show.
  To solve this, arriving at an edge arms a deferred timer (`scheduleEdgeSnapStillCheck`, delay 100 ms). When the timer fires:
  1. It checks whether the pointer remained motionless for $\ge 100$ ms.
  2. If motionless, velocity evaluates to `.zero`.
  3. The seam condition ($0 \le 400$) is satisfied, and the snap preview is immediately displayed without requiring further pointer motion.
- **Why (inferred)**:
  Eliminates a critical UX flaw where stopping abruptly at a multi-monitor boundary left the snap engine permanently believing the cursor was traveling at high speed.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:2023-2053` (`scheduleEdgeSnapStillCheck`, `armEdgeSnapStillCheck`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:1029-1040` ("a pointer that arrives fast and stops at a seam shows the preview once still, with no further event, and snaps")

### S-08: Still-Check Single-Timer Coalescing and Rescheduling
- **What it does**:
  Only one still-check timer is permitted to be pending at any time (`edgeSnapStillCheckPending`). When new drag events arrive while a timer is already armed, the callback re-evaluates remaining idle time: $\min(\text{stillAfter} - (\text{now} - \text{last}), \text{stillAfter})$ and extends the timer deadline.
- **Why (inferred)**:
  High-frequency mouse movement (1,000+ Hz) would otherwise enqueue thousands of dispatch timer blocks, exhausting run loop resources.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:2028-2047`
  - `Tests/WindowEdgeSnapRuntimeTests.swift:1042-1055` ("a drag keeps one still check waiting however many events it sends, and that check still finds the stop")

### S-09: Generational Invalidation of Seam Timers
- **What it does**:
  A monotonic generation counter (`edgeSnapStillCheckGeneration`) increments on every drag cancel, reset, or mouse release. When a scheduled timer block executes, it compares its captured generation with the active counter:
  `guard check == self.edgeSnapStillCheckGeneration else { return }`.
  If the generation has changed, the timer silently terminates.
- **Why (inferred)**:
  Prevents race conditions where a timer armed during a previous drag fires during a subsequent mouse interaction or after the window has already been released.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:2035-2038`
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:2056`
  - `Tests/WindowEdgeSnapRuntimeTests.swift:1057-1078` ("a release and a new press drop the waiting still check, and the next drag gets its own")

### S-10: Equidistant Seam Coordinate Tie-Breaking
- **What it does**:
  On a shared seam, the cursor coordinate mathematically lies on the boundary of both displays (distance 0 to both frames). Screens are ranked by squared distance to cursor; for equidistant screens, ownership is awarded to the screen that "holds" the point in Quartz coordinate space:
  `x >= minX && x < maxX && y > minY && y <= maxY` (in flipped AppKit coordinates).
  If still tied, system screen enumeration order is preserved.
- **Why (inferred)**:
  Prevents unstable target oscillation or flickering between monitors when a pointer rests directly on an interface boundary.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:808-814` (sorting and tie-breaking)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:925-928` (`holds(_:_:)`)

---

## 3. Drag Classification (D-Cases)

### D-01: Window vs. Pointer Motion Thresholding (2 pt Floor)
- **What it does**:
  Before evaluating drag direction or distance ratios, both window travel distance and pointer travel distance must exceed 2 points (`movementThreshold = 2`):
  - Window displacement: $d_w = \sqrt{\Delta x_w^2 + \Delta y_w^2}$
  - Pointer displacement: $d_p = \sqrt{\Delta x_p^2 + \Delta y_p^2}$
  If $d_w \le 2$, classification returns `.waiting`.
  If $d_w > 2$ but $d_p \le 2$, classification returns `.unrelated`.
- **Why (inferred)**:
  Eliminates sensor noise, micro-jitters, and transient window-server frame discrepancies before physical dragging has established a clear direction.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:631` (`private static let movementThreshold: CGFloat = 2`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:769-773` (`classify(...)`)

### D-02: Directional Vector Cosine Alignment ($\ge 0.6$)
- **What it does**:
  Computes the dot product of normalized window movement vector and pointer movement vector:
  $$\cos\theta = \frac{\Delta x_w \cdot \Delta x_p + \Delta y_w \cdot \Delta y_p}{d_w \cdot d_p}$$
  The drag is classified as `.moving` only if $\cos\theta \ge 0.6$ (corresponding to an angular deviation of $\le 53.1^\circ$).
- **Why (inferred)**:
  Confirms that the window is traveling in substantially the same direction as the cursor. An alignment $< 0.6$ rejects windows moving perpendicular to the pointer or moving in opposite directions (e.g. background window repositioning).
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:774-777`
  - `Tests/WindowLayoutFeatureTests.swift:737-742` ("edge snap confirms a window that follows the pointer")
  - `Tests/WindowLayoutFeatureTests.swift:780-784` ("an unrelated window move cannot follow a pointer going the other way")

### D-03: Distance Travel Ratio Bounds (0.2 to 1.8)
- **What it does**:
  Calculates the ratio of window displacement to pointer displacement:
  $$R = \frac{d_w}{d_p}$$
  The drag is classified as `.moving` only if $0.2 \le R \le 1.8$.
- **Why (inferred)**:
  In macOS, window server frame updates can lag pointer motion by several frames during high-DPI compositing (yielding $R \approx 0.3-0.5$), or catch up rapidly after a rendering hitch (yielding $R \approx 1.2-1.5$). The range $[0.2, 1.8]$ accommodates display pipeline lag without misclassifying stationary or erratic windows.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:776-777`
  - `Tests/WindowLayoutFeatureTests.swift:785-790` ("a short Accessibility lag still confirms the same drag")

### D-04: Complete Immunity for Content Drags
- **What it does**:
  When a user clicks and drags inside an application window (e.g. selecting text, lassoing items in Finder, scrubbing a video timeline, dragging canvas objects):
  - The window frame remains stationary ($d_w = 0 \le 2$).
  - `classify` returns `.waiting`.
  - The drag candidate never transitions to `isMoving = true`.
  - Even if the pointer is dragged all the way to a screen bezel and released, no snap preview is ever shown, no snap placement occurs, and no Accessibility calls are made on the main run loop.
- **Why (inferred)**:
  Prevents accidental snapping when users perform routine in-app drag operations that happen to terminate near screen perimeters.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:751-754` ("Content drags leave the frame still... Neither may turn into a placement just because the pointer ends at a screen edge.")
  - `Tests/WindowEdgeSnapRuntimeTests.swift:822-844` ("a drag inside an app asks that app only from the lookup queue, never from the main run loop the taps share", "a drag inside an app that ends over a snap zone never asks that app from the main run loop")
  - `Tests/WindowLayoutFeatureTests.swift:743-748` ("a content drag with a still window never becomes window snapping")

### D-05: Press-Time Native Resize Handle Rejection
- **What it does**:
  At initial `leftMouseDown`, the cursor coordinate is tested against the candidate window's bounding box:
  - Corner band: within 12 pt of any window corner (`resizeCornerDistance = 12`).
  - Edge band: within 5 pt of any window edge (`resizeEdgeDistance = 5`).
  If the press falls within these bands, the sequence is identified as a native AppKit window resize, and tracking is suppressed for the duration of the mouse press (`edgeSnapSequenceSuppressed = true`).
- **Why (inferred)**:
  Provides immediate press-time suppression, avoiding redundant background Accessibility resolves and window-server sampling loops when the user intentionally grabs a window edge to resize it.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:618-619` (`resizeCornerDistance = 12`, `resizeEdgeDistance = 5`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:733-748` (`startsAtResizeHandle(_:frame:)`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1582-1585`
  - `Tests/WindowLayoutFeatureTests.swift:767-778` ("a symmetric corner resize is rejected before movement classification", "a symmetric edge resize is rejected at the native resize handle", "the title bar stays available away from resize corners")

### D-06: Mid-Drag Native Resize Detection via Perpendicular Edge Anchoring
- **What it does**:
  If a window's dimensions change by $> 2$ pt during a drag, the engine evaluates whether the frame shares perpendicular edges with its initial state (`sharesPerpendicularEdges`):
  - Shares a vertical edge: $|\text{minX}_1 - \text{minX}_0| \le 2$ OR $|\text{maxX}_1 - \text{maxX}_0| \le 2$
  - Shares a horizontal edge: $|\text{minY}_1 - \text{minY}_0| \le 2$ OR $|\text{maxY}_1 - \text{maxY}_0| \le 2$
  If perpendicular edges remain anchored while size changes, classification outputs `.resizing`, which immediately cancels edge snap tracking.
- **Why (inferred)**:
  Catches native resizes initiated from non-standard resize areas (e.g. custom resize grips or applications with unusually wide border handles) that bypassed the press-time coordinate check.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:759-763`
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:913-919` (`sharesPerpendicularEdges`)
  - `Tests/WindowLayoutFeatureTests.swift:749-754` ("native window resizing cancels edge snapping")
  - `Tests/WindowEdgeSnapRuntimeTests.swift:631-639` ("a resize with anchored edges cancels tracking instead of restoring")

### D-07: Restoration Resize Exception for Un-Snapping Drags
- **What it does**:
  When a previously snapped or maximized window is dragged away from an edge and restores its pre-snap size, its dimensions change drastically. However, because the entire window frame travels with the cursor, it does **not** share anchored perpendicular edges with the initial frame. `classify` correctly classifies this as `.moving` rather than `.resizing`.
- **Why (inferred)**:
  Ensures that un-docking a window to restore its original size does not prematurely abort tracking or prevent re-docking to another edge in the same drag.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:753-754` ("A tiled window restoring its old size while it starts moving is still a move.")
  - `Tests/WindowLayoutFeatureTests.swift:755-766` ("a tiled window restoring its size while dragged is still a window move", "a side tile restoring only its width is still a horizontal window move")

### D-08: Consecutive Mismatch Tolerance (3-Strike Filter)
- **What it does**:
  If `classify` returns `.unrelated` during a drag, tracking is not immediately aborted. Instead, an internal counter (`mismatchCount`) increments. Tracking is cancelled only after 3 consecutive `.unrelated` evaluations (`mismatchCount >= 3`). A single `.moving` result resets the counter to 0.
- **Why (inferred)**:
  Prevents momentary frame hitches, temporary window-server dropping of frames during workspace transitions, or short mouse hitches from destroying an active drag.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1919` (`drag.mismatchCount = 0`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1925-1930` (`drag.mismatchCount += 1`, clamp at 3)

### D-09: Pure Window-Server Polling During Drag (Zero AX Overhead)
- **What it does**:
  During an active drag, window geometry is sampled up to 30 times per second (`edgeSnapSampleInterval = 0.033` s) using non-blocking window-server calls (`CGWindowListCopyWindowInfo` via `WindowServerSupport.frame(ofWindowID:)`). No Accessibility attribute reads (`kAXPositionAttribute` / `kAXSizeAttribute`) are performed on the main run loop while the mouse button is held.
- **Why (inferred)**:
  Accessibility IPC queries block synchronously on the target application's main thread. Because that application's main thread is concurrently handling window redraws for the active drag, calling AX causes catastrophic thread contention, dropped frames, and cursor stuttering. Window-server queries read directly from WindowServer shared memory without stalling the app.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1897-1909`
  - `Tests/WindowEdgeSnapRuntimeTests.swift:830-832` (`lookupQueueAX > 0 && mainAXWhileHeld == 0`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:906-908` (`previewedWhileHeld && mainAXWhileHeld == 0`)

### D-10: Off-Thread Target Resolution with Generational Guard
- **What it does**:
  Resolving the target window's `AXUIElement` is dispatched off the main thread onto a private background serial queue (`edgeSnapResolveQueue`) with a strict messaging timeout of 0.25 s (`AXUIElementSetMessagingTimeout`). When the background resolve completes, it checks `edgeSnapSequenceGeneration`; if the drag was released or cancelled while the resolve was in flight, the result is discarded.
- **Why (inferred)**:
  Initial window identification requires traversing application window lists via Accessibility. Offloading this search prevents beachballing on the main thread when dragging windows belonging to heavy or momentarily unresponsive applications.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1810-1847` (`beginEdgeSnapResolve`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1856-1861` (`AXUIElementSetMessagingTimeout(..., 0.25)`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:994-1006` ("a lookup still running when tracking is cancelled is dropped, and the next drag starts its own")

### D-11: Top-Edge 1 pt Coordinate Rewrite Trick
- **What it does**:
  On macOS 15, when a confirmed window drag reaches the top display boundary ($y \le \text{screen.minY} + 0.5$), the event tap dynamically rewrites the event's Quartz coordinate by 1 point downward:
  `event.location = CGPoint(x: point.x, y: screen.minY + 1)`.
  This modification occurs only after the drag has been definitively confirmed as a window move (`drag.isMoving == true`).
- **Why (inferred)**:
  macOS triggers Mission Control / window overview when a pointer reaches $y = 0$ during a window drag. Rewriting $y = 0$ to $y = 1$ prevents the system Mission Control gesture from firing, allowing top-edge maximize snapping to function cleanly. Applying this only to confirmed window drags ensures native menu bar interaction remains unaffected.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:717-731` (`locationAvoidingSystemTopDrag`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1533-1541`
  - `Tests/WindowEdgeSnapRuntimeTests.swift:978-992` ("a lookup landing while the window rests at an edge shows the preview and protects the next top-edge event")

---

## 4. Acceptance and Settle Behavior (A-Cases)

### A-01: Lenient Edge-Anchored Acceptance (Clamped Window Placement)
- **What it does**:
  When an action commits, the resulting window frame is read back. Rather than requiring exact pixel equality with the requested frame, `WindowLayoutGeometry.accepts` evaluates success based on edge anchors and overlap:
  1. Minimum window bounds guard: `actualRect.width > 80 && actualRect.height > 80`.
  2. Anchored edge tolerance: `anchorTolerance = 36` pt.
  3. Dimension spanning:
     - `fullWidth`: width $\ge 82\%$ of target OR both left and right edges align within 36 pt.
     - `fullHeight`: height $\ge 82\%$ of target OR both top and bottom edges align within 36 pt.
  4. Area overlap: $\frac{\text{area}(\text{actual} \cap \text{target})}{\max(1, \text{area}(\text{target}))} > 0.45$ (for halves, thirds, quarters).
  A side half is accepted if its outer edge aligns within 36 pt, it satisfies `fullHeight`, and overlap exceeds 45%.
- **Why (inferred)**:
  Many macOS apps (Terminal, Finder, Calculator, Settings) enforce minimum width/height limits or step-wise resizing (e.g. monospace character grids). Demanding exact frame equality causes clamped windows to be treated as failures, triggering unwanted rollback loops.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutSupport.swift:831-934` (`accepts(actualRect:targetRect:action:anchorTolerance:)`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:101` (`private let anchorTolerance: CGFloat = 36`)
  - `Tests/WindowLayoutFeatureTests.swift:1589-1593` ("window layout right half accepts a larger app minimum size when it spans the full height")

### A-02: Corner and Sixth Zone Acceptance (35% Overlap Floor)
- **What it does**:
  For quadrant corners (`.topLeft`, `.topRight`, `.bottomLeft`, `.bottomRight`) and sixths:
  - Both corner boundary edges must align within `anchorTolerance = 36` pt (e.g. for `topLeft`: $|\text{minX}_a - \text{minX}_t| \le 36$ AND $|\text{maxY}_a - \text{maxY}_t| \le 36$).
  - Area overlap floor is lowered to 35% (`overlap > 0.35`).
- **Why (inferred)**:
  Corner and sixth placements produce small target frames (e.g. 1/4 or 1/6 screen area). Apps with standard minimum size limits (often 600–800 pt wide) overflow these boundaries significantly. Anchoring both corner edges while requiring 35% overlap confirms the user's corner placement intent without triggering false failures.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutSupport.swift:878-917`
  - `Tests/WindowLayoutFeatureTests.swift:947-951` ("accepts a larger minimum-sized window on the same anchors")

### A-03: Maximize and Centering Overlap Floors
- **What it does**:
  - Maximize (`.maximize`): Requires high area overlap: $\text{overlap} > 0.90$.
  - Margin Maximize (`.marginMaximize`): Requires midX and midY alignment within 36 pt AND $\text{overlap} > 0.82$.
  - Centering (`.center`): Requires midX and midY alignment within 36 pt.
  - Display Transfers (`.previousDisplay`, `.nextDisplay`): Requires $\text{overlap} > 0.72$.
  - Restore & FullScreen: Explicitly return `false` (ineligible for frame-based acceptance).
- **Why (inferred)**:
  Maximize represents full-screen utilization; accepting low overlap would permit partially expanded windows to claim maximize status. Centering focuses on midpoint balance rather than boundary adherence.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutSupport.swift:918-933`
  - `Tests/WindowLayoutFeatureTests.swift:1624-1628` ("window layout margin maximize rejects a merely centered small window")

### A-04: Strict Frame Tolerance for Precision Actions (8 pt Threshold)
- **What it does**:
  Where lenient geometric acceptance is not invoked (e.g. standard precision read-backs and cycle continuations), frames are compared using `frameTolerance = 8` pt:
  $$|\Delta x| \le 8 \land |\Delta y| \le 8 \land |\Delta w| \le 8 \land |\Delta h| \le 8$$
- **Why (inferred)**:
  Accommodates macOS window drop shadows, fractional scaling point roundoffs, and sub-pixel compositing adjustments while firmly rejecting real misplacements.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutSupport.swift:373` (`static let frameTolerance: CGFloat = 8`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutSupport.swift:1048-1052` (`isClose(to:tolerance:)`)

### A-05: Deferred Settle Lifecycle (150 ms Retry Cycle)
- **What it does**:
  When an action is applied, if the immediate read-back does not match:
  1. The action does not immediately fail or rollback.
  2. It schedules an asynchronous settle verification timer for 150 ms (`scheduleSettle(..., attempt: 0)`).
  3. When attempt 0 fires:
     - If verified (via `isClose` or `accepts`), the action concludes successfully.
     - If unverified, it issues a second AX frame write attempt and schedules attempt 1 (another 150 ms).
- **Why (inferred)**:
  Resolves the upstream "issue #334" defect: many macOS applications commit Accessibility size changes asynchronously on their own run loop. Immediate read-back sees the pre-resize frame; judging failure immediately would cause the window manager to roll back the placement, leaving windows moved but never resized.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:611-634` ("Some apps commit Accessibility size changes with a short delay...")
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:668-694` (`scheduleSettle`, `continueSettle`)

### A-06: Scratch-Frame Coercion for Stuck Windows
- **What it does**:
  If attempt 1 of the deferred settle cycle also fails on a maximize-family action (`shouldUseMaximizeFallback`), the engine temporarily applies an ungapped maximize frame (`WindowLayoutGeometry.rect(for: .maximize, ...)`). Immediately following this write, it re-applies the gapped target rectangle.
- **Why (inferred)**:
  Certain stubborn applications (or apps caching prior window geometry) become stuck in intermediate constraints. Forcing an ungapped maximize resets the application's internal geometry cache, coaxing it into honoring the subsequent placement.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:695-711` ("An ungapped scratch frame that coaxes a stubborn window into resizing...")

### A-07: Rollback and Generational Safety on Final Settle Failure
- **What it does**:
  If all deferred settle attempts fail:
  1. `concludeSettle(..., success: false)` restores the original pre-snap window frame via AX.
  2. Frame history for the window is purged.
  3. Any pending settled frame record is removed.
  4. A failure result is published to the UI only if `resultGeneration` matches the current generation.
- **Why (inferred)**:
  Provides clean atomic rollback on genuine failures, while generational guarding ensures that an overdue failure callback from an earlier action does not overwrite feedback or state for a newer user action.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:724-754` (`concludeSettle`)

### A-08: Settled Frame Refresh and Manual Drag Protection (300 ms)
- **What it does**:
  When a placement is accepted leniently (e.g. clamped window), the immediate read-back may reflect an intermediate frame. A 300 ms timer (`scheduleSettledFrameRefresh`) is scheduled to re-read the settled frame.
  Crucially, the refreshed frame is accepted **only** if it moved closer to the requested frame:
  `settledFrameRefreshAccepts(actual:settled:tolerance:)`:
  $$|\text{read} - \text{requested}| \le |\text{earlier} - \text{requested}| + \text{tolerance}$$
  If the user moved or widened the window manually during the 300 ms window, the frame moved away from the target, and the refresh rejects it.
- **Why (inferred)**:
  Ensures accurate history recording for late-committing apps without allowing manual user repositions to be erroneously adopted as the application's settled placement.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutSupport.swift:440-453` (`settledFrameRefreshAccepts`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:640-666` (`scheduleSettledFrameRefresh`)
  - `Tests/WindowLayoutFeatureTests.swift:1508-1521` ("window layout settled frame refresh keeps a change by hand from becoming the settled frame")

### A-09: Snapped Window Title-Bar Drag Restoration
- **What it does**:
  When an eligible snapped window is dragged by its title bar away from its docked position (with `windowEdgeSnapRestoreOnDrag` enabled):
  1. Geometry check: `needsSizeRestore` checks if $|w_s - w_r| > 2$ or $|h_s - h_r| > 2$.
  2. Frame calculation: `restoredFrame` calculates the restored rectangle:
     - Relative title-bar grab position is preserved: $\text{ratio} = \frac{\text{pointerStart.x} - \text{minX}_s}{\text{width}_s}$.
     - Grab depth below window top is preserved: $\text{grabY} = \min(\max(\text{pointerStart.y} - \text{minY}_s, 0), \text{height}_r)$.
     - Window origin is clamped to keep the restored window within the display under the pointer.
- **Why (inferred)**:
  Replicates native macOS and Windows snap restoration mechanics, allowing users to effortlessly pull windows away from docks without having to manually resize them back to working dimensions.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowGestureSupport.swift:672-700` (`needsSizeRestore`, `restoredFrame`)
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1951-2008` (`restoreSnappedWindowIfNeeded`, `finishSnappedWindowRestore`)
  - `Tests/WindowEdgeSnapRestoreTests.swift:8-80`

### A-10: Two-Phase Size-First Drag Restoration
- **What it does**:
  During title-bar drag restoration, restoration is performed in two decoupled phases:
  - Phase 1: Set window size to `restoreSize` via AX (`setSize`).
  - Phase 2: Once the app confirms the size write (or clamps it), set window position using the confirmed size (`setPosition`).
  If the application refuses the resize, the window is **not** repositioned using the smaller requested width.
- **Why (inferred)**:
  If position was set simultaneously or before size confirmation, an application refusing the resize would cause a large window to jump across the screen based on the small origin coordinate, creating severe visual glitching.
- **Evidence**:
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1967-1970` ("Move only after the app confirms a size. A refusal must not reposition a still-large window...")
  - `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift:1991-2008` (`finishSnappedWindowRestore`)
  - `Tests/WindowEdgeSnapRuntimeTests.swift:667-681` ("a refused resize keeps the original size and confirmed position without a false restore")

---

## Traceability Cross-Reference

| Case ID | Core Metric / Threshold | Primary Upstream Source | Primary Upstream Test |
|---|---|---|---|
| **Z-01** | 8 zones; activation dist 12 pt; corner width 96–180 pt, height 80–160 pt | `WindowGestureSupport.swift:362, 617, 839` | `WindowLayoutFeatureTests.swift:791` |
| **Z-02** | Default quadrant/half/maximize actions | `WindowGestureSupport.swift:368` | `WindowLayoutFeatureTests.swift:791` |
| **Z-03** | Max 4 areas per edge; horizontal cols, vertical rows | `WindowGestureSupport.swift:381, 457, 514` | `WindowEdgeSnapRuntimeTests.swift:925` |
| **Z-04** | Fractional indexing $\lfloor f \cdot N \rfloor$ | `WindowGestureSupport.swift:494, 877` | `WindowEdgeSnapRuntimeTests.swift:936` |
| **Z-05** | Allowed action groups; excludes dynamic / display transfers | `WindowGestureSupport.swift:413, 546` | `WindowLayoutFeatureTests.swift:324` |
| **Z-06** | Comma-delimited `zone=action`, `+` partition join, default delta omission | `WindowGestureSupport.swift:482, 542` | `SettingsFeatureTests.swift:259` |
| **Z-07** | Graceful degradation of corrupted/unknown tokens to default | `WindowGestureSupport.swift:464` | `WindowEdgeSnapRuntimeTests.swift:911` |
| **Z-08** | Disabled zones list; standdown on enter | `WindowGestureSupport.swift:393, 875` | `WindowEdgeSnapRuntimeTests.swift:1120` |
| **Z-09** | `com.apple.WindowManager` coexistence check; Separate Spaces exception | `WindowGestureSupport.swift:626` | `WindowLayoutFeatureTests.swift:720` |
| **S-01** | Outer display wall snaps at any flick speed | `WindowGestureSupport.swift:787, 828` | `WindowEdgeSnapRuntimeTests.swift:1008` |
| **S-02** | Shared seam gated at $\le 400$ pt/s perpendicular speed | `WindowGestureSupport.swift:620, 801` | `WindowEdgeSnapRuntimeTests.swift:1018` |
| **S-03** | Parallel velocity along edge ignored | `WindowGestureSupport.swift:789, 801` | `WindowEdgeSnapRuntimeTests.swift:936` |
| **S-04** | 50 ms trail span, 20 ms minimum divisor floor, 512 capacity | `WindowGestureSupport.swift:562, 607` | `WindowEdgeSnapRuntimeTests.swift:1042` |
| **S-05** | Nanosecond hardware uptime stamping (`CLOCK_UPTIME_RAW`) | `WindowLayoutService.swift:1553` | `WindowEdgeSnapRuntimeTests.swift:1079` |
| **S-06** | 100 ms pause reset for flick out of rest | `WindowGestureSupport.swift:570, 585` | `WindowEdgeSnapRuntimeTests.swift:1086` |
| **S-07** | Deferred still-check timer (100 ms) when stopped at seam | `WindowLayoutService.swift:2023` | `WindowEdgeSnapRuntimeTests.swift:1029` |
| **S-08** | Single still-check timer coalescing and reschedule | `WindowLayoutService.swift:2028` | `WindowEdgeSnapRuntimeTests.swift:1042` |
| **S-09** | Generational invalidation (`edgeSnapStillCheckGeneration`) | `WindowLayoutService.swift:2035, 2056` | `WindowEdgeSnapRuntimeTests.swift:1057` |
| **S-10** | Equidistant seam tie-breaking via Quartz point ownership | `WindowGestureSupport.swift:808, 925` | `PointerDisplayLookupTests.swift:75` |
| **D-01** | Movement threshold 2 pt floor for window and pointer | `WindowGestureSupport.swift:631, 769` | `WindowLayoutFeatureTests.swift:737` |
| **D-02** | Cosine directional alignment $\ge 0.6$ ($\le 53^\circ$) | `WindowGestureSupport.swift:774` | `WindowLayoutFeatureTests.swift:737` |
| **D-03** | Distance ratio bounds $0.2 \le R \le 1.8$ | `WindowGestureSupport.swift:776` | `WindowLayoutFeatureTests.swift:785` |
| **D-04** | Content drags inside apps return `.waiting` and never snap | `WindowGestureSupport.swift:751, 770` | `WindowEdgeSnapRuntimeTests.swift:822` |
| **D-05** | Press-time resize handle rejection (12 pt corners, 5 pt borders) | `WindowGestureSupport.swift:618, 733` | `WindowLayoutFeatureTests.swift:767` |
| **D-06** | Mid-drag native resize rejection via perpendicular edge anchoring | `WindowGestureSupport.swift:759, 913` | `WindowLayoutFeatureTests.swift:749` |
| **D-07** | Tiled restore size change exempted from resize rejection | `WindowGestureSupport.swift:753` | `WindowLayoutFeatureTests.swift:755` |
| **D-08** | 3-consecutive-strike filter for `.unrelated` classification | `WindowLayoutService.swift:1924` | `WindowEdgeSnapRuntimeTests.swift:860` |
| **D-09** | Window-server polling at 30 Hz; zero AX calls during drag | `WindowLayoutService.swift:1897` | `WindowEdgeSnapRuntimeTests.swift:830` |
| **D-10** | Off-thread AX target resolution with 0.25 s timeout | `WindowLayoutService.swift:1810, 1856` | `WindowEdgeSnapRuntimeTests.swift:994` |
| **D-11** | Top-edge 1 pt coordinate rewrite for Mission Control coexistence | `WindowGestureSupport.swift:717` | `WindowEdgeSnapRuntimeTests.swift:978` |
| **A-01** | Lenient acceptance: anchor tol 36 pt, full width/height 82%, overlap 45% | `WindowLayoutSupport.swift:831` | `WindowLayoutFeatureTests.swift:1589` |
| **A-02** | Corner and sixth acceptance: 35% overlap floor | `WindowLayoutSupport.swift:878` | `WindowLayoutFeatureTests.swift:947` |
| **A-03** | Maximize $\ge 90\%$ overlap; margin maximize $\ge 82\%$; center midpoints | `WindowLayoutSupport.swift:918` | `WindowLayoutFeatureTests.swift:1624` |
| **A-04** | Frame tolerance 8 pt for precision verification | `WindowLayoutSupport.swift:373, 1048` | `WindowLayoutFeatureTests.swift:977` |
| **A-05** | Deferred settle retry cycle: 150 ms attempt 0, 150 ms attempt 1 | `WindowLayoutService.swift:611, 668` | `WindowLayoutFeatureTests.swift:1501` |
| **A-06** | Scratch-frame coercion (ungapped maximize fallback reset) | `WindowLayoutService.swift:695` | `WindowLayoutFeatureTests.swift:1508` |
| **A-07** | Atomic rollback on final failure with generational guard | `WindowLayoutService.swift:724` | `WindowEdgeSnapRuntimeTests.swift:734` |
| **A-08** | 300 ms settled frame refresh; movement-toward-target check | `WindowLayoutSupport.swift:440` | `WindowLayoutFeatureTests.swift:1508` |
| **A-09** | Title-bar drag restore preserving grab ratio and depth | `WindowGestureSupport.swift:672` | `WindowEdgeSnapRestoreTests.swift:23` |
| **A-10** | Two-phase size-first restore preventing jump glitches on refusal | `WindowLayoutService.swift:1967, 1991` | `WindowEdgeSnapRuntimeTests.swift:667` |

---

## Open Questions for the License Gate and Design

1. **License Gate Posture (Phase A Gate Item A4) — RESOLVED 2026-11-07: Option 1, clean-room reimplementation** (decision recorded in `docs/plan/v1x-license-gate-brief.md`).
   - *Option 1 (Clean-Room Reimplementation) — SELECTED*:
     Implement the specifications captured above as original Swift code residing in `TriggerGeometryKit` (pure geometry and seam mathematics) and `PointerDragKit` (drag classification and event tap handling). The resulting code shares no copyrightable expression with upstream and cites `vorssaint-utils` purely as functional prior art. MyMacX remains under its existing licensing model.
   - *Option 2 (GPL-3.0-or-later Relicense)*:
     Directly import upstream source modules. This compels open-sourcing the entire MyMacX codebase under GPL-3.0-or-later and requires distinct branding/trademark separation under upstream `TRADEMARKS.md`.
   - *Option 3 (Separately Distributed GPL Helper)*:
     Package the edge snapping daemon as an independent open-source helper process communicating via XPC. High architectural overhead with minimal benefit given that our clean-room implementation is straightforward.

2. **Architectural Seam Placement (ADR Alignment)**
   - Upstream combines trigger detection, layout geometry, overlay rendering, and Accessibility mutation inside a single monolithic service (`WindowLayoutService.swift`, 3,317 lines).
   - In MyMacX, our architectural invariants require strict separation:
     - Pure geometry (zones, split areas, seam velocity, cosine classification) belongs in `TriggerGeometryKit`.
     - Drag classification and event tap sampling belong in `PointerDragKit`.
     - Transactional lifecycle (preview, commit, cancel) belongs in `SnapInteractionKit`.
     - Visual rendering belongs in `OverlayKit`.
     - Execution and verification belong in `WindowActionPerforming` (`WindowActionKit` / `AXWindowKit`).
   - *Decision*: Does the orchestrator and domain pass agree that Edge Snap is strictly a Trigger that feeds `WindowIntent` into `WindowActionPerforming`, completely isolated from AX frame mutation?

3. **Stage Manager & Top-Drag 1 pt Rewrite Trick**
   - Upstream implements an event coordinate rewrite (`D-11`) to prevent macOS 15 from activating Mission Control when dragging to the top of the screen.
   - Is modifying event stream coordinates acceptable under MyMacX platform constraints, or should top-edge snapping stand down when macOS top-overview is active?
   - Upstream also dynamically samples WindowServer for Stage Manager recent-apps strip bounds (75 pt reservation). Should Stage Manager strip reservation be implemented in v1.x-1 or deferred to post-v1.x hardening?

4. **Scratch-Frame Coercion vs. Immediate Rollback**
   - Upstream applies an ungapped maximize frame as a scratch frame (`A-06`) to coerce stubborn applications into resizing.
   - In MyMacX, our domain invariant states: *"Commit succeeds only after Accessibility read-back verifies the resulting frame. A failed action preserves or best-effort restores the prior frame."*
   - Should scratch-frame coercion be permitted as an internal retry adapter inside `AXWindowKit`, or should MyMacX reject scratch-frame coercion in favor of clean lenient acceptance and immediate rollback?

5. **Initial Sprint Scope (Fixed 8 Zones vs. Remappable Split Partitions)**
   - The specification details multi-area partitioning (1–4 parts per edge) and custom action maps (`Z-03`, `Z-04`).
   - The combined plan proposes shipping fixed 8 zones first in v1.x-1, and introducing the remappable 1–4 partition map alongside the Settings zone picker in v1.x-3.
   - Does the case list structure provide adequate isolation to implement fixed 8 zones first without refactoring the underlying geometry kit later? (Confirmed: `maximumParts = 1` reduces the partition math to fixed defaults seamlessly).
