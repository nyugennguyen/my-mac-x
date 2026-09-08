import ApplicationServices
import CoreFoundation
import CoreGraphics
import Foundation

struct MacOSInputMonitoringAuthorizer: Sendable {
    func hasAccess() -> Bool {
        CGPreflightListenEventAccess()
    }

    func requestAccess() -> Bool {
        CGRequestListenEventAccess()
    }
}

/// CoreGraphics Adapter for non-text keyboard metadata. Permission prompts remain a caller-owned,
/// human-visible action: this Adapter only preflights access and reports installation failure.
actor MacOSEventTapSystem: EventTapSystem {
    private let runLoop = EventTapRunLoopThread(name: "MyMacX.EventTap")
    private let state = MacOSEventTapState()

    func install(
        _ handler: @escaping @Sendable (EventTapSignal) -> EventTapEventDisposition
    ) async -> EventTapInstallation? {
        await runLoop.perform { [state] in state.install(handler) }
    }

    func enable(_ installation: EventTapInstallation) async {
        await runLoop.perform { [state] in state.enable(installation) }
    }

    func invalidate(_ installation: EventTapInstallation) async {
        await runLoop.perform { [state] in state.invalidate(installation) }
    }

    deinit {
        runLoop.shutdown { [state] in state.invalidateCurrentInstallation() }
    }
}

private final class MacOSEventTapState: @unchecked Sendable {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var callbackBox: MacOSEventTapCallbackBox?
    private var installation: EventTapInstallation?
    private var nextInstallationID: UInt64 = 1

    func install(
        _ handler: @escaping @Sendable (EventTapSignal) -> EventTapEventDisposition
    ) -> EventTapInstallation? {
        guard tap == nil, CGPreflightListenEventAccess() else { return nil }

        let installation = allocateInstallation()
        let callbackBox = MacOSEventTapCallbackBox(handler: handler)
        let mask = Self.eventMask([.keyDown, .keyUp, .flagsChanged])
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: macOSEventTapCallback,
            userInfo: Unmanaged.passUnretained(callbackBox).toOpaque()
        ) else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }

        self.tap = tap
        self.source = source
        self.callbackBox = callbackBox
        self.installation = installation
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        return installation
    }

    func enable(_ installation: EventTapInstallation) {
        guard self.installation == installation, let tap, CFMachPortIsValid(tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func invalidate(_ installation: EventTapInstallation) {
        guard self.installation == installation else { return }
        invalidateCurrentInstallation()
    }

    func invalidateCurrentInstallation() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap { CFMachPortInvalidate(tap) }
        installation = nil
        callbackBox = nil
        source = nil
        tap = nil
    }

    private func allocateInstallation() -> EventTapInstallation {
        let installation = EventTapInstallation(rawValue: nextInstallationID)
        nextInstallationID &+= 1
        if nextInstallationID == 0 { nextInstallationID = 1 }
        return installation
    }

    private static func eventMask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }
}

/// Copies only non-text metadata and makes the sole physical-event suppression decision.
final class MacOSEventTapCallbackBox: @unchecked Sendable {
    private let handler: @Sendable (EventTapSignal) -> EventTapEventDisposition

    init(
        handler: @escaping @Sendable (EventTapSignal) -> EventTapEventDisposition
    ) {
        self.handler = handler
    }

    func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let signal = Self.signal(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        let disposition = handler(signal)
        return disposition == .consume ? nil : Unmanaged.passUnretained(event)
    }

    private static func signal(type: CGEventType, event: CGEvent) -> EventTapSignal? {
        switch type {
        case .tapDisabledByTimeout: return .disabledByTimeout
        case .tapDisabledByUserInput: return .disabledByUserInput
        case .keyDown: return .key(keySignal(kind: .keyDown, event: event))
        case .keyUp: return .key(keySignal(kind: .keyUp, event: event))
        case .flagsChanged: return .key(keySignal(kind: .flagsChanged, event: event))
        default: return nil
        }
    }

    private static func keySignal(
        kind: EventTapKeySignal.Kind,
        event: CGEvent
    ) -> EventTapKeySignal {
        EventTapKeySignal(
            kind: kind,
            hardwareKeyCode: UInt16(
                truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)
            ),
            modifierFlags: event.flags.rawValue,
            isRepeat: kind == .keyDown
                && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    }
}

private let macOSEventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let callbackBox = Unmanaged<MacOSEventTapCallbackBox>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return callbackBox.receive(type: type, event: event)
}

private final class EventTapRunLoopThread: @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        let condition = NSCondition()
        private var runLoop: CFRunLoop?

        func publish(_ runLoop: CFRunLoop) {
            condition.lock()
            self.runLoop = runLoop
            condition.broadcast()
            condition.unlock()
        }

        func waitForRunLoop() -> CFRunLoop {
            condition.lock()
            while runLoop == nil { condition.wait() }
            let runLoop = runLoop!
            condition.unlock()
            return runLoop
        }
    }

    private let storage: Storage
    private let thread: Thread

    init(name: String) {
        let storage = Storage()
        self.storage = storage
        thread = Thread {
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
            let runLoop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(runLoop, keepAlive, .commonModes)
            storage.publish(runLoop)
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, keepAlive, .commonModes)
            CFRunLoopSourceInvalidate(keepAlive)
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = storage.waitForRunLoop()
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () -> Value
    ) async -> Value {
        let runLoop = storage.waitForRunLoop()
        return await withCheckedContinuation { continuation in
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                continuation.resume(returning: operation())
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    func shutdown(_ teardown: @escaping @Sendable () -> Void) {
        let runLoop = storage.waitForRunLoop()
        let completed = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            teardown()
            CFRunLoopStop(runLoop)
            completed.signal()
        }
        CFRunLoopWakeUp(runLoop)
        completed.wait()
    }
}
