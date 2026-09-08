import XCTest

@testable import MyMacX

final class TriggerDwellEngineTests: XCTestCase {
    func testUpdatedConfigurationAppliesToNextDwellWithoutRecreatingEngine() async throws {
        let clock = ManualTriggerDwellClock()
        let engine = TriggerDwellEngine(
            configuration: try TriggerDwellConfiguration(dwellDuration: .milliseconds(120)),
            clock: clock
        )
        let probe = TriggerDwellEventProbe()
        await probe.start(events: await engine.events)
        let first = DisplayID(rawValue: 91)
        let second = DisplayID(rawValue: 92)

        await engine.update(.inside(first))
        await advanceRegisteredDwell(clock, by: .milliseconds(120))
        await engine.update(.outside)
        await clock.advance(by: TriggerDwellConfiguration.exitHysteresisDuration)
        await engine.updateConfiguration(
            try TriggerDwellConfiguration(dwellDuration: .milliseconds(180))
        )
        await engine.update(.inside(second))
        await clock.advance(by: .milliseconds(179))
        await assertEvents([.activated(first), .deactivated(first)], in: probe)
        await clock.advance(by: .milliseconds(1))

        await assertEvents(
            [.activated(first), .deactivated(first), .activated(second)],
            in: probe
        )
    }

    func testRepeatedInsideSamplesDoNotPostponeConfiguredDwell() async throws {
        let clock = ManualTriggerDwellClock()
        let engine = TriggerDwellEngine(
            configuration: try TriggerDwellConfiguration(
                dwellDuration: .milliseconds(120)
            ),
            clock: clock
        )
        let probe = TriggerDwellEventProbe()
        await probe.start(events: await engine.events)
        let target = DisplayID(rawValue: 41)

        await engine.update(.inside(target))
        await clock.advance(by: .milliseconds(60))
        await engine.update(.inside(target))
        await clock.advance(by: .milliseconds(59))
        await engine.update(.inside(target))
        await assertEvents([], in: probe)

        await clock.advance(by: .milliseconds(1))
        await assertEvents([.activated(target)], in: probe)

        await engine.update(.inside(target))
        await clock.advance(by: .milliseconds(500))
        await assertEvents([.activated(target)], in: probe)
    }

    func testLeavingBeforeDwellCancelsAndReentryRequiresTheFullDwell() async throws {
        let clock = ManualTriggerDwellClock()
        let engine = TriggerDwellEngine(
            configuration: try TriggerDwellConfiguration(
                dwellDuration: .milliseconds(180)
            ),
            clock: clock
        )
        let probe = TriggerDwellEventProbe()
        await probe.start(events: await engine.events)
        let target = DisplayID(rawValue: 42)

        await engine.update(.inside(target))
        await clock.advance(by: .milliseconds(179))
        await engine.update(.outside)
        await clock.advance(by: .milliseconds(1))
        await assertEvents([], in: probe)

        await engine.update(.inside(target))
        await clock.advance(by: .milliseconds(179))
        await assertEvents([], in: probe)
        await clock.advance(by: .milliseconds(1))
        await assertEvents([.activated(target)], in: probe)
    }

    func testBriefExitAndSameDisplayReentryDoNotFlicker() async throws {
        let clock = ManualTriggerDwellClock()
        let engine = TriggerDwellEngine(
            configuration: try TriggerDwellConfiguration(
                dwellDuration: .milliseconds(150)
            ),
            clock: clock
        )
        let probe = TriggerDwellEventProbe()
        await probe.start(events: await engine.events)
        let target = DisplayID(rawValue: 43)

        await engine.update(.inside(target))
        await clock.advance(by: .milliseconds(150))
        await assertEvents([.activated(target)], in: probe)

        await engine.update(.outside)
        await clock.advance(
            by: TriggerDwellConfiguration.exitHysteresisDuration - .milliseconds(1)
        )
        await engine.update(.inside(target))
        await clock.advance(by: .seconds(1))

        await assertEvents([.activated(target)], in: probe)
    }

    func testRepeatedOutsideSamplesDoNotPostponeBoundedDeactivation() async throws {
        let clock = ManualTriggerDwellClock()
        let engine = TriggerDwellEngine(
            configuration: try TriggerDwellConfiguration(
                dwellDuration: .milliseconds(150)
            ),
            clock: clock
        )
        let probe = TriggerDwellEventProbe()
        await probe.start(events: await engine.events)
        let target = DisplayID(rawValue: 44)

        await engine.update(.inside(target))
        await clock.advance(by: .milliseconds(150))
        await assertEvents([.activated(target)], in: probe)

        await engine.update(.outside)
        await clock.advance(
            by: TriggerDwellConfiguration.exitHysteresisDuration / 2
        )
        await engine.update(.outside)
        await clock.advance(
            by: TriggerDwellConfiguration.exitHysteresisDuration / 2
        )

        await assertEvents(
            [.activated(target), .deactivated(target)],
            in: probe
        )
    }

