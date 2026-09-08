import Foundation
import CoreGraphics
import XCTest
@testable import MyMacX

final class EventTapManagerTests: XCTestCase {
    func testStartIsIdempotentAfterTapBecomesActive() async {
        let system = InMemoryEventTapSystem()
        let manager = makeManager(system: system)

        let first = await manager.start()
        let second = await manager.start()
        let installCount = await system.installCount
        let enableCount = await system.enableCount
        let status = await manager.status()

        XCTAssertEqual(first, .active)
        XCTAssertEqual(second, .active)
        XCTAssertEqual(status, .active)
        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(enableCount, 1)
    }

    func testUnavailableInstallationIsStableUntilStopped() async {
        let system = InMemoryEventTapSystem(allowsInstallation: false)
        let manager = makeManager(system: system)

        let first = await manager.start()
        let second = await manager.start()
        let status = await manager.status()
        let installCount = await system.installCount

        XCTAssertEqual(first, .unavailable)
        XCTAssertEqual(second, .unavailable)
        XCTAssertEqual(status, .unavailable)
        XCTAssertEqual(installCount, 1)
    }

    func testTimeoutDisableReenablesSameInstallation() async {
        let system = InMemoryEventTapSystem()
        let manager = makeManager(system: system)
        _ = await manager.start()
        let installed = await system.enabledInstallations
        let originalInstallation = installed[0]

        let disposition = await system.emit(.disabledByTimeout)
        await system.waitUntilEnableCount(2)

        let enabledInstallations = await system.enabledInstallations
        let installCount = await system.installCount
        let status = await manager.status()
        XCTAssertEqual(disposition, .passThrough)
        XCTAssertEqual(enabledInstallations, [originalInstallation, originalInstallation])
        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(status, .active)
    }

    func testUserInputDisableReenablesSameInstallation() async {
        let system = InMemoryEventTapSystem()
        let manager = makeManager(system: system)
        _ = await manager.start()
        let installed = await system.enabledInstallations
        let originalInstallation = installed[0]

        let disposition = await system.emit(.disabledByUserInput)
        await system.waitUntilEnableCount(2)

        let enabledInstallations = await system.enabledInstallations
        let installCount = await system.installCount
        XCTAssertEqual(disposition, .passThrough)
        XCTAssertEqual(enabledInstallations, [originalInstallation, originalInstallation])
        XCTAssertEqual(installCount, 1)
    }

    func testStopInvalidatesOnceAndIsIdempotent() async {
        let system = InMemoryEventTapSystem()
        let manager = makeManager(system: system)
        _ = await manager.start()

        await manager.stop()
        await manager.stop()
        let status = await manager.status()
        let invalidateCount = await system.invalidateCount

        XCTAssertEqual(status, .stopped)
        XCTAssertEqual(invalidateCount, 1)
    }

    func testCallbackFromStoppedInstallationCannotReenableRestartedTap() async {
        let system = InMemoryEventTapSystem()
        let manager = makeManager(system: system)
        _ = await manager.start()
        let firstEnabledInstallations = await system.enabledInstallations
        let staleInstallation = firstEnabledInstallations[0]
        await manager.stop()
        _ = await manager.start()
        let enableCountBeforeStaleCallback = await system.enableCount

        let disposition = await system.emit(.disabledByTimeout, from: staleInstallation)
        let enableCount = await system.enableCount
        let status = await manager.status()

        XCTAssertEqual(disposition, .passThrough)
        XCTAssertEqual(enableCount, enableCountBeforeStaleCallback)
        XCTAssertEqual(status, .active)
    }

    func testRestartWaitsForInFlightInstallationTeardown() async {
        let system = InMemoryEventTapSystem()
        await system.pauseNextInstall()
        let manager = makeManager(system: system)
        let initialStart = Task { await manager.start() }
        await system.waitUntilInstallRequested()

        let stop = Task { await manager.stop() }
        await Task.yield()
        let restart = Task { await manager.start() }
        await Task.yield()
        let installCountBeforeResume = await system.installCount
        XCTAssertEqual(installCountBeforeResume, 1)

        await system.resumeInstall()
        await stop.value

        let restartStatus = await restart.value
        let initialStartStatus = await initialStart.value
        let installCount = await system.installCount
        let invalidateCount = await system.invalidateCount
        XCTAssertEqual(restartStatus, .active)
        XCTAssertEqual(initialStartStatus, .stopped)
        XCTAssertEqual(installCount, 2)
        XCTAssertEqual(invalidateCount, 1)
    }

