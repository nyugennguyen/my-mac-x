import CoreGraphics
import XCTest

@testable import MyMacX

final class PointerDragTrackerTests: XCTestCase {
    func testDragBeginsOnlyAfterPointerAndCapturedWindowMovementCorroborate() async {
        let tracker = PointerDragTracker()
        let capturedWindow = WindowIdentity(
            rawValue: UUID(uuidString: "7204438F-C6CE-42BB-854B-D6437E7B37C4")!
        )
        let otherWindow = WindowIdentity(
            rawValue: UUID(uuidString: "8526C88D-2D98-4550-B73E-A648DA96BBF9")!
        )
        let interaction = InteractionID(
            UUID(uuidString: "AAEDE5C0-A7BF-4547-AFDE-6195E9667629")!
        )

        let pressed = await tracker.consume(
            .leftButtonPressed(
                interaction: interaction,
                capturedWindow: capturedWindow,
                location: CGPoint(x: 310, y: 420)
            )
        )
        let hovered = await tracker.consume(.pointerMoved(location: CGPoint(x: 312, y: 421)))
        let otherWindowMoved = await tracker.consume(.capturedWindowMoved(otherWindow))
        let pointerDragged = await tracker.consume(
            .leftButtonDragged(location: CGPoint(x: 318, y: 426))
        )
        let corroborated = await tracker.consume(.capturedWindowMoved(capturedWindow))
        let duplicateMove = await tracker.consume(.capturedWindowMoved(capturedWindow))

        XCTAssertNil(pressed)
        XCTAssertNil(hovered)
        XCTAssertNil(otherWindowMoved)
        XCTAssertNil(pointerDragged)
        XCTAssertEqual(
            corroborated,
            .began(
                PointerDragContext(
                    interaction: interaction,
                    capturedWindow: capturedWindow,
                    pointerLocation: CGPoint(x: 318, y: 426)
                )
            )
        )
        XCTAssertNil(duplicateMove)
    }

    func testMonitorLifecyclePublishesVerifiedDragAndStopsFurtherInput() async throws {
        let pointerEvents = InMemoryPointerEventAdapter()
        let windowMovements = InMemoryPointerDragWindowMovementAdapter(
            window: WindowIdentity(
                rawValue: UUID(uuidString: "692F1A55-3500-4B2E-8E12-5CA3F2867E04")!
            )
        )
        let monitor = PointerDragMonitor(
            pointerEvents: pointerEvents,
            windowMovements: windowMovements
        )
        let events = await monitor.events

        let firstStart = await monitor.start()
        let duplicateStart = await monitor.start()
        await pointerEvents.send(.leftButtonPressed(location: CGPoint(x: 400, y: 700)))
        await pointerEvents.send(.leftButtonDragged(location: CGPoint(x: 410, y: 710)))
        await windowMovements.sendMovement()

        let began = try await firstPointerDragEvent(from: events)
        await monitor.stop()
        await pointerEvents.send(.leftButtonPressed(location: CGPoint(x: 500, y: 800)))
        await pointerEvents.send(.leftButtonDragged(location: CGPoint(x: 510, y: 810)))
        await windowMovements.sendMovement()
        let eventAfterStop = await firstPointerDragEvent(
            from: events,
            within: .milliseconds(50)
        )

        XCTAssertEqual(firstStart, .active)
        XCTAssertEqual(duplicateStart, .active)
        guard case let .began(context) = began else {
            return XCTFail("Expected a verified pointer drag")
        }
        let observedWindow = await windowMovements.windowIdentity
        XCTAssertEqual(context.pointerLocation, CGPoint(x: 410, y: 710))
        XCTAssertEqual(context.capturedWindow, observedWindow)
        XCTAssertNil(eventAfterStop)
    }

    func testConcurrentStartsShareOneAdapterStart() async {
        let pointerEvents = GatedPointerEventAdapter()
        let monitor = PointerDragMonitor(
            pointerEvents: pointerEvents,
            windowMovements: InMemoryPointerDragWindowMovementAdapter(window: WindowIdentity())
        )

        let first = Task { await monitor.start() }
        while await pointerEvents.startCount == 0 { await Task.yield() }
        let second = Task { await monitor.start() }
        for _ in 0..<20 { await Task.yield() }
        await pointerEvents.releaseStart()

        let firstResult = await first.value
        let secondResult = await second.value
        let startCount = await pointerEvents.startCount
        XCTAssertEqual(firstResult, .active)
        XCTAssertEqual(secondResult, .active)
        XCTAssertEqual(startCount, 1)
        await monitor.stop()
    }