    func testSlowConsumerDoesNotLoseTerminalDeactivationDuringSustainedDisplayChanges() async throws {
        let clock = ManualTriggerDwellClock()
        let engine = TriggerDwellEngine(
            configuration: try TriggerDwellConfiguration(
                dwellDuration: .milliseconds(120)
            ),
            clock: clock
        )
        let events = await engine.events
        let displays = (100...110).map { DisplayID(rawValue: UInt32($0)) }

        for display in displays {
            await engine.update(.inside(display))
            await advanceRegisteredDwell(clock, by: .milliseconds(120))
        }

        let probe = TriggerDwellEventProbe()
        await probe.start(events: events)
        let expected: [TriggerDwellEvent] = displays.enumerated().flatMap { index, display in
            index == displays.startIndex
                ? [.activated(display)]
                : [.deactivated(displays[index - 1]), .activated(display)]
        }

        await assertEvents(expected, in: probe)
    }

    func testRejectsDwellDurationsOutsideTheSupportedRange() {
        XCTAssertThrowsError(
            try TriggerDwellConfiguration(dwellDuration: .milliseconds(119))
        )
        XCTAssertNoThrow(
            try TriggerDwellConfiguration(dwellDuration: .milliseconds(120))
        )
        XCTAssertNoThrow(
            try TriggerDwellConfiguration(dwellDuration: .milliseconds(180))
        )
        XCTAssertThrowsError(
            try TriggerDwellConfiguration(dwellDuration: .milliseconds(181))
        )
    }
    func testRapidCrossDisplayTransitionsDoNotLoseActiveDisplayDeactivation() async throws {
        let clock = ManualTriggerDwellClock()
        let engine = TriggerDwellEngine(
            configuration: try TriggerDwellConfiguration(
                dwellDuration: .milliseconds(150)
            ),
            clock: clock
        )
        let probe = TriggerDwellEventProbe()
        await probe.start(events: await engine.events)
        let displayA = DisplayID(rawValue: 1)
        let displayB = DisplayID(rawValue: 2)
        let displayC = DisplayID(rawValue: 3)
        let displayD = DisplayID(rawValue: 4)

        // Activate Display A.
        await engine.update(.inside(displayA))
        await advanceRegisteredDwell(clock, by: .milliseconds(150))
        await assertEvents([.activated(displayA)], in: probe)

        // Rapid cross-Display transitions — no dwell completes between them.
        await engine.update(.inside(displayB))
        await engine.update(.inside(displayC))
        await engine.update(.inside(displayD))

        // Exactly one deactivation: A was the only active display.
        // B, C, D were only dwelling — no spurious deactivations.
        await assertEvents(
            [.activated(displayA), .deactivated(displayA)],
            in: probe
        )

        // Complete dwell for D and verify activation.
        await advanceRegisteredDwell(clock, by: .milliseconds(150))
        await assertEvents(
            [.activated(displayA), .deactivated(displayA), .activated(displayD)],
            in: probe
        )
    }
}

private actor ManualTriggerDwellClock: TriggerDwellClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var current = Duration.zero
    private var sleepers: [UUID: Sleeper] = [:]

    func now() -> Duration {
        current
    }

    func sleep(until deadline: Duration) async throws {
        guard deadline > current else { return }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = Sleeper(
                    deadline: deadline,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.cancelSleep(id: id) }
        }
    }

    func advance(by duration: Duration) {
        precondition(duration >= .zero)
        current += duration

        let due = sleepers.filter { $0.value.deadline <= current }
        for (id, sleeper) in due {
            sleepers[id] = nil
            sleeper.continuation.resume()
        }
    }

    func pendingSleepCount() -> Int {
        sleepers.count
    }

    private func cancelSleep(id: UUID) {
        guard let sleeper = sleepers.removeValue(forKey: id) else { return }
        sleeper.continuation.resume(throwing: CancellationError())
    }
}

private actor TriggerDwellEventProbe {
    private var values: [TriggerDwellEvent] = []
    private var task: Task<Void, Never>?

    func start(events: AsyncStream<TriggerDwellEvent>) {
        task?.cancel()
        task = Task { [weak self] in
            for await event in events {
                await self?.record(event)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    func snapshot() -> [TriggerDwellEvent] {
        values
    }

    private func record(_ event: TriggerDwellEvent) {
        values.append(event)
    }
}

private func assertEvents(
    _ expected: [TriggerDwellEvent],
    in probe: TriggerDwellEventProbe,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<10 {
        await Task.yield()
    }
    for _ in 0..<100 {
        if await probe.snapshot() == expected { return }
        await Task.yield()
    }

    let actual = await probe.snapshot()
    XCTAssertEqual(actual, expected, file: file, line: line)
}

private func advanceRegisteredDwell(
    _ clock: ManualTriggerDwellClock,
    by duration: Duration
) async {
    for _ in 0..<100 {
        if await clock.pendingSleepCount() == 1 { break }
        await Task.yield()
    }
    let pendingSleepCount = await clock.pendingSleepCount()
    XCTAssertEqual(pendingSleepCount, 1)
    await clock.advance(by: duration)
    for _ in 0..<100 {
        await Task.yield()
    }
}
