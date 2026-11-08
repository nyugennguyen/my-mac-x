import ApplicationServices
import CoreFoundation
import CoreGraphics
import Foundation

protocol PointerDragScheduledTimeout: Sendable {
    func cancel()
}

protocol PointerDragReleaseTimeoutScheduling: Sendable {
    func schedule(
        afterMilliseconds: UInt64,
        _ operation: @escaping @Sendable () -> Void
    ) -> any PointerDragScheduledTimeout
}

final class TaskPointerDragReleaseTimeoutScheduler:
    PointerDragReleaseTimeoutScheduling,
    @unchecked Sendable
{
    func schedule(
        afterMilliseconds: UInt64,
        _ operation: @escaping @Sendable () -> Void
    ) -> any PointerDragScheduledTimeout {
        TaskPointerDragScheduledTimeout(
            task: Task {
                try? await Task.sleep(for: .milliseconds(afterMilliseconds))
                guard !Task.isCancelled else { return }
                operation()
            }
        )
    }
}

private final class TaskPointerDragScheduledTimeout:
    PointerDragScheduledTimeout,
    @unchecked Sendable
{
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

/// Compact pointer facts copied from the system callback.
///
/// Locations use AppKit-compatible global logical coordinates from
/// `CGEvent.unflippedLocation`. No raw event, button history, title, or Accessibility object
/// crosses this seam.
enum PointerPlatformSignal: Equatable, Sendable {
    case leftButtonPressed(location: CGPoint, timestamp: UInt64)
    case leftButtonDragged(location: CGPoint, timestamp: UInt64)
    case leftButtonReleased(location: CGPoint, timestamp: UInt64)
    case interrupted

    static func leftButtonPressed(location: CGPoint) -> PointerPlatformSignal {
        .leftButtonPressed(location: location, timestamp: 0)
    }

    static func leftButtonDragged(location: CGPoint) -> PointerPlatformSignal {
        .leftButtonDragged(location: location, timestamp: 0)
    }

    static func leftButtonReleased(location: CGPoint) -> PointerPlatformSignal {
        .leftButtonReleased(location: location, timestamp: 0)
    }

    var location: CGPoint? {
        switch self {
        case .leftButtonPressed(let loc, _),
             .leftButtonDragged(let loc, _),
             .leftButtonReleased(let loc, _):
            return loc
        case .interrupted:
            return nil
        }
    }

    var timestamp: UInt64 {
        switch self {
        case .leftButtonPressed(_, let ts),
             .leftButtonDragged(_, let ts),
             .leftButtonReleased(_, let ts):
            return ts
        case .interrupted:
            return 0
        }
    }
}

enum PointerEventAdapterStart: Sendable {
    case active(AsyncStream<PointerPlatformSignal>)
    case unavailable
}

/// System-input seam with two real Adapters: a listen-only CGEvent tap in production and an
/// in-memory stream in tests.
protocol PointerEventAdapting: Sendable {
    func start() async -> PointerEventAdapterStart
    func stop() async
}

enum PointerDragWindowObservationFailure: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case noEligibleWindow
    case notificationUnsupported
    case temporarilyUnavailable
    case systemUnavailable
}

enum PointerDragWindowObservationResult: Sendable {
    case observing(window: WindowIdentity, movements: AsyncStream<WindowIdentity>)
    case unavailable(PointerDragWindowObservationFailure)
}

/// Accessibility seam with two real Adapters: a confined AXObserver in production and an
/// in-memory movement stream in tests.
protocol PointerDragWindowMovementAdapting: Sendable {
    func observeFocusedWindow() async -> PointerDragWindowObservationResult
    func stopObserving() async
}

enum PointerDragMonitorStart: Equatable, Sendable {
    case active
    case unavailable
}

protocol PointerDragMonitoring: Actor {
    var events: AsyncStream<PointerDragEvent> { get }

    func start() async -> PointerDragMonitorStart
    func stop() async
}