    func testCurrentGenerationSynchronouslyReturnsHandlerDispositionAndStaleGenerationPasses() async {
        let system = InMemoryEventTapSystem()
        let manager = makeManager(system: system) { signal in
            guard case .key = signal else { return .passThrough }
            return .consume
        }
        _ = await manager.start()
        let enabledInstallations = await system.enabledInstallations
        let staleInstallation = enabledInstallations[0]
        let key = EventTapSignal.key(
            EventTapKeySignal(
                kind: .keyDown,
                hardwareKeyCode: 4,
                modifierFlags: 0,
                isRepeat: false
            )
        )

        let activeDisposition = await system.emit(key)
        XCTAssertEqual(activeDisposition, .consume)

        await manager.stop()
        let staleDisposition = await system.emit(key, from: staleInstallation)
        XCTAssertEqual(staleDisposition, .passThrough)

        _ = await manager.start()
        let restartedDisposition = await system.emit(key)
        XCTAssertEqual(restartedDisposition, .consume)
    }

    func testCoreGraphicsCallbackPackagesNonTextMetadataAndPassesRawEventThrough() throws {
        let capture = EventTapSignalCapture()
        let callbackBox = MacOSEventTapCallbackBox { signal in
            capture.record(signal)
            return .passThrough
        }
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 42, keyDown: true)
        )
        event.flags = [.maskCommand, .maskShift]
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)

        let returned = try XCTUnwrap(
            callbackBox.receive(type: .keyDown, event: event)
        ).takeUnretainedValue()

        XCTAssertTrue(returned === event)
        XCTAssertEqual(
            capture.signal,
            .key(
                EventTapKeySignal(
                    kind: .keyDown,
                    hardwareKeyCode: 42,
                    modifierFlags: event.flags.rawValue,
                    isRepeat: true
                )
            )
        )
    }

    func testCoreGraphicsCallbackClassifiesKeyUpAndModifierChangesAsNonRepeats() throws {
        let capture = EventTapSignalCapture()
        let callbackBox = MacOSEventTapCallbackBox { signal in
            capture.record(signal)
            return .passThrough
        }
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: false)
        )
        event.flags = [.maskControl]
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)

        let returnedKeyUp = try XCTUnwrap(
            callbackBox.receive(type: .keyUp, event: event)
        ).takeUnretainedValue()
        XCTAssertTrue(returnedKeyUp === event)
        XCTAssertEqual(
            capture.signal,
            .key(
                EventTapKeySignal(
                    kind: .keyUp,
                    hardwareKeyCode: 59,
                    modifierFlags: event.flags.rawValue,
                    isRepeat: false
                )
            )
        )

        let returnedFlagsChanged = try XCTUnwrap(
            callbackBox.receive(type: .flagsChanged, event: event)
        ).takeUnretainedValue()
        XCTAssertTrue(returnedFlagsChanged === event)
        XCTAssertEqual(
            capture.signal,
            .key(
                EventTapKeySignal(
                    kind: .flagsChanged,
                    hardwareKeyCode: 59,
                    modifierFlags: event.flags.rawValue,
                    isRepeat: false
                )
            )
        )
    }

    func testCoreGraphicsCallbackReturnsNilOnlyForRecognizedConsumedSignal() throws {
        let capture = EventTapSignalCapture()
        let callbackBox = MacOSEventTapCallbackBox { signal in
            capture.record(signal)
            return .consume
        }
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 4, keyDown: true)
        )

        XCTAssertNil(callbackBox.receive(type: .keyDown, event: event))
        XCTAssertEqual(capture.count, 1)

        let returnedUnsupported = try XCTUnwrap(
            callbackBox.receive(type: .mouseMoved, event: event)
        ).takeUnretainedValue()
        XCTAssertTrue(returnedUnsupported === event)
        XCTAssertEqual(capture.count, 1)
    }

    private func makeManager(
        system: InMemoryEventTapSystem,
        handler: @escaping @Sendable (EventTapSignal) -> EventTapEventDisposition = {
            _ in .passThrough
        }
    ) -> EventTapManager {
        EventTapManager(system: system, handler: handler)
    }
}

private final class EventTapSignalCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedSignal: EventTapSignal?
    private var recordedCount = 0

    var signal: EventTapSignal? {
        lock.withLock { capturedSignal }
    }

    var count: Int {
        lock.withLock { recordedCount }
    }

    func record(_ signal: EventTapSignal) {
        lock.withLock {
            capturedSignal = signal
            recordedCount += 1
        }
    }
}
