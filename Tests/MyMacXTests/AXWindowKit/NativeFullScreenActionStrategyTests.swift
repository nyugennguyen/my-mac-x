import XCTest
@testable import MyMacX

final class NativeFullScreenActionStrategyTests: XCTestCase {
    func testAcceptedRequestSettlesAsExplicitlyUnverified() async {
        let identity = WindowIdentity()
        let adapter = ScriptedNativeFullScreenAdapter(
            requests: [.result(identity, .accepted)],
            probes: [.result(identity, .present)]
        )
        let strategy = makeStrategy(
            adapter: adapter,
            clock: ScriptedNativeFullScreenClock(immediate: [.seconds(1)])
        )

        let result = await strategy.perform(on: identity)

        XCTAssertEqual(result, .acceptedButUnverified)
    }

    func testRejectedRequestReturnsRejectedWithoutWaitingOrProbing() async {
        let identity = WindowIdentity()
        let adapter = ScriptedNativeFullScreenAdapter(
            requests: [.result(identity, .rejected)]
        )
        let clock = ScriptedNativeFullScreenClock(immediate: [])

        let result = await makeStrategy(adapter: adapter, clock: clock).perform(on: identity)
        let probeCount = await adapter.probeCount

        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(probeCount, 0)
    }

    func testAcceptedRequestReportsExactCapturedWindowDisappearedDuringSettle() async {
        let identity = WindowIdentity()
        let otherIdentity = WindowIdentity()
        let adapter = ScriptedNativeFullScreenAdapter(
            requests: [.result(identity, .accepted)],
            probes: [.result(identity, .windowDisappeared)]
        )
        let strategy = makeStrategy(
            adapter: adapter,
            clock: ScriptedNativeFullScreenClock(immediate: [.seconds(1)])
        )

        let result = await strategy.perform(on: identity)
        let requestedIdentities = await adapter.requestedIdentities
        let probedIdentities = await adapter.probedIdentities

        XCTAssertEqual(result, .windowDisappeared)
        XCTAssertEqual(requestedIdentities, [identity])
        XCTAssertEqual(probedIdentities, [identity])
        XCTAssertFalse(requestedIdentities.contains(otherIdentity))
    }

    func testFiniteDeadlineReturnsTimedOutWhenRequestDoesNotComplete() async {
        let identity = WindowIdentity()
        let adapter = ScriptedNativeFullScreenAdapter(requests: [.suspend(identity)])
        let strategy = makeStrategy(
            adapter: adapter,
            clock: ScriptedNativeFullScreenClock(immediate: [.seconds(5)])
        )

        let result = await strategy.perform(on: identity)

        XCTAssertEqual(result, .timedOut)
    }

    func testFiniteDeadlineDoesNotAwaitARequestThatIgnoresCancellation() async {
        let identity = WindowIdentity()
        let gate = ScriptedNativeFullScreenRequestGate()
        let adapter = ScriptedNativeFullScreenAdapter(
            requests: [.ignoreCancellation(identity, gate: gate, result: .accepted)]
        )
        let strategy = makeStrategy(
            adapter: adapter,
            clock: ScriptedNativeFullScreenClock(immediate: [.seconds(5)])
        )
        let returned = expectation(description: "deadline returned")
        let action = Task {
            let result = await strategy.perform(on: identity)
            returned.fulfill()
            return result
        }
        while await adapter.requestCount == 0 {
            await Task.yield()
        }

        await fulfillment(of: [returned], timeout: 1)
        await gate.release()
        let result = await action.value

        XCTAssertEqual(result, .timedOut)
    }

    func testLateAcceptedRequestIsIgnoredAfterDeadlineResolution() async {
        let identity = WindowIdentity()
        let gate = ScriptedNativeFullScreenRequestGate()
        let adapter = ScriptedNativeFullScreenAdapter(
            requests: [.ignoreCancellation(identity, gate: gate, result: .accepted)],
            probes: [.result(identity, .present)]
        )
        let strategy = makeStrategy(
            adapter: adapter,
            clock: ScriptedNativeFullScreenClock(immediate: [.seconds(5)])
        )

        let returned = expectation(description: "deadline returned before late Adapter result")
        let action = Task {
            let result = await strategy.perform(on: identity)
            returned.fulfill()
            return result
        }
        while await adapter.requestCount == 0 {
            await Task.yield()
        }

        await fulfillment(of: [returned], timeout: 1)
        await gate.release()
        while await adapter.completedRequestCount == 0 {
            await Task.yield()
        }
        for _ in 0..<10 { await Task.yield() }
        let result = await action.value
        let probeCount = await adapter.probeCount

        XCTAssertEqual(result, .timedOut)
        XCTAssertEqual(probeCount, 0)
    }

    func testCallerCancellationReturnsCancelled() async {
        let identity = WindowIdentity()
        let adapter = ScriptedNativeFullScreenAdapter(requests: [.suspend(identity)])
        let strategy = makeStrategy(
            adapter: adapter,
            clock: ScriptedNativeFullScreenClock(immediate: [])
        )
        let action = Task { await strategy.perform(on: identity) }
        while await adapter.requestCount == 0 {
            await Task.yield()
        }

        action.cancel()
        let result = await action.value

        XCTAssertEqual(result, .cancelled)
    }

