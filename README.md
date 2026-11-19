# My Mac X

> A native, local-first macOS window manager built in Swift. Combines **Notch Snap** for pointer users, customizable **Hotkeys**, and a prefix-driven **Super Mode** for keyboard power users.

[![Latest Release](https://img.shields.io/github/v/release/nyugennguyen/my-mac-x?color=blue&label=Release)](https://github.com/nyugennguyen/my-mac-x/releases)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%20Sonoma%2B-black.svg?style=flat&logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat&logo=swift)](https://swift.org)
[![Universal Binary](https://img.shields.io/badge/Architecture-Universal%20(arm64%20%7C%20x86__64)-blue.svg?style=flat)](#system-requirements)
[![Tests: 634 Passing](https://img.shields.io/badge/Tests-634%20Passing-brightgreen.svg?style=flat)](#building-from-source)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=flat)](./LICENSE)
[![Local-First](https://img.shields.io/badge/Privacy-100%25%20Local--First-green.svg?style=flat)](#privacy--security-invariants)

---

## Table of Contents

- [Overview](#overview)
- [What's New in v0.1.1](#whats-new-in-v011)
- [System Requirements](#system-requirements)
- [Installation & First Run](#installation--first-run)
- [Permissions Setup](#permissions-setup)
  - [Open Design Onboarding (Recommended)](#open-design-onboarding-recommended)
  - [Manual Permission Configuration](#manual-permission-configuration)
  - [Troubleshooting & Permission Reset](#troubleshooting--permission-reset)
- [Key Features](#key-features)
  - [Notch Snap & Edge Zones](#notch-snap--edge-zones)
  - [Keyboard Hotkeys](#keyboard-hotkeys)
  - [Super Mode](#super-mode)
  - [First-Launch Onboarding Window](#first-launch-onboarding-window)
  - [Multi-Display & Reconnect Stability](#multi-display--reconnect-stability)
- [Privacy & Security Invariants](#privacy--security-invariants)
- [Building from Source](#building-from-source)
- [Diagnostics & Support](#diagnostics--support)
- [License](#license)

---

## Overview

**My Mac X** is designed to feel like a missing system feature of macOS. It executes window placements directly via documented public macOS Accessibility APIs, avoiding private symbols or unsafe injection hacks.

- **Pointer First**: Drag any eligible window toward your screen's notch (or top-center on displays without a notch) to reveal the transient **Layout Chooser** and drop zones.
- **Keyboard First**: Use clean global hotkeys or enter **Super Mode**—a modal prefix key sequence that lets you orchestrate layouts without straining your hands on multi-modifier shortcuts.
- **Display Aware**: Automatically handles multi-monitor setups using reconnect-stable hardware IDs, respecting usable screen area and display seams.
- **Clean Execution**: Fast layout transitions, non-mutating placement previews, and verified frame commits with full undo/restore capabilities.

---

## What's New in v0.1.1

- **First-Launch Permission Onboarding (Open Design)**: Replaces legacy modal alert dialogs with a modern, frameless 580×560 pt native macOS window featuring subtle material vibrancy, rounded interactive cards, and drag-by-background support.
- **Dual Permission Guidance**: Dedicated visual cards for both **Accessibility** and **Input Monitoring** permissions with live status badges (`Granted` vs `Required` / `Recommended`), plain-English purpose explanations, and 1-click deep-linking to macOS System Settings.
- **Live Auto-Refresh**: Dynamic state observers and active-application notifications update permission badges in real time as soon as you toggle them in System Settings—no application restart required.
- **Privacy & Security Trust Guarantee**: Clear, upfront callout ensuring all operations remain local-first, offline, and privacy-preserving with zero logging of typed text, keystrokes, window titles, or screen content.
- **Full Test Suite Verification**: 634 unit and integration tests passing on macOS 14/15 runner matrix with complete Swift 6 concurrency compliance.

---

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later.
- **Hardware Architecture**: Apple Silicon (`arm64`) or Intel (`x86_64`) Universal binary.
- **Dependencies**: None. Pure Swift using native AppKit and SwiftUI.

---

## Installation & First Run

1. Download the latest release (`MyMacX-0.1.1.dmg` or `MyMacX-0.1.1.zip`) from the [Releases page](https://github.com/nyugennguyen/my-mac-x/releases).
2. Open the DMG and drag **`MyMacX.app`** into your **`/Applications`** folder.
3. Launch **My Mac X** from `/Applications` or via Spotlight (`⌘ Space`).
4. On first launch, the **Open Design Onboarding Window** will guide you through granting the necessary permissions.

---

## Permissions Setup

### Open Design Onboarding (Recommended)

When My Mac X starts for the first time without permissions, it presents the **First-Launch Onboarding Window**:

1. **Accessibility Permission (Required)**: Click **Grant Access** (or **Open Settings**) to open macOS **System Settings > Privacy & Security > Accessibility**. Toggle **My Mac X** to **ON**. The badge in the onboarding window automatically switches to **Granted**.
2. **Input Monitoring Permission (Recommended for Super Mode)**: Click **Grant Access** to configure event taps for prefix sequence capture.
3. Once Accessibility is granted, click **Get Started** to start using My Mac X immediately.

---

### Manual Permission Configuration

If you prefer to configure permissions manually:

#### 1. Accessibility Permission (Mandatory)
macOS requires explicit authorization under the Transparency, Consent, and Control (TCC) framework before any app can inspect, move, or resize third-party application windows.

1. Open **System Settings** > **Privacy & Security** > **Accessibility**.
2. Ensure the toggle next to **My Mac X** is switched **ON** (blue).
3. If My Mac X is not listed:
   - Click the **`+`** (Add) button below the list.
   - Authenticate with Touch ID or your administrator password.
   - Select `/Applications/My Mac X.app` and click **Open**.
   - Verify the toggle is **ON**.

#### 2. Input Monitoring Permission (Conditional)
Only required if you use **Super Mode** with global event-tap sequence capture (standard hotkeys do not require Input Monitoring).

1. Open **System Settings** > **Privacy & Security** > **Input Monitoring**.
2. Click the **`+`** button (or toggle **ON** if already present).
3. Select `/Applications/My Mac X.app`.
4. When prompted by macOS, select **Quit & Reopen** (or restart My Mac X).

---

### Troubleshooting & Permission Reset

#### Issue: Permission toggle is ON, but window snapping/moving does not work
This occurs if macOS TCC caches a previous binary signature after recompiling or updating without changing the bundle ID.

Reset the TCC cache for My Mac X using Terminal:

```bash
# Reset Accessibility permission for My Mac X
tccutil reset Accessibility dev.mymacx.app

# Reset Input Monitoring permission for My Mac X (if configured)
tccutil reset ListenEvent dev.mymacx.app
```

Then re-open **System Settings** > **Privacy & Security** > **Accessibility**, re-enable **My Mac X**, and relaunch the app.

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
1. Tap your designated **Prefix Key** (e.g., `⌥ Space`).
2. The transient **Super HUD** appears showing available placement actions.
3. Tap a single mnemonic key (e.g., `H` for left half, `L` for right half, `M` for maximize, `U` for undo).
4. Press `Escape` at any time to dismiss without moving the window.

### First-Launch Onboarding Window
- **Frameless Native Window**: Clean 580×560 pt canvas with material vibrancy and drag-by-background capability.
- **Live Status Badges**: Automatically updates from `Required` to `Granted` via real-time notifications as soon as you toggle settings.
- **Privacy Trust Banner**: Clear confirmation of local-first execution and zero data collection.

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
git clone https://github.com/nyugennguyen/my-mac-x.git
cd my-mac-x

# Fast debug build (no signing required)
xcodebuild -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# Run the complete automated test suite (634 tests)
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

This project is licensed under the **GNU General Public License v3.0** (GPL-3.0). See the [LICENSE](./LICENSE) file for the full text.
