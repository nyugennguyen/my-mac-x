#!/usr/bin/env swift

// THROWAWAY SPRINT 0 PROTOTYPE — public API only.
//
// Safe default: no argument prints usage; --inspect performs read-only AX queries.
// Mutation requires BOTH --apply and --confirm-I-understand. Do not invoke mutation
// from automation. Focus a disposable test window and be ready to restore it.

import AppKit
import ApplicationServices
import Foundation

enum PrototypeError: Error, CustomStringConvertible {
    case accessibilityNotTrusted
    case ax(String, AXError)
    case missingAttribute(String)
    case unsupportedValue(String)

    var description: String {
        switch self {
        case .accessibilityNotTrusted:
            return "Accessibility permission is not granted. Enable it manually in System Settings."
        case let .ax(operation, error):
            return "\(operation) failed with AXError rawValue=\(error.rawValue)"
        case let .missingAttribute(attribute):
            return "Missing AX attribute: \(attribute)"
        case let .unsupportedValue(attribute):
            return "AX attribute has an unsupported value: \(attribute)"
        }
    }
}

func copyAttribute(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else { throw PrototypeError.ax("Read \(attribute)", error) }
    guard let value else { throw PrototypeError.missingAttribute(attribute) }
    return value
}

func copyElement(_ element: AXUIElement, _ attribute: String) throws -> AXUIElement {
    let value = try copyAttribute(element, attribute)
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
        throw PrototypeError.unsupportedValue(attribute)
    }
    return unsafeBitCast(value, to: AXUIElement.self)
}

func copyPoint(_ element: AXUIElement, _ attribute: String) throws -> CGPoint {
    let value = try copyAttribute(element, attribute)
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        throw PrototypeError.unsupportedValue(attribute)
    }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    var point = CGPoint.zero
    guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else {
        throw PrototypeError.unsupportedValue(attribute)
    }
    return point
}

func copySize(_ element: AXUIElement, _ attribute: String) throws -> CGSize {
    let value = try copyAttribute(element, attribute)
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        throw PrototypeError.unsupportedValue(attribute)
    }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    var size = CGSize.zero
    guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else {
        throw PrototypeError.unsupportedValue(attribute)
    }
    return size
}

func isSettable(_ element: AXUIElement, _ attribute: String) throws -> Bool {
    var result = DarwinBoolean(false)
    let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &result)
    guard error == .success else { throw PrototypeError.ax("Check settable \(attribute)", error) }
    return result.boolValue
}

func setPoint(_ point: CGPoint, on element: AXUIElement, attribute: String) throws {
    var mutablePoint = point
    guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
        throw PrototypeError.unsupportedValue(attribute)
    }
    let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
    guard error == .success else { throw PrototypeError.ax("Set \(attribute)", error) }
}

func setSize(_ size: CGSize, on element: AXUIElement, attribute: String) throws {
    var mutableSize = size
    guard let value = AXValueCreate(.cgSize, &mutableSize) else {
        throw PrototypeError.unsupportedValue(attribute)
    }
    let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
    guard error == .success else { throw PrototypeError.ax("Set \(attribute)", error) }
}

func focusedWindowViaSystemWideElement() throws -> AXUIElement {
    let system = AXUIElementCreateSystemWide()
    let application = try copyElement(system, kAXFocusedApplicationAttribute)
    return try copyElement(application, kAXFocusedWindowAttribute)
}

func focusedWindowViaFrontmostProcess() throws -> AXUIElement {
    guard let frontmost = NSWorkspace.shared.frontmostApplication else {
        throw PrototypeError.missingAttribute("NSWorkspace.frontmostApplication")
    }
    let application = AXUIElementCreateApplication(frontmost.processIdentifier)
    return try copyElement(application, kAXFocusedWindowAttribute)
}

func focusedWindow() throws -> AXUIElement {
    do {
        return try focusedWindowViaSystemWideElement()
    } catch {
        // Public fallback recommended by the Sprint 0 research. Do not enumerate
        // arbitrary windows or guess the first one when the focused window is absent.
        print("System-wide focus lookup unavailable; trying the frontmost-process fallback.")
        return try focusedWindowViaFrontmostProcess()
    }
}

func printInspection(window: AXUIElement) throws {
    let position = try copyPoint(window, kAXPositionAttribute)
    let size = try copySize(window, kAXSizeAttribute)
    let canMove = try isSettable(window, kAXPositionAttribute)
    let canResize = try isSettable(window, kAXSizeAttribute)

    print("Focused window")
    print("  position: x=\(position.x), y=\(position.y)")
    print("  size: width=\(size.width), height=\(size.height)")
    print("  AXPosition settable: \(canMove)")
    print("  AXSize settable: \(canResize)")
}

