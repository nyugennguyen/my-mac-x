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

func inferredGeometry(
    frame: CGRect,
    safeTop: CGFloat,
    auxiliaryTopLeftArea left: CGRect?,
    auxiliaryTopRightArea right: CGRect?
) -> GeometryResult {

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

func inferredGeometry(for screen: NSScreen) -> GeometryResult {
    inferredGeometry(
        frame: screen.frame,
        safeTop: screen.safeAreaInsets.top,
        auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
        auxiliaryTopRightArea: screen.auxiliaryTopRightArea
    )
}

func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
}

func topology(of frame: CGRect, relativeTo reference: CGRect) -> String {
    if frame == reference { return "reference" }

    let horizontal = if frame.maxX <= reference.minX {
        "left"
    } else if frame.minX >= reference.maxX {
        "right"
    } else {
        "x-overlap"
    }
    let vertical = if frame.maxY <= reference.minY {
        "below"
    } else if frame.minY >= reference.maxY {
        "above"
    } else {
        "y-overlap"
    }
    return "\(horizontal),\(vertical)"
}

func runSelfTest() -> Bool {
    struct Fixture {
        let name: String
        let frame: CGRect
        let safeTop: CGFloat
        let left: CGRect?
        let right: CGRect?
        let expectedClassification: String
    }

    let fixtures = [
        Fixture(
            name: "negative-x-non-notch",
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            safeTop: 0,
            left: nil,
            right: nil,
            expectedClassification: "top-center-fallback"
        ),
        Fixture(
            name: "negative-y-non-notch",
            frame: CGRect(x: 320, y: -1080, width: 1920, height: 1080),
            safeTop: 0,
            left: nil,
            right: nil,
            expectedClassification: "top-center-fallback"
        ),
        Fixture(
            name: "negative-origin-notch-candidate",
            frame: CGRect(x: -1470, y: -200, width: 1470, height: 956),
            safeTop: 32,
            left: CGRect(x: -1470, y: 724, width: 646, height: 32),
            right: CGRect(x: -645, y: 724, width: 645, height: 32),
            expectedClassification: "notch-candidate"
        ),
        Fixture(
            name: "invalid-auxiliary-gap-falls-back",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            safeTop: 24,
            left: CGRect(x: 100, y: 676, width: 420, height: 24),
            right: CGRect(x: 500, y: 676, width: 400, height: 24),
            expectedClassification: "top-center-fallback"
        ),
    ]

    var allPassed = true
    for fixture in fixtures {
        let result = inferredGeometry(
            frame: fixture.frame,
            safeTop: fixture.safeTop,
            auxiliaryTopLeftArea: fixture.left,
            auxiliaryTopRightArea: fixture.right
        )
        let classificationPassed = result.classification == fixture.expectedClassification
        let containmentPassed = fixture.frame.contains(result.triggerRegion)
        let passed = classificationPassed && containmentPassed
        allPassed = allPassed && passed
        print(
            "Fixture \(fixture.name): \(passed ? "PASS" : "FAIL") "
                + "classification=\(result.classification) triggerWithinScreen=\(containmentPassed) "
                + "trigger=\(result.triggerRegion)"
        )
    }
    return allPassed
}

let arguments = Set(CommandLine.arguments.dropFirst())
guard arguments.contains("--inspect") || arguments.contains("--self-test") else {
    print("Usage: notch-geometry-poc.swift [--inspect] [--self-test]")
    print("Read-only: prints public NSScreen geometry for manual review.")
    exit(EXIT_SUCCESS)
}

if arguments.contains("--self-test"), !runSelfTest() {
    exit(EXIT_FAILURE)
}

guard arguments.contains("--inspect") else {
    exit(EXIT_SUCCESS)
}

let screens = NSScreen.screens
print("Screens: \(screens.count)")
let referenceFrame = NSScreen.main?.frame ?? screens.first?.frame ?? .zero
let scales = Set(screens.map(\.backingScaleFactor))
print("Mixed backing scale factors: \(scales.count > 1)")
print("Contains negative origin: \(screens.contains { $0.frame.origin.x < 0 || $0.frame.origin.y < 0 })")
for (index, screen) in screens.enumerated() {
    let result = inferredGeometry(for: screen)
    print("\nScreen \(index) displayID=\(displayID(for: screen).map(String.init) ?? "unknown")")
    print("  localizedName: \(screen.localizedName)")
    print("  isMain: \(screen == NSScreen.main)")
    print("  frame: \(screen.frame)")
    print("  visibleFrame: \(screen.visibleFrame)")
    print("  backingScaleFactor: \(screen.backingScaleFactor)")
    if let displayID = displayID(for: screen), let mode = CGDisplayCopyDisplayMode(displayID) {
        print("  displayMode: points=\(mode.width)x\(mode.height) pixels=\(mode.pixelWidth)x\(mode.pixelHeight)")
    }
    print("  topologyRelativeToMain: \(topology(of: screen.frame, relativeTo: referenceFrame))")
    print("  safeAreaInsets: \(screen.safeAreaInsets)")
    print("  auxiliaryTopLeftArea: \(String(describing: screen.auxiliaryTopLeftArea))")
    print("  auxiliaryTopRightArea: \(String(describing: screen.auxiliaryTopRightArea))")
    print("  classification: \(result.classification)")
    print("  inferredNotchRegion: \(String(describing: result.notchRegion))")
    print("  triggerRegion: \(result.triggerRegion)")
    print("  triggerWithinScreen: \(screen.frame.contains(result.triggerRegion))")
}
