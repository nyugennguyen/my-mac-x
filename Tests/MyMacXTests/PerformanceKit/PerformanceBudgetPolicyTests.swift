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

import XCTest
@testable import MyMacX

final class PerformanceBudgetPolicyTests: XCTestCase {
    func testMeterUsesTheInjectedMonotonicClock() {
        let clock = ScriptedPerformanceClock([1_000_000, 3_500_000])
        let meter = PerformanceMeter(clock: clock)

        let elapsed = meter.measure {}

        XCTAssertEqual(elapsed, PerformanceDuration(nanoseconds: 2_500_000))
    }

    func testPublicBetaWorkloadPassesAtEveryBudget() {
        let observation = PerformanceObservation(
            idleCPUPercent: [0.2, 0.7, 1.0],
            eventToActionStart: [.milliseconds(25), PerformanceDuration(nanoseconds: 99_999_999)],
            overlayPreviewCalculation: [.milliseconds(2), PerformanceDuration(nanoseconds: 7_999_999)],
            residentMemoryBytesBefore: 100_000_000,
            residentMemoryBytesAfter: 100_000_000 + (5 * 1_024 * 1_024),
            completedActions: 500,
            completedDisplayChanges: 100,
            observerCountBefore: 3,
            observerCountAfter: 3
        )

        let evaluation = PerformanceBudgetPolicy.publicBeta.evaluate(observation)

        XCTAssertTrue(evaluation.isWithinBudget)
        XCTAssertEqual(evaluation.failures, [])
    }

    func testEveryExceededBudgetIsReportedTogether() {
        let observation = PerformanceObservation(
            idleCPUPercent: [1.1],
            eventToActionStart: [.milliseconds(100)],
            overlayPreviewCalculation: [.milliseconds(8)],
            residentMemoryBytesBefore: 100_000_000,
            residentMemoryBytesAfter: 106_000_000,
            completedActions: 500,
            completedDisplayChanges: 100,
            observerCountBefore: 3,
            observerCountAfter: 4
        )

        let evaluation = PerformanceBudgetPolicy.publicBeta.evaluate(observation)

        XCTAssertFalse(evaluation.isWithinBudget)
        XCTAssertEqual(
            Set(evaluation.failures),
            Set([
                .exceeded(.idleCPU),
                .exceeded(.eventToActionStart),
                .exceeded(.overlayPreviewCalculation),
                .exceeded(.residentMemoryGrowth),
                .exceeded(.observerGrowth),
            ])
        )
    }

    func testMissingSamplesAndShortMemoryWorkloadFailClosed() {
        let observation = PerformanceObservation(
            idleCPUPercent: [],
            eventToActionStart: [],
            overlayPreviewCalculation: [],
            residentMemoryBytesBefore: 100_000_000,
            residentMemoryBytesAfter: 99_000_000,
            completedActions: 499,
            completedDisplayChanges: 99,
            observerCountBefore: 3,
            observerCountAfter: 3
        )

        let evaluation = PerformanceBudgetPolicy.publicBeta.evaluate(observation)

        XCTAssertEqual(
            Set(evaluation.failures),
            Set([
                .missing(.idleCPU),
                .missing(.eventToActionStart),
                .missing(.overlayPreviewCalculation),
                .insufficientWorkload(
                    requiredActions: 500,
                    completedActions: 499,
                    requiredDisplayChanges: 100,
                    completedDisplayChanges: 99
                ),
            ])
        )
    }

