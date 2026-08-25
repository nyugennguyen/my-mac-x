#!/usr/bin/env swift

// THROWAWAY SPRINT 0 PROTOTYPE — public API only.
//
// This creates a LISTEN-ONLY event tap. It cannot suppress or rewrite input.
// Do not type secrets while manually testing. --self-test posts one synthetic Escape
// down/up pair and stops after observing it; it never reads user text.

import CoreGraphics
import Foundation

private let isSelfTest = CommandLine.arguments.contains("--self-test")
private var observedSyntheticEscape = false

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
        if isSelfTest, type == .keyUp, keyCode == 53 {
            observedSyntheticEscape = true
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
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

guard CommandLine.arguments.contains("--listen") || isSelfTest else {
    print("Usage: event-tap-poc.swift --listen")
    print("Safe delivery check: event-tap-poc.swift --self-test")
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

if isSelfTest {
    print("Listen-only event tap active. Posting one synthetic Escape pair.")
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
} else {
    print("Listen-only event tap active. Try Control+Space and command keys; press Control+C to stop.")
}
CFRunLoopRun()

if isSelfTest {
    print(observedSyntheticEscape ? "SELF-TEST PASS: synthetic Escape observed." : "SELF-TEST FAIL: no synthetic Escape observed.")
    exit(observedSyntheticEscape ? EXIT_SUCCESS : EXIT_FAILURE)
}
