#!/usr/bin/env swift

// THROWAWAY SPRINT 0 PROTOTYPE — public AppKit API only.
//
// Read-only: enumerates NSScreen geometry and computes candidate trigger regions.
// It does not open windows, change displays, or assume that every top safe-area inset is a notch.

import AppKit
import CoreGraphics
import Foundation

struct GeometryResult {
    let classification: String
    let notchRegion: CGRect?
    let triggerRegion: CGRect
}

func inferredGeometry(for screen: NSScreen) -> GeometryResult {
    let frame = screen.frame
    let left = screen.auxiliaryTopLeftArea
    let right = screen.auxiliaryTopRightArea
    let safeTop = screen.safeAreaInsets.top

    // When both auxiliary areas exist, the gap between them is the public-API signal
    // available for a top-center camera housing. Validate rather than hard-code its size.
    if let left, let right {
        let gapMinX = left.maxX
        let gapMaxX = right.minX
        let gapWidth = gapMaxX - gapMinX
        if safeTop > 0, gapWidth > 0, gapMinX >= frame.minX, gapMaxX <= frame.maxX {
            let notch = CGRect(
                x: gapMinX,
                y: frame.maxY - safeTop,
                width: gapWidth,
                height: safeTop
            ).intersection(frame)
            let trigger = CGRect(
                x: notch.minX - 32,
                y: max(frame.minY, notch.minY - 20),
                width: notch.width + 64,
                height: notch.height + 20
            ).intersection(frame)
            return GeometryResult(classification: "notch-candidate", notchRegion: notch, triggerRegion: trigger)
        }
    }

    // Non-notch fallback: a small top-center target, expressed in the screen's global
    // AppKit coordinate space. This remains valid for negative x/y screen origins.
    let fallbackWidth = min(180, frame.width * 0.25)
    let fallbackHeight: CGFloat = 16
    let fallback = CGRect(
        x: frame.midX - fallbackWidth / 2,
        y: frame.maxY - fallbackHeight,
        width: fallbackWidth,
        height: fallbackHeight
    ).intersection(frame)
    return GeometryResult(classification: "top-center-fallback", notchRegion: nil, triggerRegion: fallback)
}

func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
}

guard CommandLine.arguments.contains("--inspect") else {
    print("Usage: notch-geometry-poc.swift --inspect")
    print("Read-only: prints public NSScreen geometry for manual review.")
    exit(EXIT_SUCCESS)
}

let screens = NSScreen.screens
print("Screens: \(screens.count)")
for (index, screen) in screens.enumerated() {
    let result = inferredGeometry(for: screen)
    print("\nScreen \(index) displayID=\(displayID(for: screen).map(String.init) ?? "unknown")")
    print("  frame: \(screen.frame)")
    print("  visibleFrame: \(screen.visibleFrame)")
    print("  backingScaleFactor: \(screen.backingScaleFactor)")
    print("  safeAreaInsets: \(screen.safeAreaInsets)")
    print("  auxiliaryTopLeftArea: \(String(describing: screen.auxiliaryTopLeftArea))")
    print("  auxiliaryTopRightArea: \(String(describing: screen.auxiliaryTopRightArea))")
    print("  classification: \(result.classification)")
    print("  inferredNotchRegion: \(String(describing: result.notchRegion))")
    print("  triggerRegion: \(result.triggerRegion)")
    print("  triggerWithinScreen: \(screen.frame.contains(result.triggerRegion))")
}

