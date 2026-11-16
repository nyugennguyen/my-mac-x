// MyMacX
// Copyright (C) 2026 NyugenNguyen
//
// This program is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the LICENSE file for details.

import AppKit
import ApplicationServices
import CoreFoundation

/// Accessibility Adapter backed exclusively by documented public macOS functions and constants.
///
/// The actor confines every `AXUIElement`. Only opaque identity plus content-free geometry
/// and capability values leave this Adapter.
actor SystemWindowAdapter: AccessibilityWindowAdapting,
        AccessibilityWindowMutationAdapting,
        NativeFullScreenAccessibilityAdapting,
        PointerDragWindowMovementAdapting,
        CapturedWindowApplicationIdentifying {
    /// Bounds every synchronous public AX message made by this Adapter.
    static let messagingTimeoutSeconds: Float = 1
    static let shared = SystemWindowAdapter()

    private static let identityCacheLimit = 64

    private enum AXRead<Value> {
        case success(Value)
        case failure(AXError)
    }

    private var identityCache = WindowIdentityCache<AXUIElement>(
        capacity: identityCacheLimit,
        areEquivalent: { CFEqual($0, $1) }
    )
    private let movementRunLoop = AXMovementRunLoopThread(
        name: "MyMacX.PointerAXObserver"
    )
    private var movementObserver: AXObserver?
    private var movementObservedWindow: AXUIElement?
    private var movementSource: CFRunLoopSource?
    private var movementCallbackBox: SystemAXMovementCallbackBox?

    func captureFocusedWindow() -> AccessibilityWindowCapture {
        guard AXIsProcessTrusted() else {
            return .failure(.permissionRequired)
        }

        let focusedWindow: AXUIElement
        switch resolveFocusedWindow() {
        case .success(let window):
            focusedWindow = window
        case .failure(let error):
            return .failure(map(error))
        }

        var processID: pid_t = 0
        if AXUIElementGetPid(focusedWindow, &processID) == .success, processID == getpid() {
            return .unsupported
        }

        switch configureMessagingTimeout(on: focusedWindow) {
        case .success:
            break
        case .failure(let error):
            return .failure(map(error))
        }

        let kind: WindowKind
        switch copyWindowKind(from: focusedWindow) {
        case .success(let value):
            kind = value
        case .failure(.attributeUnsupported), .failure(.noValue):
            return .unsupported
        case .failure(let error):
            return .failure(map(error))
        }

        let isMovable: Bool
        switch isAttributeSettable(kAXPositionAttribute as CFString, on: focusedWindow) {
        case .success(let value):
            isMovable = value
        case .failure(let error):
            return .failure(map(error))
        }

        let isResizable: Bool
        switch isAttributeSettable(kAXSizeAttribute as CFString, on: focusedWindow) {
        case .success(let value):
            isResizable = value
        case .failure(let error):
            return .failure(map(error))
        }

        let minimized: WindowMinimizedState
        switch copyMinimizedState(from: focusedWindow) {
        case .success(let value):
            minimized = value
        case .failure(let error):
            return .failure(map(error))
        }

        return .candidate(
            AccessibilityWindowCandidate(
                identity: identityCache.identity(for: focusedWindow),
                kind: kind,
                capabilities: WindowCapabilities(
                    isMovable: isMovable,
                    isResizable: isResizable,
                    minimized: minimized,
                    nativeFullScreen: .unavailable
                )
            )
        )
    }

    /// Registers movement observation on the exact element entered into this Adapter's identity
    /// cache. Actor serialization keeps resolution, identity lookup, and notification registration
    /// atomic with respect to all other window captures.
    func observeFocusedWindow() -> PointerDragWindowObservationResult {
        stopObserving()

        let candidate: AccessibilityWindowCandidate
        switch captureFocusedWindow() {
        case .candidate(let value):
            candidate = value
        case .unsupported:
            return .unavailable(.noEligibleWindow)
        case .failure(let failure):
            return .unavailable(mapObservation(failure))
        }
        guard candidate.capabilities.minimized != .active,
              candidate.capabilities.isMovable || candidate.capabilities.isResizable,
              let window = identityCache.element(for: candidate.identity)
        else {
            return .unavailable(.noEligibleWindow)
        }

        var processID: pid_t = 0
        let processError = AXUIElementGetPid(window, &processID)
        guard processError == .success, processID > 0 else {
            return .unavailable(mapObservation(processError))
        }

        var createdObserver: AXObserver?
        let createError = AXObserverCreate(
            processID,
            systemAXMovementObserverCallback,
            &createdObserver
        )
        guard createError == .success, let createdObserver else {
            return .unavailable(mapObservation(createError))
        }

        let channel = AsyncStream.makeStream(
            of: WindowIdentity.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let box = SystemAXMovementCallbackBox(
            window: candidate.identity,
            continuation: channel.continuation
        )
        let retainedBox = Unmanaged.passRetained(box)
        let addError = AXObserverAddNotification(
            createdObserver,
            window,
            kAXMovedNotification as CFString,
            retainedBox.toOpaque()
        )
        guard addError == .success else {
            retainedBox.release()
            channel.continuation.finish()
            return .unavailable(mapObservation(addError))
        }

        channel.continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.stopObserving()
            }
        }

        let source = AXObserverGetRunLoopSource(createdObserver)
        movementRunLoop.add(source)
        movementObserver = createdObserver
        movementObservedWindow = window
        movementSource = source
        movementCallbackBox = box
        return .observing(window: candidate.identity, movements: channel.stream)
    }

    func stopObserving() {
        if let movementObserver, let movementObservedWindow {
            AXObserverRemoveNotification(
                movementObserver,
                movementObservedWindow,
                kAXMovedNotification as CFString
            )
        }
        if let movementSource {
            movementRunLoop.remove(movementSource)
        }
        if let box = movementCallbackBox {
            box.finish()
            Unmanaged.passUnretained(box).release()
            movementCallbackBox = nil
        }
        movementSource = nil
        movementObservedWindow = nil
        movementObserver = nil
    }

    func inspectWindow(_ identity: WindowIdentity) -> AccessibilityWindowInspectionResult {
        guard AXIsProcessTrusted() else {
            return .failure(.permissionRequired)
        }
        guard let window = identityCache.element(for: identity) else {
            return .failure(.windowDisappeared)
        }

        var processID: pid_t = 0
        if AXUIElementGetPid(window, &processID) == .success, processID == getpid() {
            return .failure(.rejected)
        }

        switch configureMessagingTimeout(on: window) {
        case .success:
            break
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        let kind: WindowKind
        switch copyWindowKind(from: window) {
        case .success(let value):
            kind = value
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        let position: CGPoint
        switch copyPointAttribute(kAXPositionAttribute as CFString, from: window) {
        case .success(let value):
            position = value
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        let size: CGSize
        switch copySizeAttribute(kAXSizeAttribute as CFString, from: window) {
        case .success(let value):
            size = value
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        let isMovable: Bool
        switch isAttributeSettable(kAXPositionAttribute as CFString, on: window) {
        case .success(let value):
            isMovable = value
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        let isResizable: Bool
        switch isAttributeSettable(kAXSizeAttribute as CFString, on: window) {
        case .success(let value):
            isResizable = value
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        let minimized: WindowMinimizedState
        switch copyMinimizedState(from: window) {
        case .success(let value):
            minimized = value
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        return .available(
            AccessibilityWindowInspection(
                frame: CGRect(origin: position, size: size),
                kind: kind,
                capabilities: WindowCapabilities(
                    isMovable: isMovable,
                    isResizable: isResizable,
                    minimized: minimized,
                    nativeFullScreen: .unavailable
                )
            )
        )
    }

    /// Resolves only the owning bundle identifier for the exact cached window identity.
    /// Both APIs used here are public; no title or document metadata is read.
    func bundleIdentifier(for identity: WindowIdentity) -> String? {
        guard let window = identityCache.element(for: identity) else { return nil }

        var processID: pid_t = 0
        guard AXUIElementGetPid(window, &processID) == .success, processID > 0 else {
            return nil
        }
        return NSRunningApplication(processIdentifier: processID)?.bundleIdentifier
    }

    func writeFrame(
        _ request: AccessibilityFrameWriteRequest,
        to identity: WindowIdentity
    ) -> AccessibilityWindowWriteResult {
        guard AXIsProcessTrusted() else {
            return .failure(.permissionRequired)
        }
        guard let window = identityCache.element(for: identity) else {
            return .failure(.windowDisappeared)
        }

        var processID: pid_t = 0
        if AXUIElementGetPid(window, &processID) == .success, processID == getpid() {
            return .failure(.rejected)
        }

        switch configureMessagingTimeout(on: window) {
        case .success:
            break
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        switch copyWindowKind(from: window) {
        case .success:
            break
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        switch copyMinimizedState(from: window) {
        case .success(.active):
            return .failure(.rejected)
        case .success(.inactive), .success(.unavailable):
            break
        case .failure(let error):
            return .failure(mapOperation(error))
        }

        if request.axes.contains(.position) {
            switch isAttributeSettable(kAXPositionAttribute as CFString, on: window) {
            case .success(true):
                break
            case .success(false):
                return .failure(.rejected)
            case .failure(let error):
                return .failure(mapOperation(error))
            }
        }
        if request.axes.contains(.size) {
            switch isAttributeSettable(kAXSizeAttribute as CFString, on: window) {
            case .success(true):
                break
            case .success(false):
                return .failure(.rejected)
            case .failure(let error):
                return .failure(mapOperation(error))
            }
        }

        let frame = request.frame.cgRect
        for attribute in AXFrameWriteOrdering.attributes(
            for: request.mode,
            axes: request.axes
        ) {
            let write: AXRead<Void>
            switch attribute {
            case .position:
                write = setPosition(frame.origin, on: window)
            case .size:
                write = setSize(frame.size, on: window)
            }

            switch write {
            case .success:
                continue
            case .failure(let error):
                return .failure(mapOperation(error))
            }
        }
        return .accepted
    }

    func requestNativeFullScreen(
        for identity: WindowIdentity
    ) -> NativeFullScreenRequestResult {
        guard AXIsProcessTrusted() else {
            return .accessibilityPermissionRequired
        }
        guard let window = identityCache.element(for: identity) else {
            return .windowDisappeared
        }

        switch configureMessagingTimeout(on: window) {
        case .success:
            break
        case .failure(let error):
            return mapNativeFullScreenRequest(error)
        }

        let fullScreenButton: AXUIElement
        switch copyElementAttribute(kAXFullScreenButtonAttribute as CFString, from: window) {
        case .success(let button):
            fullScreenButton = button
        case .failure(let error):
            return mapNativeFullScreenRequest(error)
        }

        switch configureMessagingTimeout(on: fullScreenButton) {
        case .success:
            break
        case .failure(let error):
            return mapNativeFullScreenRequest(error)
        }

        let error = AXUIElementPerformAction(fullScreenButton, kAXPressAction as CFString)
        return error == .success ? .accepted : mapNativeFullScreenRequest(error)
    }

    func probeWindow(_ identity: WindowIdentity) -> NativeFullScreenProbeResult {
        guard AXIsProcessTrusted() else {
            return .accessibilityPermissionRequired
        }
        guard let window = identityCache.element(for: identity) else {
            return .windowDisappeared
        }

        switch configureMessagingTimeout(on: window) {
        case .success:
            break
        case .failure(let error):
            return mapNativeFullScreenProbe(error)
        }

        switch copyStringAttribute(kAXRoleAttribute as CFString, from: window) {
        case .success:
            return .present
        case .failure(let error):
            return mapNativeFullScreenProbe(error)
        }
    }

    private func resolveFocusedWindow() -> AXRead<AXUIElement> {
        let systemWide = AXUIElementCreateSystemWide()
        switch configureMessagingTimeout(on: systemWide) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }

        switch copyElementAttribute(
            kAXFocusedApplicationAttribute as CFString,
            from: systemWide
        ) {
        case .success(let application):
            return resolveFocusedWindow(from: application)
        case .failure(let error):
            guard AXFocusedApplicationFallbackPolicy.shouldFallback(after: error) else {
                return .failure(error)
            }
        }

        guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return .failure(.noValue)
        }

        let frontmostApplication = AXUIElementCreateApplication(processID)
        return resolveFocusedWindow(from: frontmostApplication)
    }

    private func resolveFocusedWindow(from application: AXUIElement) -> AXRead<AXUIElement> {
        switch configureMessagingTimeout(on: application) {
        case .success:
            return copyElementAttribute(
                kAXFocusedWindowAttribute as CFString,
                from: application
            )
        case .failure(let error):
            return .failure(error)
        }
    }

    private func configureMessagingTimeout(on element: AXUIElement) -> AXRead<Void> {
        let error = AXUIElementSetMessagingTimeout(element, Self.messagingTimeoutSeconds)
        return error == .success ? .success(()) : .failure(error)
    }

    private func copyElementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXRead<AXUIElement> {
        var copiedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &copiedValue)

        guard error == .success else {
            return .failure(error)
        }
        guard let copiedValue, CFGetTypeID(copiedValue) == AXUIElementGetTypeID() else {
            return .failure(.noValue)
        }

        return .success(copiedValue as! AXUIElement)
    }

    private func copyStringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXRead<String> {
        var copiedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &copiedValue)

        guard error == .success else {
            return .failure(error)
        }
        guard let value = copiedValue as? String else {
            return .failure(.noValue)
        }

        return .success(value)
    }

    private func copyWindowKind(from element: AXUIElement) -> AXRead<WindowKind> {
        let role: String
        switch copyStringAttribute(kAXRoleAttribute as CFString, from: element) {
        case .success(let value):
            role = value
        case .failure(let error):
            return .failure(error)
        }

        let subrole: String?
        switch copyStringAttribute(kAXSubroleAttribute as CFString, from: element) {
        case .success(let value):
            subrole = value
        case .failure(.attributeUnsupported), .failure(.noValue):
            subrole = nil
        case .failure(let error):
            return .failure(error)
        }

        guard let kind = AXWindowEligibility.kind(role: role, subrole: subrole) else {
            return .failure(.attributeUnsupported)
        }
        return .success(kind)
    }

    private func copyPointAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXRead<CGPoint> {
        var copiedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &copiedValue)

        guard error == .success else {
            return .failure(error)
        }
        guard let copiedValue, CFGetTypeID(copiedValue) == AXValueGetTypeID() else {
            return .failure(.noValue)
        }

        let value = copiedValue as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(value) == .cgPoint,
              AXValueGetValue(value, .cgPoint, &point) else {
            return .failure(.noValue)
        }
        return .success(point)
    }

    private func copySizeAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXRead<CGSize> {
        var copiedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &copiedValue)

        guard error == .success else {
            return .failure(error)
        }
        guard let copiedValue, CFGetTypeID(copiedValue) == AXValueGetTypeID() else {
            return .failure(.noValue)
        }

        let value = copiedValue as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(value) == .cgSize,
              AXValueGetValue(value, .cgSize, &size) else {
            return .failure(.noValue)
        }
        return .success(size)
    }

    private func setPosition(_ position: CGPoint, on element: AXUIElement) -> AXRead<Void> {
        var processID: pid_t = 0
        if AXUIElementGetPid(element, &processID) == .success, processID == getpid() {
            return .failure(.illegalArgument)
        }
        var mutablePosition = position
        guard let value = AXValueCreate(.cgPoint, &mutablePosition) else {
            return .failure(.failure)
        }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            value
        )
        return error == .success ? .success(()) : .failure(error)
    }

    private func setSize(_ size: CGSize, on element: AXUIElement) -> AXRead<Void> {
        var processID: pid_t = 0
        if AXUIElementGetPid(element, &processID) == .success, processID == getpid() {
            return .failure(.illegalArgument)
        }
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            return .failure(.failure)
        }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            value
        )
        return error == .success ? .success(()) : .failure(error)
    }

    private func copyMinimizedState(from element: AXUIElement) -> AXRead<WindowMinimizedState> {
        var copiedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            &copiedValue
        )

        switch error {
        case .success:
            guard let value = copiedValue as? Bool else {
                return .failure(.noValue)
            }
            return .success(value ? .active : .inactive)
        case .attributeUnsupported, .noValue:
            return .success(.unavailable)
        default:
            return .failure(error)
        }
    }

    private func isAttributeSettable(
        _ attribute: CFString,
        on element: AXUIElement
    ) -> AXRead<Bool> {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute, &settable)

        switch error {
        case .success:
            return .success(settable.boolValue)
        case .attributeUnsupported, .noValue:
            return .success(false)
        default:
            return .failure(error)
        }
    }

    private func map(_ error: AXError) -> FocusedWindowFailure {
        switch error {
        case .apiDisabled:
            return .permissionRequired
        case .noValue, .attributeUnsupported, .invalidUIElement:
            return .noEligibleWindow
        case .cannotComplete:
            return .temporarilyUnavailable
        case .success, .failure, .illegalArgument, .invalidUIElementObserver,
                .actionUnsupported, .notificationUnsupported, .notImplemented,
                .notificationAlreadyRegistered, .notificationNotRegistered,
                .parameterizedAttributeUnsupported, .notEnoughPrecision:
            return .systemUnavailable
        @unknown default:
            return .systemUnavailable
        }
    }

    private func mapObservation(
        _ failure: FocusedWindowFailure
    ) -> PointerDragWindowObservationFailure {
        switch failure {
        case .permissionRequired:
            return .accessibilityPermissionRequired
        case .noEligibleWindow:
            return .noEligibleWindow
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .systemUnavailable:
            return .systemUnavailable
        }
    }

    private func mapObservation(
        _ error: AXError
    ) -> PointerDragWindowObservationFailure {
        switch error {
        case .apiDisabled:
            return .accessibilityPermissionRequired
        case .invalidUIElement, .noValue, .attributeUnsupported:
            return .noEligibleWindow
        case .notificationUnsupported:
            return .notificationUnsupported
        case .cannotComplete:
            return .temporarilyUnavailable
        case .success, .failure, .illegalArgument, .invalidUIElementObserver,
                .actionUnsupported, .notImplemented, .notificationAlreadyRegistered,
                .notificationNotRegistered, .parameterizedAttributeUnsupported,
                .notEnoughPrecision:
            return .systemUnavailable
        @unknown default:
            return .systemUnavailable
        }
    }

    private func mapOperation(_ error: AXError) -> AccessibilityWindowOperationFailure {
        switch error {
        case .apiDisabled:
            return .permissionRequired
        case .invalidUIElement, .noValue:
            return .windowDisappeared
        case .cannotComplete:
            return .temporarilyUnavailable
        case .success, .failure, .illegalArgument, .invalidUIElementObserver,
                .attributeUnsupported, .actionUnsupported, .notificationUnsupported,
                .notImplemented, .notificationAlreadyRegistered,
                .notificationNotRegistered, .parameterizedAttributeUnsupported,
                .notEnoughPrecision:
            return .rejected
        @unknown default:
            return .rejected
        }
    }

    private func mapNativeFullScreenRequest(_ error: AXError) -> NativeFullScreenRequestResult {
        switch error {
        case .apiDisabled:
            return .accessibilityPermissionRequired
        case .invalidUIElement:
            return .windowDisappeared
        case .cannotComplete:
            return .temporarilyUnavailable
        case .success:
            return .accepted
        case .failure, .illegalArgument, .invalidUIElementObserver, .noValue,
                .attributeUnsupported, .actionUnsupported, .notificationUnsupported,
                .notImplemented, .notificationAlreadyRegistered,
                .notificationNotRegistered, .parameterizedAttributeUnsupported,
                .notEnoughPrecision:
            return .rejected
        @unknown default:
            return .rejected
        }
    }

    private func mapNativeFullScreenProbe(_ error: AXError) -> NativeFullScreenProbeResult {
        switch error {
        case .apiDisabled:
            return .accessibilityPermissionRequired
        case .invalidUIElement:
            return .windowDisappeared
        case .cannotComplete:
            return .temporarilyUnavailable
        case .success:
            return .present
        case .failure, .illegalArgument, .invalidUIElementObserver, .noValue,
                .attributeUnsupported, .actionUnsupported, .notificationUnsupported,
                .notImplemented, .notificationAlreadyRegistered,
                .notificationNotRegistered, .parameterizedAttributeUnsupported,
                .notEnoughPrecision:
            return .rejected
        @unknown default:
            return .rejected
        }
    }
}