    func testStopDuringStartWaitsForOneTeardownAndPreventsActivation() async {
        let pointerEvents = GatedPointerEventAdapter()
        let monitor = PointerDragMonitor(
            pointerEvents: pointerEvents,
            windowMovements: InMemoryPointerDragWindowMovementAdapter(window: WindowIdentity())
        )

        let starting = Task { await monitor.start() }
        while await pointerEvents.startCount == 0 { await Task.yield() }
        let stopping = Task { await monitor.stop() }
        for _ in 0..<20 { await Task.yield() }
        await pointerEvents.releaseStart()

        let startResult = await starting.value
        await stopping.value
        let stopCount = await pointerEvents.stopCount
        XCTAssertEqual(startResult, .unavailable)
        XCTAssertEqual(stopCount, 1)
    }

    func testFastDragAndReleaseAreReplayedAfterDelayedWindowObservation() async throws {
        let pointerEvents = InMemoryPointerEventAdapter()
        let capturedWindow = WindowIdentity()
        let windowMovements = GatedPointerDragWindowMovementAdapter(window: capturedWindow)
        let monitor = PointerDragMonitor(
            pointerEvents: pointerEvents,
            windowMovements: windowMovements
        )
        let events = await monitor.events

        let started = await monitor.start()
        XCTAssertEqual(started, .active)
        await pointerEvents.send(.leftButtonPressed(location: CGPoint(x: 300, y: 20)))
        while await windowMovements.observeCount == 0 { await Task.yield() }
        await pointerEvents.send(.leftButtonDragged(location: CGPoint(x: 312, y: 24)))
        await pointerEvents.send(.leftButtonReleased(location: CGPoint(x: 314, y: 25)))
        await windowMovements.sendMovement()
        await windowMovements.releaseObservation()

        let observed = try await firstPointerDragEvents(count: 2, from: events)
        guard case let .began(context) = observed[0] else {
            return XCTFail("Expected a verified drag before release")
        }
        XCTAssertEqual(context.capturedWindow, capturedWindow)
        XCTAssertEqual(context.pointerLocation, CGPoint(x: 312, y: 24))
        XCTAssertEqual(observed[1], .released(interaction: context.interaction))
        await monitor.stop()
    }

    func testNewPressEpochInvalidatesAStaleDelayedArm() async throws {
        let pointerEvents = InMemoryPointerEventAdapter()
        let staleWindow = WindowIdentity()
        let currentWindow = WindowIdentity()
        let windowMovements = SequencedGatedWindowMovementAdapter(
            windows: [staleWindow, currentWindow]
        )
        let monitor = PointerDragMonitor(
            pointerEvents: pointerEvents,
            windowMovements: windowMovements
        )
        let events = await monitor.events

        _ = await monitor.start()
        await pointerEvents.send(.leftButtonPressed(location: CGPoint(x: 100, y: 20)))
        while await windowMovements.observeCount < 1 { await Task.yield() }
        await pointerEvents.send(.leftButtonDragged(location: CGPoint(x: 110, y: 24)))

        await pointerEvents.send(.leftButtonPressed(location: CGPoint(x: 200, y: 20)))
        while await windowMovements.observeCount < 2 { await Task.yield() }
        await windowMovements.sendMovement(at: 0)
        await windowMovements.releaseObservation(at: 0)

        await pointerEvents.send(.leftButtonDragged(location: CGPoint(x: 214, y: 25)))
        await windowMovements.sendMovement(at: 1)
        await windowMovements.releaseObservation(at: 1)

        let event = try await firstPointerDragEvent(from: events)
        guard case let .began(context) = event else {
            return XCTFail("Expected the current press to begin dragging")
        }
        XCTAssertEqual(context.capturedWindow, currentWindow)
        XCTAssertEqual(context.pointerLocation, CGPoint(x: 214, y: 25))
        await monitor.stop()
    }

    // MARK: - SOL Finding 1: Delayed AX observation replay must not leak into subsequent presses