    func testCallerCancellationDoesNotAwaitARequestThatIgnoresCancellation() async {
        let identity = WindowIdentity()
        let gate = ScriptedNativeFullScreenRequestGate()
        let adapter = ScriptedNativeFullScreenAdapter(
            requests: [.ignoreCancellation(identity, gate: gate, result: .accepted)]
        )
        let strategy = makeStrategy(
            adapter: adapter,
            clock: ScriptedNativeFullScreenClock(immediate: [])
        )
        let returned = expectation(description: "cancellation returned")
        let action = Task {
            let result = await strategy.perform(on: identity)
            returned.fulfill()
            return result
        }
        while await adapter.requestCount == 0 {
            await Task.yield()
        }

        action.cancel()
        await fulfillment(of: [returned], timeout: 1)
        await gate.release()
        let result = await action.value

        XCTAssertEqual(result, .cancelled)
    }

    func testWaitingWindowDoesNotBlockAnotherWindowLane() async {
        let waitingIdentity = WindowIdentity()
        let independentIdentity = WindowIdentity()
        let adapter = ScriptedNativeFullScreenAdapter(
            requests: [
                .suspend(waitingIdentity),
                .result(independentIdentity, .accepted)
            ],
            probes: [.result(independentIdentity, .present)]
        )
        let strategy = makeStrategy(
            adapter: adapter,
            clock: ScriptedNativeFullScreenClock(immediate: [.seconds(1)])
        )
        let waitingAction = Task { await strategy.perform(on: waitingIdentity) }
        while await adapter.requestCount == 0 {
            await Task.yield()
        }

        let independentResult = await strategy.perform(on: independentIdentity)

        XCTAssertEqual(independentResult, .acceptedButUnverified)
        waitingAction.cancel()
        let waitingResult = await waitingAction.value
        XCTAssertEqual(waitingResult, .cancelled)
    }

    private func makeStrategy(
        adapter: ScriptedNativeFullScreenAdapter,
        clock: ScriptedNativeFullScreenClock
    ) -> NativeFullScreenActionStrategy {
        NativeFullScreenActionStrategy(
            adapter: adapter,
            clock: clock,
            policy: NativeFullScreenActionPolicy(
                settleDelay: .seconds(1),
                deadline: .seconds(5)
            )
        )
    }
}

private actor ScriptedNativeFullScreenAdapter: NativeFullScreenAccessibilityAdapting {
    enum RequestStep: Sendable {
        case result(WindowIdentity, NativeFullScreenRequestResult)
        case suspend(WindowIdentity)
        case ignoreCancellation(
            WindowIdentity,
            gate: ScriptedNativeFullScreenRequestGate,
            result: NativeFullScreenRequestResult
        )
    }

    enum ProbeStep: Sendable {
        case result(WindowIdentity, NativeFullScreenProbeResult)
    }

    private var requests: [RequestStep]
    private var probes: [ProbeStep]
    private(set) var requestedIdentities: [WindowIdentity] = []
    private(set) var probedIdentities: [WindowIdentity] = []
    private(set) var completedRequestCount = 0

    var requestCount: Int { requestedIdentities.count }
    var probeCount: Int { probedIdentities.count }

    init(requests: [RequestStep], probes: [ProbeStep] = []) {
        self.requests = requests
        self.probes = probes
    }

    func requestNativeFullScreen(for identity: WindowIdentity) async -> NativeFullScreenRequestResult {
        requestedIdentities.append(identity)
        guard !requests.isEmpty else { return .rejected }

        switch requests.removeFirst() {
        case let .result(expectedIdentity, result) where expectedIdentity == identity:
            completedRequestCount += 1
            return result
        case let .suspend(expectedIdentity) where expectedIdentity == identity:
            do {
                try await Task.sleep(for: .seconds(3_600))
                completedRequestCount += 1
                return .rejected
            } catch {
                completedRequestCount += 1
                return .cancelled
            }
        case let .ignoreCancellation(expectedIdentity, gate, result)
                where expectedIdentity == identity:
            await gate.wait()
            completedRequestCount += 1
            return result
        case .result, .suspend, .ignoreCancellation:
            completedRequestCount += 1
            return .rejected
        }
    }

    func probeWindow(_ identity: WindowIdentity) -> NativeFullScreenProbeResult {
        probedIdentities.append(identity)
        guard !probes.isEmpty else { return .rejected }

        switch probes.removeFirst() {
        case let .result(expectedIdentity, result) where expectedIdentity == identity:
            return result
        case .result:
            return .rejected
        }
    }
}

private actor ScriptedNativeFullScreenRequestGate {
    private var isReleased = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ScriptedNativeFullScreenClock: NativeFullScreenClock {
    private let immediate: [Duration]

    init(immediate: [Duration]) {
        self.immediate = immediate
    }

    func sleep(for duration: Duration) async throws {
        if immediate.contains(duration) { return }
        try await Task.sleep(for: .seconds(3_600))
    }
}