private final class SystemAXMovementCallbackBox: @unchecked Sendable {
    private let window: WindowIdentity
    private let lock = NSLock()
    private var continuation: AsyncStream<WindowIdentity>.Continuation?

    init(
        window: WindowIdentity,
        continuation: AsyncStream<WindowIdentity>.Continuation
    ) {
        self.window = window
        self.continuation = continuation
    }

    func moved() {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(window)
    }

    func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }
}

private let systemAXMovementObserverCallback: AXObserverCallback = {
    _, _, notification, userInfo in
    guard notification as String == kAXMovedNotification,
          let userInfo
    else { return }
    let box = Unmanaged<SystemAXMovementCallbackBox>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    box.moved()
}

private final class AXMovementRunLoopThread: @unchecked Sendable {
    private let runLoop: CFRunLoop

    init(name: String) {
        let condition = NSCondition()
        var runLoopRef: CFRunLoop?

        let thread = Thread {
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
            let currentRunLoop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(currentRunLoop, keepAlive, .commonModes)

            condition.lock()
            runLoopRef = currentRunLoop
            condition.broadcast()
            condition.unlock()

            CFRunLoopRun()
            CFRunLoopRemoveSource(currentRunLoop, keepAlive, .commonModes)
            CFRunLoopSourceInvalidate(keepAlive)
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()

        condition.lock()
        while runLoopRef == nil {
            condition.wait()
        }
        self.runLoop = runLoopRef!
        condition.unlock()
    }

    func add(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CFRunLoopWakeUp(runLoop)
    }

    func remove(_ source: CFRunLoopSource) {
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
    }

    deinit {
        CFRunLoopStop(runLoop)
        CFRunLoopWakeUp(runLoop)
    }
}

enum AXFocusedApplicationFallbackPolicy {
    static func shouldFallback(after error: AXError) -> Bool {
        switch error {
        case .noValue, .attributeUnsupported, .cannotComplete:
            return true
        case .success, .failure, .illegalArgument, .invalidUIElement,
                .invalidUIElementObserver, .apiDisabled, .actionUnsupported,
                .notificationUnsupported, .notImplemented,
                .notificationAlreadyRegistered, .notificationNotRegistered,
                .parameterizedAttributeUnsupported, .notEnoughPrecision:
            return false
        @unknown default:
            return false
        }
    }
}

enum AXWindowEligibility {
    static func kind(role: String, subrole: String?) -> WindowKind? {
        if role == (kAXSheetRole as String) {
            return .sheet
        }
        guard role == (kAXWindowRole as String) else {
            return nil
        }

        if subrole == (kAXStandardWindowSubrole as String) {
            return .standard
        }
        if subrole == (kAXDialogSubrole as String)
            || subrole == (kAXSystemDialogSubrole as String) {
            return .dialog
        }
        return nil
    }
}

enum AXFrameAttribute: Equatable {
    case position
    case size
}

enum AXFrameWriteOrdering {
    static func attributes(
        for mode: AccessibilityWindowWriteMode,
        axes: AccessibilityFrameAxes = .all
    ) -> [AXFrameAttribute] {
        let ordered: [AXFrameAttribute]
        switch mode {
        case .target:
            ordered = [.size, .position]
        case .rollback:
            ordered = [.position, .size]
        }
        return ordered.filter { attribute in
            switch attribute {
            case .position:
                axes.contains(.position)
            case .size:
                axes.contains(.size)
            }
        }
    }
}

/// Bounded least-recently-used association between one Adapter element and its opaque identity.
///
/// `Element` stays generic so cache behavior can be verified without letting an
/// `AXUIElement` escape the system Adapter.
struct WindowIdentityCache<Element> {
    private struct Record {
        let element: Element
        let identity: WindowIdentity
    }

    private let capacity: Int
    private let areEquivalent: (Element, Element) -> Bool
    private var records: [Record] = []

    init(capacity: Int, areEquivalent: @escaping (Element, Element) -> Bool) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.areEquivalent = areEquivalent
    }

    mutating func identity(for element: Element) -> WindowIdentity {
        if let index = records.firstIndex(where: { areEquivalent($0.element, element) }) {
            let existing = records.remove(at: index)
            records.append(existing)
            return existing.identity
        }

        let identity = WindowIdentity()
        records.append(Record(element: element, identity: identity))

        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }

        return identity
    }

    mutating func element(for identity: WindowIdentity) -> Element? {
        guard let index = records.firstIndex(where: { $0.identity == identity }) else {
            return nil
        }

        let record = records.remove(at: index)
        records.append(record)
        return record.element
    }
}