    func testReplayedDragCompletionDoesNotInterfereWithSubsequentPress() async throws {
        let pointerEvents = InMemoryPointerEventAdapter()
        let staleWindow = WindowIdentity()
        let freshWindow = WindowIdentity()
        let windowMovements = SequencedGatedWindowMovementAdapter(
            windows: [staleWindow, freshWindow]
        )
        let monitor = PointerDragMonitor(
            pointerEvents: pointerEvents,
            windowMovements: windowMovements
        )
        let events = await monitor.events

        _ = await monitor.start()

        // First press: arm, drag, release all before AX observation completes.
        await pointerEvents.send(.leftButtonPressed(location: CGPoint(x: 100, y: 20)))
        while await windowMovements.observeCount < 1 { await Task.yield() }
        await pointerEvents.send(.leftButtonDragged(location: CGPoint(x: 110, y: 24)))
        await pointerEvents.send(.leftButtonReleased(location: CGPoint(x: 112, y: 25)))

        // AX observation completes → replays buffered began + released.
        await windowMovements.sendMovement(at: 0)
        await windowMovements.releaseObservation(at: 0)

        let replayed = try await firstPointerDragEvents(count: 2, from: events)
        guard case let .began(firstContext) = replayed[0] else {
            return XCTFail("Expected replayed began from first press")
        }
        XCTAssertEqual(firstContext.capturedWindow, staleWindow)
        XCTAssertEqual(replayed[1], .released(interaction: firstContext.interaction))

        // Second press: must start clean with a fresh window.
        await pointerEvents.send(.leftButtonPressed(location: CGPoint(x: 200, y: 30)))
        while await windowMovements.observeCount < 2 { await Task.yield() }
        await pointerEvents.send(.leftButtonDragged(location: CGPoint(x: 214, y: 35)))
        await windowMovements.sendMovement(at: 1)
        await windowMovements.releaseObservation(at: 1)

        let secondEvent = try await firstPointerDragEvent(from: events)
        guard case let .began(secondContext) = secondEvent else {
            return XCTFail("Expected the second press to begin dragging")
        }
        XCTAssertEqual(secondContext.capturedWindow, freshWindow)
        XCTAssertEqual(secondContext.pointerLocation, CGPoint(x: 214, y: 35))
        XCTAssertNotEqual(firstContext.interaction, secondContext.interaction)
        await monitor.stop()
    }

    // MARK: - SOL Finding 2: Triple rapid start-stop-start lifecycle

    func testTripleRapidStartStopStartSucceedsWithCleanState() async {
        let pointerEvents = GatedPointerEventAdapter()
        let capturedWindow = WindowIdentity()
        let windowMovements = InMemoryPointerDragWindowMovementAdapter(
            window: capturedWindow
        )
        let monitor = PointerDragMonitor(
            pointerEvents: pointerEvents,
            windowMovements: windowMovements
        )

        // Start → immediate stop → immediate start.
        let firstStart = Task { await monitor.start() }
        while await pointerEvents.startCount == 0 { await Task.yield() }
        let stop = Task { await monitor.stop() }
        await pointerEvents.releaseStart()
        _ = await firstStart.value
        await stop.value

        // Final start — also gated, must release.
        let finalStart = Task { await monitor.start() }
        while await pointerEvents.startCount < 2 { await Task.yield() }
        await pointerEvents.releaseStart()
        let finalResult = await finalStart.value

        let finalStartCount = await pointerEvents.startCount
        let finalStopCount = await pointerEvents.stopCount
        XCTAssertEqual(finalResult, .active)
        XCTAssertEqual(finalStartCount, 2)
        XCTAssertEqual(finalStopCount, 1)
        await monitor.stop()
    }
}

// MARK: - Test Adapters

private actor InMemoryPointerEventAdapter: PointerEventAdapting {
    private let stream: AsyncStream<PointerPlatformSignal>
    private let continuation: AsyncStream<PointerPlatformSignal>.Continuation
    private var isActive = false

    init() {
        let channel = AsyncStream.makeStream(of: PointerPlatformSignal.self)
        stream = channel.stream
        continuation = channel.continuation
    }

    func start() -> PointerEventAdapterStart {
        isActive = true
        return .active(stream)
    }

    func stop() {
        isActive = false
    }

    func send(_ signal: PointerPlatformSignal) {
        guard isActive else { return }
        continuation.yield(signal)
    }
}