    func testP95IgnoresOneOutlierInTwentySamplesButNotTwo() {
        let base = PerformanceObservation(
            idleCPUPercent: Array(repeating: 0.5, count: 20),
            eventToActionStart: Array(repeating: .milliseconds(20), count: 19) + [.milliseconds(200)],
            overlayPreviewCalculation: Array(repeating: .milliseconds(2), count: 20),
            residentMemoryBytesBefore: 100,
            residentMemoryBytesAfter: 90,
            completedActions: 500,
            completedDisplayChanges: 100,
            observerCountBefore: 3,
            observerCountAfter: 2
        )

        XCTAssertTrue(PerformanceBudgetPolicy.publicBeta.evaluate(base).isWithinBudget)

        let twoOutliers = PerformanceObservation(
            idleCPUPercent: base.idleCPUPercent,
            eventToActionStart: Array(repeating: .milliseconds(20), count: 18)
                + [.milliseconds(200), .milliseconds(201)],
            overlayPreviewCalculation: base.overlayPreviewCalculation,
            residentMemoryBytesBefore: base.residentMemoryBytesBefore,
            residentMemoryBytesAfter: base.residentMemoryBytesAfter,
            completedActions: base.completedActions,
            completedDisplayChanges: base.completedDisplayChanges,
            observerCountBefore: base.observerCountBefore,
            observerCountAfter: base.observerCountAfter
        )

        XCTAssertEqual(
            PerformanceBudgetPolicy.publicBeta.evaluate(twoOutliers).failures,
            [.exceeded(.eventToActionStart)]
        )
    }

    func testInvalidSamplesAndConfigurationFailClosed() {
        let policy = PerformanceBudgetPolicy(
            maximumIdleCPUPercentP95: -.infinity,
            maximumEventToActionStartP95: .milliseconds(100),
            maximumOverlayPreviewCalculationP95: .milliseconds(8),
            maximumResidentMemoryGrowthBytes: 0,
            requiredActionsForMemoryBudget: 0,
            requiredDisplayChangesForObserverBudget: 0
        )
        let observation = PerformanceObservation(
            idleCPUPercent: [.nan],
            eventToActionStart: [.milliseconds(1)],
            overlayPreviewCalculation: [.milliseconds(1)],
            residentMemoryBytesBefore: 0,
            residentMemoryBytesAfter: 0,
            completedActions: -1,
            completedDisplayChanges: -1,
            observerCountBefore: -1,
            observerCountAfter: -1
        )

        XCTAssertEqual(
            Set(policy.evaluate(observation).failures),
            Set([.invalid(.idleCPU), .invalid(.residentMemoryGrowth), .invalid(.observerGrowth)])
        )
    }

    func testMillisecondsSaturateInsteadOfWrapping() {
        XCTAssertEqual(
            PerformanceDuration.milliseconds(UInt64.max),
            PerformanceDuration(nanoseconds: UInt64.max)
        )
    }

    func testProductionInstrumentationBuildsOneCoherentObservationFromRuntimeHooks() {
        let clock = ScriptedPerformanceClock([100, 160, 200, 240])
        let sampler = ScriptedPerformanceSystemSampler(memory: [1_000, 1_400], observers: [3, 3])
        let instrumentation = ProductionPerformanceInstrumentation(clock: clock, system: sampler)

        instrumentation.recordIdleCPU(percent: 0.4)
        instrumentation.recordEventToActionStart(eventReceivedAt: 40)
        instrumentation.measureOverlayPreviewCalculation {}
        instrumentation.recordCompletedAction()
        instrumentation.recordDisplayChange()

        XCTAssertEqual(
            instrumentation.observation(),
            PerformanceObservation(
                idleCPUPercent: [0.4],
                eventToActionStart: [PerformanceDuration(nanoseconds: 60)],
                overlayPreviewCalculation: [PerformanceDuration(nanoseconds: 40)],
                residentMemoryBytesBefore: 1_000,
                residentMemoryBytesAfter: 1_400,
                completedActions: 1,
                completedDisplayChanges: 1,
                observerCountBefore: 3,
                observerCountAfter: 3
            )
        )
    }
}

private final class ScriptedPerformanceSystemSampler: PerformanceSystemSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var memory: [UInt64]
    private var observers: [Int]
    init(memory: [UInt64], observers: [Int]) { self.memory = memory; self.observers = observers }
    func residentMemoryBytes() -> UInt64 { lock.withLock { memory.removeFirst() } }
    func observerCount() -> Int { lock.withLock { observers.removeFirst() } }
}

private final class ScriptedPerformanceClock: PerformanceClock, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt64]

    init(_ values: [UInt64]) {
        self.values = values
    }

    func nowNanoseconds() -> UInt64 {
        lock.withLock { values.removeFirst() }
    }
}
