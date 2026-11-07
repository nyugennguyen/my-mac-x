# Sprint v1.x-2 Human Verification Guide: Edge Snap Runtime & Coexistence

> **IMPORTANT**: This document is a step-by-step verification protocol for human operators. In accordance with `AGENT.MD` runtime invariants and wave-3 readiness rules, physical pointer dragging, multi-display seam dynamics, and native macOS window tiling coexistence require physical verification on live hardware. The AI agent cannot and does not self-certify these gates.

---

## 1. Prerequisites & Test Setup

- **Hardware**: Mac running macOS 14+ (Sonoma or Sequoia 15+).
  - For multi-display seam tests: 2 physical monitors connected side-by-side (or 1 Mac + external display).
- **Build**: Built with `scripts/release/build-app.sh` or launched from Xcode with Accessibility & Input Monitoring permissions granted.
- **Diagnostics**: Console / Logger streaming `dev.mymacx.app` subsystem.

---

## 2. Test Cases

### 2.1 Single-Display Perimeter Zones (Z-01 to Z-08)

For each zone, click a standard resizable application window (e.g. Safari, TextEdit, Finder) title bar and drag toward the display edge.

| Test ID | Drag Path | Expected Preview | Expected Commit on Mouse-Up |
|---|---|---|---|
| **PZ-01** | Drag to left border (center Y) | Left half rectangle preview overlay appears within 12 pt of perimeter. | Window snaps to left 50% display half. |
| **PZ-02** | Drag to right border (center Y) | Right half rectangle preview overlay appears within 12 pt of perimeter. | Window snaps to right 50% display half. |
| **PZ-03** | Drag to top border (center X) | Fullscreen / maximize rectangle preview overlay appears. | Window maximizes to visible screen area (excluding menu bar/dock). |
| **PZ-04** | Drag to bottom border (center X) | Bottom half rectangle preview overlay appears. | Window snaps to bottom 50% display half. |
| **PZ-05** | Drag to top-left corner | Top-left quarter rectangle preview overlay appears. | Window snaps to top-left quadrant (50% width, 50% height). |
| **PZ-06** | Drag to top-right corner | Top-right quarter rectangle preview overlay appears. | Window snaps to top-right quadrant. |
| **PZ-07** | Drag to bottom-left corner | Bottom-left quarter rectangle preview overlay appears. | Window snaps to bottom-left quadrant. |
| **PZ-08** | Drag to bottom-right corner | Bottom-right quarter rectangle preview overlay appears. | Window snaps to bottom-right quadrant. |
| **PZ-09** | Drag into zone, then pull back 30 pt inward | Preview overlay disappears cleanly. | Window remains at mouse release location with no snap applied. |

---

### 2.2 Multi-Display Seam Gating (S-01 to S-03)

Test setup: Two monitors arranged horizontally (Display 1 on left, Display 2 on right). Shared vertical seam at `x = Display 1.maxX`.

| Test ID | Action & Velocity | Target Border | Expected Behavior |
|---|---|---|---|
| **SG-01** | **Slow Drag** (< 400 pt/s): Move window slowly toward right edge of Display 1. | Shared internal seam between Display 1 & Display 2. | **Snap Activates**: Right-half preview overlay appears on Display 1. Releasing mouse commits right-half snap. |
| **SG-02** | **Fast Flick** (>= 400 pt/s): Flick window briskly across from Display 1 into Display 2. | Shared internal seam between Display 1 & Display 2. | **Pass-Through**: Snap preview is **suppressed**. Window traverses smoothly into Display 2 without stutter or accidental snapping. |
| **SG-03** | **Outer Wall Any Speed**: Flick window briskly toward far-left outer border of Display 1. | Outer physical border. | **Snap Activates**: Left-half preview overlay appears regardless of velocity (outer walls never suppress). |

---

### 2.3 macOS Sequoia Native Tiling Coexistence (Z-09)

Test environment: macOS 15.0+ Sequoia.

#### Scenario A: Native Tiling Enabled
1. Open **System Settings → Desktop & Dock**.
2. Ensure **"Drag windows to screen edges to tile"** is **ON**.
3. Drag a window to the outer screen edges:
   - **Outer Left / Right / Top**: Native macOS tiling takes precedence. MyMacX stands down visibly:
     - No MyMacX preview overlay is shown.
     - `SystemTilingCoexistenceModel.status` reports `.stoodDown(reason: ...)`.
     - `DiagnosticsStatusSnapshot.edgeSnap` reflects `stoodDownSystemTiling`.
4. Drag a window to the **shared seam between two displays**:
   - MyMacX activates: macOS 15 native tiling does not support internal seams, so MyMacX owns shared seams unconditionally.

#### Scenario B: Native Tiling Disabled
1. In **System Settings → Desktop & Dock**, turn **"Drag windows to screen edges to tile"** **OFF**.
2. Without restarting MyMacX (live preference change notification):
   - `SystemTilingCoexistenceModel` automatically detects the preference change.
   - Drag to outer left/right/top: MyMacX edge snap previews appear and commit properly.

---

### 2.4 Clamped-App & Minimum-Size Handling (A-01 to A-05)

Use applications with hard minimum size limits (e.g. **Terminal.app**, **Calculator.app**).

| Test ID | App | Target Zone | Expected Outcome |
|---|---|---|---|
| **CA-01** | Terminal.app (default font, large min size) | Top-left quadrant | Window cannot shrink to 25% screen size, but clamps to minimum width/height. Window is anchored to top-left corner. Readback verifies lenient acceptance (`acceptedClamped`). |
| **CA-02** | Calculator.app (fixed size window) | Right half | Window cannot expand to 50% width. Window is placed and centered against the right edge. Marked as accepted/clamped. |
| **CA-03** | History & Undo | Any snapped window | Trigger Undo (via menu bar or hotkey `⌘Z`): window immediately returns to its pre-snap frame and position recorded in `HistoryKit`. |

---

## 3. Human Sign-Off Checklist

- [ ] Single-display 8-perimeter zones preview and commit cleanly.
- [ ] Pull-back from edge cancels preview without committing.
- [ ] Multi-display slow drag snaps to seam; fast flick passes through across seam without stutter.
- [ ] macOS 15 native tiling coexistence: stands down on outer edges when native tiling is ON; activates on shared seams.
- [ ] macOS 15 live preference toggle updates coexistence status without app restart.
- [ ] Clamped apps (Terminal/Calculator) anchor correctly and are treated as successful.
- [ ] Undo restores pre-snap window bounds accurately.

**Tester Signature / Date**: __________________________