private actor InMemoryPointerDragWindowMovementAdapter: PointerDragWindowMovementAdapting {
    private let window: WindowIdentity
    private let stream: AsyncStream<WindowIdentity>
    private let continuation: AsyncStream<WindowIdentity>.Continuation

    init(window: WindowIdentity) {
        self.window = window
        let channel = AsyncStream.makeStream(of: WindowIdentity.self)
        stream = channel.stream
        continuation = channel.continuation
    }

    func observeFocusedWindow() -> PointerDragWindowObservationResult {
        .observing(window: window, movements: stream)
    }

    func stopObserving() {}

    func sendMovement() {
        continuation.yield(window)
    }

    var windowIdentity: WindowIdentity { window }
}

private actor GatedPointerEventAdapter: PointerEventAdapting {
    private let stream: AsyncStream<PointerPlatformSignal>
    private var startContinuation: CheckedContinuation<Void, Never>?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init() {
        stream = AsyncStream { _ in }
    }

    func start() async -> PointerEventAdapterStart {
        startCount += 1
        await withCheckedContinuation { startContinuation = $0 }
        return .active(stream)
    }

    func stop() { stopCount += 1 }

    func releaseStart() {
        startContinuation?.resume()
        startContinuation = nil
    }
}

private actor SequencedGatedWindowMovementAdapter: PointerDragWindowMovementAdapting {
    private let windows: [WindowIdentity]
    private let streams: [AsyncStream<WindowIdentity>]
    private let continuations: [AsyncStream<WindowIdentity>.Continuation]
    private var observationContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var observeCount = 0

    init(windows: [WindowIdentity]) {
        self.windows = windows
        let channels = windows.map { _ in AsyncStream.makeStream(of: WindowIdentity.self) }
        streams = channels.map(\.stream)
        continuations = channels.map(\.continuation)
    }

    func observeFocusedWindow() async -> PointerDragWindowObservationResult {
        let index = observeCount
        observeCount += 1
        await withCheckedContinuation { observationContinuations[index] = $0 }
        return .observing(window: windows[index], movements: streams[index])
    }

    func stopObserving() {}

    func sendMovement(at index: Int) {
        continuations[index].yield(windows[index])
    }

    func releaseObservation(at index: Int) {
        observationContinuations.removeValue(forKey: index)?.resume()
    }
}

private actor GatedPointerDragWindowMovementAdapter: PointerDragWindowMovementAdapting {
    private let window: WindowIdentity
    private let stream: AsyncStream<WindowIdentity>
    private let continuation: AsyncStream<WindowIdentity>.Continuation
    private var observationContinuation: CheckedContinuation<Void, Never>?
    private(set) var observeCount = 0

    init(window: WindowIdentity) {
        self.window = window
        let channel = AsyncStream.makeStream(of: WindowIdentity.self)
        stream = channel.stream
        continuation = channel.continuation
    }

    func observeFocusedWindow() async -> PointerDragWindowObservationResult {
        observeCount += 1
        await withCheckedContinuation { observationContinuation = $0 }
        return .observing(window: window, movements: stream)
    }

    func stopObserving() {}

    func sendMovement() {
        continuation.yield(window)
    }

    func releaseObservation() {
        observationContinuation?.resume()
        observationContinuation = nil
    }
}

// MARK: - Test Helpers

private enum PointerDragMonitorTestFailure: Error {
    case streamFinished
    case timedOut
}

private func firstPointerDragEvent(
    from events: AsyncStream<PointerDragEvent>
) async throws -> PointerDragEvent {
    try await withThrowingTaskGroup(of: PointerDragEvent.self) { group in
        group.addTask {
            for await event in events {
                return event
            }
            throw PointerDragMonitorTestFailure.streamFinished
        }
        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw PointerDragMonitorTestFailure.timedOut
        }

        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}

private func firstPointerDragEvents(
    count: Int,
    from events: AsyncStream<PointerDragEvent>
) async throws -> [PointerDragEvent] {
    try await withThrowingTaskGroup(of: [PointerDragEvent].self) { group in
        group.addTask {
            var observed: [PointerDragEvent] = []
            for await event in events {
                observed.append(event)
                if observed.count == count { return observed }
            }
            throw PointerDragMonitorTestFailure.streamFinished
        }
        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw PointerDragMonitorTestFailure.timedOut
        }

        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}

private func firstPointerDragEvent(
    from events: AsyncStream<PointerDragEvent>,
    within duration: Duration
) async -> PointerDragEvent? {
    await withTaskGroup(of: PointerDragEvent?.self) { group in
        group.addTask {
            for await event in events {
                return event
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: duration)
            return nil
        }

        let value = await group.next()!
        group.cancelAll()
        return value
    }
}