func applyClearlyGuardedTestMutation(window: AXUIElement, restoreAfterReadBack: Bool) throws {
    let originalPosition = try copyPoint(window, kAXPositionAttribute)
    let originalSize = try copySize(window, kAXSizeAttribute)
    guard try isSettable(window, kAXPositionAttribute), try isSettable(window, kAXSizeAttribute) else {
        print("Refusing mutation: the focused window is not both movable and resizable.")
        return
    }

    // Deliberately modest test delta. The prototype reads back but does not auto-restore,
    // because restore behavior itself could overwrite a user's subsequent manual move.
    let targetPosition = CGPoint(x: originalPosition.x + 24, y: originalPosition.y + 24)
    let targetSize = CGSize(width: max(320, originalSize.width - 48), height: max(240, originalSize.height - 48))
    try setSize(targetSize, on: window, attribute: kAXSizeAttribute)
    try setPoint(targetPosition, on: window, attribute: kAXPositionAttribute)

    let actualPosition = try copyPoint(window, kAXPositionAttribute)
    let actualSize = try copySize(window, kAXSizeAttribute)
    print(restoreAfterReadBack
        ? "Mutation completed; automatic restore will run after read-back."
        : "Mutation completed; restore the disposable test window manually.")
    print("  original: \(originalPosition), \(originalSize)")
    print("  requested: \(targetPosition), \(targetSize)")
    print("  read-back: \(actualPosition), \(actualSize)")

    if restoreAfterReadBack {
        // Restore position first so macOS does not clamp the original size against
        // the temporary offset from the top/left screen edges.
        try setPoint(originalPosition, on: window, attribute: kAXPositionAttribute)
        try setSize(originalSize, on: window, attribute: kAXSizeAttribute)
        let restoredPosition = try copyPoint(window, kAXPositionAttribute)
        let restoredSize = try copySize(window, kAXSizeAttribute)
        print("  restored: \(restoredPosition), \(restoredSize)")
    }
}

let argumentList = Array(CommandLine.arguments.dropFirst())
let arguments = Set(argumentList)
let wantsInspect = arguments.contains("--inspect")
let wantsApply = arguments.contains("--apply")
let confirmed = arguments.contains("--confirm-I-understand")
let restoreAfterReadBack = arguments.contains("--restore-after-readback")

func explicitRecoveryFrame(from arguments: [String]) -> CGRect? {
    guard let flagIndex = arguments.firstIndex(of: "--restore-explicit") else { return nil }
    let valueStart = arguments.index(after: flagIndex)
    guard arguments.distance(from: valueStart, to: arguments.endIndex) >= 4 else { return nil }
    let values = arguments[valueStart..<arguments.index(valueStart, offsetBy: 4)].compactMap(Double.init)
    guard values.count == 4 else { return nil }
    return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
}

let explicitRecovery = explicitRecoveryFrame(from: argumentList)

guard wantsInspect || wantsApply || explicitRecovery != nil else {
    print("Usage: accessibility-window-poc.swift --inspect")
    print("Mutation (manual test only): --apply --confirm-I-understand [--restore-after-readback]")
    print("Recovery: --restore-explicit x y width height --confirm-I-understand")
    exit(EXIT_SUCCESS)
}

guard AXIsProcessTrusted() else {
    // Intentionally do not trigger a permission prompt; onboarding UX is outside this PoC.
    print(PrototypeError.accessibilityNotTrusted)
    exit(EXIT_FAILURE)
}

do {
    let window = try focusedWindow()
    try printInspection(window: window)
    if let explicitRecovery {
        guard confirmed else {
            print("Refusing explicit recovery: add --confirm-I-understand.")
            exit(EXIT_FAILURE)
        }
        try setPoint(explicitRecovery.origin, on: window, attribute: kAXPositionAttribute)
        try setSize(explicitRecovery.size, on: window, attribute: kAXSizeAttribute)
        let restoredPosition = try copyPoint(window, kAXPositionAttribute)
        let restoredSize = try copySize(window, kAXSizeAttribute)
        print("Explicit recovery read-back: \(restoredPosition), \(restoredSize)")
        exit(EXIT_SUCCESS)
    }
    if wantsApply {
        guard confirmed else {
            print("Refusing mutation: add --confirm-I-understand after reading the safety notes.")
            exit(EXIT_FAILURE)
        }
        try applyClearlyGuardedTestMutation(window: window, restoreAfterReadBack: restoreAfterReadBack)
    }
} catch {
    print("Prototype failed: \(error)")
    exit(EXIT_FAILURE)
}
