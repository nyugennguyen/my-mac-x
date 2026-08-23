#!/usr/bin/env swift

// THROWAWAY SPRINT 0 PROTOTYPE — public API only.
//
// This creates a LISTEN-ONLY event tap. It cannot suppress or rewrite input.
// Do not type secrets while manually testing. Nothing happens unless --listen is passed.

import CoreGraphics
import Foundation

private func describeModifiers(_ flags: CGEventFlags) -> String {
    var names: [String] = []
    if flags.contains(.maskControl) { names.append("control") }
    if flags.contains(.maskAlternate) { names.append("option") }
    if flags.contains(.maskShift) { names.append("shift") }
    if flags.contains(.maskCommand) { names.append("command") }
    return names.isEmpty ? "none" : names.joined(separator: "+")
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, _ in
    // Callback deliberately performs only tiny diagnostic work in this throwaway PoC.
    // Production must enqueue a compact value and return immediately.
    switch type {
    case .keyDown, .keyUp, .flagsChanged:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        print("type=\(type.rawValue) keyCode=\(keyCode) modifiers=\(describeModifiers(event.flags)) repeat=\(isRepeat)")
    case .tapDisabledByTimeout:
        print("OBSERVE: event tap disabled by timeout; production must re-enable safely.")
    case .tapDisabledByUserInput:
        print("OBSERVE: event tap disabled by user input.")
    default:
        break
    }

    // passUnretained is correct for the event supplied to this synchronous callback.
    return Unmanaged.passUnretained(event)
}

guard CommandLine.arguments.contains("--listen") else {
    print("Usage: event-tap-poc.swift --listen")
    print("Safety: listen-only; press Control+C in this Terminal to stop.")
    exit(EXIT_SUCCESS)
}

let observedEvents: [CGEventType] = [
    .keyDown,
    .keyUp,
    .flagsChanged,
]
let eventMask = observedEvents.reduce(CGEventMask(0)) { mask, type in
    mask | (CGEventMask(1) << type.rawValue)
}

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: eventMask,
    callback: eventTapCallback,
    userInfo: nil
) else {
    print("Could not create listen-only event tap. Record Accessibility/Input Monitoring state and macOS version.")
    exit(EXIT_FAILURE)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("Listen-only event tap active. Try Control+Space and command keys; press Control+C to stop.")
CFRunLoopRun()

