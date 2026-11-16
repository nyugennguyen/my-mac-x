# My Mac X

> A native, local-first macOS window manager built in Swift. Combines **Notch Snap** for pointer users, customizable **Hotkeys**, and a prefix-driven **Super Mode** for keyboard power users.

[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%20Sonoma%2B-black.svg?style=flat&logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat&logo=swift)](https://swift.org)
[![Universal Binary](https://img.shields.io/badge/Architecture-Universal%20(arm64%20%7C%20x86__64)-blue.svg?style=flat)](#system-requirements)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat)](./LICENSE)
[![Local-First](https://img.shields.io/badge/Privacy-100%25%20Local--First-green.svg?style=flat)](#privacy--security-invariants)

---

## Table of Contents

- [Overview](#overview)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Permissions Setup (Required Before Use)](#permissions-setup-required-before-use)
  - [1. Accessibility Permission (Mandatory)](#1-accessibility-permission-mandatory)
  - [2. Input Monitoring Permission (Conditional)](#2-input-monitoring-permission-conditional)
  - [Troubleshooting & Permission Reset](#troubleshooting--permission-reset)
- [Key Features](#key-features)
  - [Notch Snap & Edge Zones](#notch-snap--edge-zones)
  - [Keyboard Hotkeys](#keyboard-hotkeys)
  - [Super Mode](#super-mode)
  - [Multi-Display & Reconnect Stability](#multi-display--reconnect-stability)
- [Privacy & Security Invariants](#privacy--security-invariants)
- [Building from Source](#building-from-source)
- [Diagnostics & Support](#diagnostics--support)

---

## Overview

**My Mac X** is designed to feel like a missing system feature of macOS. It executes window placements directly via documented public macOS Accessibility APIs, avoiding private symbols or unsafe injection hacks.

- **Pointer First**: Drag any eligible window toward your screen's notch (or top-center on displays without a notch) to reveal the transient **Layout Chooser** and drop zones.
- **Keyboard First**: Use clean global hotkeys or enter **Super Mode**—a modal prefix key sequence that lets you orchestrate layouts without straining your hands on multi-modifier shortcuts.
- **Display Aware**: Automatically handles multi-monitor setups using reconnect-stable hardware IDs, respecting usable screen area and display seams.
- **Clean Execution**: Fast layout transitions, non-mutating placement previews, and verified frame commits with full undo/restore capabilities.

---

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later.
- **Hardware Architecture**: Apple Silicon (`arm64`) or Intel (`x86_64`) Universal binary.
- **Dependencies**: None. Pure Swift using native AppKit and SwiftUI.

---

## Installation

1. Download the latest release (`MyMacX.app` or DMG) from the releases page, or build it locally from source.
2. Drag **`MyMacX.app`** into your **`/Applications`** folder.
3. Launch **My Mac X** from `/Applications` or via Spotlight (`⌘ Space`).

> [!IMPORTANT]
> **Why permissions must be granted manually:**
> macOS standard drag-and-drop application installation does not configure system security entitlements. Because My Mac X manages third-party application windows across macOS without an invasive installer package, you must grant **Accessibility** permissions in macOS **System Settings** before the app can move or resize windows.

---

## Permissions Setup (Required Before Use)

Follow these steps immediately after copying the app to `/Applications`.

### 1. Accessibility Permission (Mandatory)

macOS requires explicit user authorization under the Transparency, Consent, and Control (TCC) framework before any app is permitted to query, inspect, move, or resize windows belonging to other applications.

#### Step-by-Step Instructions:

1. Open **System Settings** on your Mac (click the **** menu in the top-left corner > **System Settings...**).
2. In the left sidebar, navigate to **Privacy & Security**.
3. In the right pane, click **Accessibility**.
4. Check if **My Mac X** appears in the list:
   - **If My Mac X is in the list**: Turn the toggle switch next to **My Mac X** to **ON** (blue).
   - **If My Mac X is NOT in the list**:
     1. Click the **`+`** (Add) button below the application list.
     2. Authenticate with your Mac password or Touch ID when prompted.
     3. In the file picker dialog, navigate to **Applications**, select **`My Mac X.app`**, and click **Open**.
     4. Verify that the toggle switch next to **My Mac X** is switched **ON** (blue).
5. If **My Mac X** is already running, macOS will apply the permissions immediately. You can verify this inside the app:
   - Click the **My Mac X** icon in the menu bar.
   - Open **Settings** (`⌘ ,`).
   - The Accessibility indicator will display **Granted**.

---

### 2. Input Monitoring Permission (Conditional)

Input Monitoring is **not** required for standard global hotkeys. It is only required if you enable **Super Mode** with global event-tap sequence capture.

#### Step-by-Step Instructions (Only if using Super Mode Event Taps):

1. Open **System Settings** > **Privacy & Security**.
2. Click **Input Monitoring**.
3. Click the **`+`** button (or toggle the switch to **ON** if `My Mac X` is already present).
4. Select **`My Mac X.app`** from `/Applications`.
5. When macOS prompts with *"My Mac X will not be able to monitor input until it is quit"*, click **Quit & Reopen**.

---

### Troubleshooting & Permission Reset

#### Issue: Permission toggle is ON, but window snapping/moving does not work
This is a known macOS TCC bug that frequently occurs after an app is updated, recompiled, or replaced without changing its bundle identifier. macOS may cache the security signature of the previous binary.

To fix this, reset the TCC cache for My Mac X using Terminal:

1. Quit **My Mac X**.
2. Open **Terminal** (`/Applications/Utilities/Terminal.app`) and execute:
   ```bash
   # Reset Accessibility permission for My Mac X
   tccutil reset Accessibility dev.mymacx.app
   ```
3. If you also configured Input Monitoring:
   ```bash
   # Reset Input Monitoring permission for My Mac X
   tccutil reset ListenEvent dev.mymacx.app
   ```
4. Reopen **System Settings** > **Privacy & Security** > **Accessibility**, click **`+`**, re-add `/Applications/My Mac X.app`, and ensure it is toggled **ON**.
5. Launch **My Mac X** again.

---

## Key Features

### Notch Snap & Edge Zones
- **Notch Trigger**: Drag any window titlebar to the top notch (or top-center on displays without a notch) to reveal the transient **Layout Chooser**. Hover over a target region to preview, release to snap.
- **Edge Snap Zones**: Drag windows to the left, right, top, or screen corners to snap into Halves, Thirds, or Quarters.
- **Seam Gating**: Smooth crossing between multi-monitor display boundaries without unintentional triggering.

### Keyboard Hotkeys
Configure customizable shortcuts for standard window operations:
- **Halves**: Left Half, Right Half, Top Half, Bottom Half.
- **Thirds & Two-Thirds**: Left 1/3, Center 1/3, Right 1/3, Left 2/3, Right 2/3.
- **Quarters**: Top-Left, Top-Right, Bottom-Left, Bottom-Right.
- **Maximize**: Expands the window across the display's usable area (distinct from macOS Native Full Screen; keeps the window in the current Space).
- **Center**: Centers the captured window on the current display.
- **Move to Next/Previous Display**: Instantly transfer windows across physical monitors while preserving relative sizing.
- **Undo / Restore**: Revert to the window's previous geometry.

### Super Mode
A modal, prefix-driven navigation engine for keyboard enthusiasts:
1. Tap your designated **Prefix Key** (e.g. `⌥ Space`).
2. The transient **Super HUD** appears showing available placement actions.
3. Tap a single mnemonic key (e.g., `H` for left half, `L` for right half, `M` for maximize, `U` for undo).
4. Press `Escape` at any time to dismiss without moving the window.

### Multi-Display & Reconnect Stability
- Uses **Stable Display IDs** to remember screen layouts across monitor disconnections, sleep cycles, and dock reconnections.
- Windows moved between displays adapt automatically to differing resolutions and display scalings.

---

## Privacy & Security Invariants

My Mac X is strictly **local-first** and engineered with privacy as a foundational constraint:

- **No Telemetry**: No analytics, tracking tokens, or external network requests.
- **No Keystroke Logging**: The app never records typed text or raw keystroke streams.
- **No Screen Capture**: Screen Recording permission is **never** requested; the app cannot see your screen or capture screenshots.
- **No Data Inspection**: Window titles, document contents, and clipboard data are never inspected or written to logs.
- **Local Settings**: Preferences and layout histories are stored exclusively in macOS standard user preferences (`~/Library/Preferences/dev.mymacx.app.plist`).

---

## Building from Source

### Prerequisites
- macOS 14.0 Sonoma or newer
- Xcode 16.0 or newer with command-line tools installed (`xcode-select --install`)

### Build Commands

```bash
# Clone the repository
git clone https://github.com/your-org/mymac-x.git
cd mymac-x

# Fast debug build (no signing required)
xcodebuild -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# Run the complete automated test suite
xcodebuild -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" test

# Build an ad-hoc release bundle
./scripts/release/build-app.sh
```

The compiled application will be generated in `build/release/<version>/MyMacX.app`.

---

## Diagnostics & Support

If you encounter issues with a window not responding or positioning unexpectedly:

1. Click the **My Mac X** menu bar icon.
2. Select **Settings...** > **Diagnostics**.
3. Click **Copy Redacted Diagnostics Report**.
4. The report provides sanitized system status (macOS version, display topology, and permission state) without exposing open window titles, file paths, or private information.

---

## License

This project is licensed under the **GNU General Public License v3.0** (GPL-3.0). See the [LICENSE](file:///Users/mac/Projects/mymac-x/LICENSE) file for the full text.