/// Owns the complete input/AX lifecycle while keeping platform callbacks bounded.
///
/// `start` is idempotent. `stop` invalidates the current generation before awaiting Adapter
/// teardown, so late callback values cannot publish a drag. Callers consume only verified
/// `PointerDragEvent` values and continue to use `WindowActionPerforming` for preview/commit.
actor PointerDragMonitor: PointerDragMonitoring {
    private enum Lifecycle {
        case stopped
        case starting(UInt64, Task<PointerEventAdapterStart, Never>)
        case active(UInt64)
        case stopping(UInt64, Task<Void, Never>)
    }

    private struct PressSession: Sendable {
        enum Phase: Equatable, Sendable {
            case arming
            case replaying
            case armed
            case dragging
        }

        let epoch: UInt64
        let generation: UInt64
        let pressedLocation: CGPoint
        var phase: Phase
        var interaction: InteractionID?
        var bufferedSignals: [PointerPlatformSignal] = []
        var sawPointerDrag = false
        var pendingRelease: CGPoint?
    }

    let events: AsyncStream<PointerDragEvent>

    private let pointerEvents: any PointerEventAdapting
    private let windowMovements: any PointerDragWindowMovementAdapting
    private let tracker: PointerDragTracker
    private let releaseTimeoutScheduler: any PointerDragReleaseTimeoutScheduling
    private let continuation: AsyncStream<PointerDragEvent>.Continuation

    private var pointerTask: Task<Void, Never>?
    private var movementTask: Task<Void, Never>?
    private var armingTask: Task<PointerDragWindowObservationResult, Never>?
    private var releaseTimeoutTask: (any PointerDragScheduledTimeout)?
    private var lifecycle = Lifecycle.stopped
    private var lifecycleEpoch: UInt64 = 0
    private var pressEpoch: UInt64 = 0
    private var pressSession: PressSession?

    init(
        pointerEvents: any PointerEventAdapting,
        windowMovements: any PointerDragWindowMovementAdapting,
        tracker: PointerDragTracker = PointerDragTracker(),
        releaseTimeoutScheduler: any PointerDragReleaseTimeoutScheduling =
            TaskPointerDragReleaseTimeoutScheduler()
    ) {
        let channel = AsyncStream.makeStream(
            of: PointerDragEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        events = channel.stream
        continuation = channel.continuation
        self.pointerEvents = pointerEvents
        self.windowMovements = windowMovements
        self.tracker = tracker
        self.releaseTimeoutScheduler = releaseTimeoutScheduler
    }

    static func system() -> PointerDragMonitor {
        PointerDragMonitor(
            pointerEvents: MacOSPointerEventAdapter(),
            windowMovements: SystemWindowAdapter.shared
        )
    }

    func start() async -> PointerDragMonitorStart {
        switch lifecycle {
        case .active:
            return .active
        case let .starting(epoch, task):
            return finishStart(epoch: epoch, result: await task.value)
        case let .stopping(epoch, task):
            await task.value
            finishStop(epoch: epoch)
            return await start()
        case .stopped:
            break
        }

        lifecycleEpoch &+= 1
        let epoch = lifecycleEpoch
        let pointerEvents = pointerEvents
        let task = Task { await pointerEvents.start() }
        lifecycle = .starting(epoch, task)
        return finishStart(epoch: epoch, result: await task.value)
    }

    func stop() async {
        switch lifecycle {
        case .stopped:
            return
        case let .stopping(epoch, task):
            await task.value
            finishStop(epoch: epoch)
            return
        case let .starting(_, startTask):
            beginStop(waitingFor: startTask)
        case .active:
            beginStop(waitingFor: nil)
        }

        pointerTask?.cancel()
        pointerTask = nil
        cancelPressTasks()
        pressSession = nil
        _ = await tracker.consume(.cancelled)

        guard case let .stopping(epoch, task) = lifecycle else { return }
        await task.value
        finishStop(epoch: epoch)
    }

    deinit {
        continuation.finish()
        pointerTask?.cancel()
        movementTask?.cancel()
        armingTask?.cancel()
        releaseTimeoutTask?.cancel()
    }

    private func finishStart(
        epoch: UInt64,
        result: PointerEventAdapterStart
    ) -> PointerDragMonitorStart {
        if case .active(let activeEpoch) = lifecycle, activeEpoch == epoch {
            return .active
        }
        guard case .starting(let startingEpoch, _) = lifecycle,
              startingEpoch == epoch
        else { return .unavailable }

        switch result {
        case .unavailable:
            lifecycle = .stopped
            return .unavailable
        case .active(let source):
            lifecycle = .active(epoch)
            pointerTask = Task { [weak self] in
                for await signal in source {
                    guard !Task.isCancelled else { return }
                    await self?.consume(signal, generation: epoch)
                }
            }
            return .active
        }
    }

    private func beginStop(
        waitingFor startTask: Task<PointerEventAdapterStart, Never>?
    ) {
        lifecycleEpoch &+= 1
        let epoch = lifecycleEpoch
        let pointerEvents = pointerEvents
        let windowMovements = windowMovements
        let task = Task {
            if let startTask { _ = await startTask.value }
            await pointerEvents.stop()
            await windowMovements.stopObserving()
        }
        lifecycle = .stopping(epoch, task)
    }

    private func finishStop(epoch: UInt64) {
        guard case .stopping(let stoppingEpoch, _) = lifecycle,
              stoppingEpoch == epoch
        else { return }
        lifecycle = .stopped
    }

    private func consume(
        _ signal: PointerPlatformSignal,
        generation inputGeneration: UInt64
    ) async {
        guard case .active(let activeGeneration) = lifecycle,
              inputGeneration == activeGeneration
        else { return }

        switch signal {
        case .leftButtonPressed(let location, _):
            await beginPress(at: location, generation: inputGeneration)

        case .leftButtonDragged, .leftButtonReleased:
            await consumePressSignal(signal, generation: inputGeneration)

        case .interrupted:
            await cancelPress(generation: inputGeneration, publishCancellation: true)
        }
    }

    private func beginPress(
        at location: CGPoint,
        generation: UInt64
    ) async {
        pressEpoch &+= 1
        let epoch = pressEpoch
        cancelPressTasks()
        pressSession = nil
        publish(await tracker.consume(.cancelled))

        pressSession = PressSession(
            epoch: epoch,
            generation: generation,
            pressedLocation: location,
            phase: .arming
        )

        let windowMovements = windowMovements
        let task = Task<PointerDragWindowObservationResult, Never> {
            await windowMovements.stopObserving()
            guard !Task.isCancelled else {
                return PointerDragWindowObservationResult.unavailable(
                    .temporarilyUnavailable
                )
            }
            return await windowMovements.observeFocusedWindow()
        }
        armingTask = task
        Task { [weak self] in
            let observation = await task.value
            await self?.completeArm(
                observation,
                generation: generation,
                pressEpoch: epoch
            )
        }
    }

    private func completeArm(
        _ observation: PointerDragWindowObservationResult,
        generation: UInt64,
        pressEpoch inputPressEpoch: UInt64
    ) async {
        guard case .active(let activeGeneration) = lifecycle,
              activeGeneration == generation,
              var session = pressSession,
              session.epoch == inputPressEpoch,
              session.generation == generation,
              session.phase == .arming
        else { return }

        armingTask = nil
        guard case let .observing(window, movements) = observation else {
            if case let .unavailable(failure) = observation {
                print("[NotchSnap] window observation → unavailable(\(failure))")
            }
            pressSession = nil
            return
        }
        print("[NotchSnap] window observation → active")

        let interaction = InteractionID()
        session.phase = .replaying
        session.interaction = interaction
        pressSession = session
        _ = await tracker.consume(
            .leftButtonPressed(
                interaction: interaction,
                capturedWindow: window,
                location: session.pressedLocation
            )
        )

        guard pressSession?.epoch == inputPressEpoch else { return }

        movementTask = Task { [weak self] in
            for await signal in movements {
                guard !Task.isCancelled else { return }
                await self?.consumeMovement(
                    signal,
                    generation: generation,
                    pressEpoch: inputPressEpoch
                )
            }
        }

        while true {
            guard var replaySession = pressSession,
                  replaySession.epoch == inputPressEpoch,
                  replaySession.generation == generation
            else { return }
            let bufferedSignals = replaySession.bufferedSignals
            replaySession.bufferedSignals.removeAll(keepingCapacity: false)
            if bufferedSignals.isEmpty {
                if replaySession.phase == .replaying {
                    replaySession.phase = .armed
                    pressSession = replaySession
                }
                return
            }
            pressSession = replaySession
            for signal in bufferedSignals {
                guard pressSession?.epoch == inputPressEpoch else { return }
                await consumeReadyPressSignal(signal, generation: generation)
            }
        }
    }

    private func consumeMovement(
        _ window: WindowIdentity,
        generation inputGeneration: UInt64,
        pressEpoch inputPressEpoch: UInt64
    ) async {
        guard case .active(let activeGeneration) = lifecycle,
              activeGeneration == inputGeneration,
              let session = pressSession,
              session.epoch == inputPressEpoch,
              session.generation == inputGeneration
        else { return }

        let event = await tracker.consume(.capturedWindowMoved(window))
        if case .began = event {
            guard var currentSession = pressSession,
                  currentSession.epoch == inputPressEpoch,
                  currentSession.generation == inputGeneration
            else { return }
            currentSession.phase = .dragging
            let pendingRelease = currentSession.pendingRelease
            currentSession.pendingRelease = nil
            pressSession = currentSession
            publish(event)
            if let pendingRelease {
                await consumePressSignal(
                    .leftButtonReleased(location: pendingRelease),
                    generation: inputGeneration
                )
            }
        }
    }

    private func consumePressSignal(
        _ signal: PointerPlatformSignal,
        generation inputGeneration: UInt64
    ) async {
        guard case .active(let activeGeneration) = lifecycle,
              activeGeneration == inputGeneration,
              var session = pressSession,
              session.generation == inputGeneration
        else { return }

        if session.phase == .arming || session.phase == .replaying {
            session.bufferedSignals.append(signal)
            pressSession = session
            return
        }

        await consumeReadyPressSignal(signal, generation: inputGeneration)
    }

    private func consumeReadyPressSignal(
        _ signal: PointerPlatformSignal,
        generation inputGeneration: UInt64
    ) async {
        guard case .active(let activeGeneration) = lifecycle,
              activeGeneration == inputGeneration,
              var session = pressSession,
              session.generation == inputGeneration
        else { return }

        switch signal {
        case .leftButtonDragged(let location, _):
            session.sawPointerDrag = true
            pressSession = session
            let event = await tracker.consume(.leftButtonDragged(location: location))
            guard var currentSession = pressSession,
                  currentSession.epoch == session.epoch,
                  currentSession.generation == inputGeneration
            else { return }
            if case .began = event {
                currentSession.phase = .dragging
            }
            if case .moved = event {
                currentSession.phase = .dragging
            }
            currentSession.sawPointerDrag = true
            pressSession = currentSession
            publish(event)

        case .leftButtonReleased(let location, _):
            if session.phase == .dragging {
                let event = await tracker.consume(.leftButtonReleased(location: location))
                publish(event)
                await finishPress(epoch: session.epoch)
            } else if session.sawPointerDrag {
                session.pendingRelease = location
                pressSession = session
                scheduleReleaseTimeout(for: session)
            } else {
                _ = await tracker.consume(.leftButtonReleased(location: location))
                await finishPress(epoch: session.epoch)
            }

        case .leftButtonPressed, .interrupted:
            return
        }
    }

    private func scheduleReleaseTimeout(for session: PressSession) {
        releaseTimeoutTask?.cancel()
        releaseTimeoutTask = releaseTimeoutScheduler.schedule(afterMilliseconds: 250) {
            [weak self] in
            Task {
                await self?.expireReleasedPress(
                    generation: session.generation,
                    pressEpoch: session.epoch
                )
            }
        }
    }

    private func expireReleasedPress(
        generation: UInt64,
        pressEpoch inputPressEpoch: UInt64
    ) async {
        guard let session = pressSession,
              session.generation == generation,
              session.epoch == inputPressEpoch,
              session.pendingRelease != nil
        else { return }
        _ = await tracker.consume(.cancelled)
        await finishPress(epoch: inputPressEpoch)
    }

    private func cancelPress(
        generation: UInt64,
        publishCancellation: Bool
    ) async {
        guard let epoch = pressSession?.epoch,
              pressSession?.generation == generation
        else { return }
        let event = await tracker.consume(.cancelled)
        if publishCancellation { publish(event) }
        await finishPress(epoch: epoch)
    }

    private func finishPress(epoch: UInt64?) async {
        guard let epoch, pressSession?.epoch == epoch else { return }
        cancelPressTasks()
        pressSession = nil
        await windowMovements.stopObserving()
    }

    private func cancelPressTasks() {
        armingTask?.cancel()
        armingTask = nil
        movementTask?.cancel()
        movementTask = nil
        releaseTimeoutTask?.cancel()
        releaseTimeoutTask = nil
    }

    private func publish(_ event: PointerDragEvent?) {
        guard let event else { return }
        if case .began = event {
            print("[NotchSnap] pointer tracker → drag began")
        }
        continuation.yield(event)
    }
}

/// Public-API, listen-only pointer Adapter. The callback copies only event kind and global
/// pointer location into a bounded stream and immediately returns the original event.
actor MacOSPointerEventAdapter: PointerEventAdapting {
    private let runLoop = PrivateRunLoopThread(name: "MyMacX.PointerEvents")
    private let state = MacOSPointerEventTapState()

    func start() async -> PointerEventAdapterStart {
        await runLoop.perform { [state] in
            state.start()
        }
    }

    func stop() async {
        await runLoop.perform { [state] in
            state.stop()
        }
    }

    deinit {
        runLoop.shutdown { [state] in
            state.stop()
        }
    }
}

private final class MacOSPointerEventTapState: @unchecked Sendable {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var callbackBox: PointerEventCallbackBox?
    private var stream: AsyncStream<PointerPlatformSignal>?

    func start() -> PointerEventAdapterStart {
        if let stream {
            return .active(stream)
        }

        let hasInputMonitoringAccess = CGPreflightListenEventAccess()
        print("[NotchSnap] Input Monitoring preflight → \(hasInputMonitoringAccess)")
        guard hasInputMonitoringAccess else {
            return .unavailable
        }

        let channel = AsyncStream.makeStream(
            of: PointerPlatformSignal.self,
            bufferingPolicy: .bufferingNewest(256)
        )
        let box = PointerEventCallbackBox(continuation: channel.continuation)
        let mask = Self.eventMask([
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
        ])
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: pointerEventTapCallback,
            userInfo: Unmanaged.passUnretained(box).toOpaque()
        ) else {
            channel.continuation.finish()
            return .unavailable
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            channel.continuation.finish()
            return .unavailable
        }

        box.tap = tap
        self.tap = tap
        self.source = source
        callbackBox = box
        stream = channel.stream
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return .active(channel.stream)
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        callbackBox?.finish()
        callbackBox = nil
        source = nil
        tap = nil
        stream = nil
    }

    private static func eventMask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }
}

private final class PointerEventCallbackBox: @unchecked Sendable {
    let continuation: AsyncStream<PointerPlatformSignal>.Continuation
    var tap: CFMachPort?

    init(continuation: AsyncStream<PointerPlatformSignal>.Continuation) {
        self.continuation = continuation
    }

    func receive(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown:
            continuation.yield(.leftButtonPressed(location: event.unflippedLocation, timestamp: event.timestamp))
        case .leftMouseDragged:
            continuation.yield(.leftButtonDragged(location: event.unflippedLocation, timestamp: event.timestamp))
        case .leftMouseUp:
            continuation.yield(.leftButtonReleased(location: event.unflippedLocation, timestamp: event.timestamp))
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            continuation.yield(.interrupted)
        default:
            break
        }
    }

    func finish() {
        continuation.finish()
    }
}

private let pointerEventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    if let userInfo {
        let box = Unmanaged<PointerEventCallbackBox>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        box.receive(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

/// One private CFRunLoop used to confine callback-based system objects and their teardown.
private final class PrivateRunLoopThread: @unchecked Sendable {
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
            while runLoop == nil {
                condition.wait()
            }
            let value = runLoop!
            condition.unlock()
            return value
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
