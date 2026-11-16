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

import CoreGraphics
import XCTest

@testable import MyMacX

private final class MockWindowServerSampler: WindowServerWindowSampling, @unchecked Sendable {
    var candidate: (windowID: CGWindowID, bounds: CGRect, processID: pid_t)?
    var queryBounds: [CGWindowID: CGRect] = [:]

    func windowBounds(windowID: CGWindowID) async -> CGRect? {
        queryBounds[windowID]
    }

    func topmostWindow(at point: CGPoint) async -> (windowID: CGWindowID, bounds: CGRect, processID: pid_t)? {
        candidate
    }
}

private final class MockAccessibilityWindowAdapter: AccessibilityWindowAdapting, @unchecked Sendable {
    var candidate: AccessibilityWindowCandidate?
    var delayNanoseconds: UInt64 = 0

    func captureFocusedWindow() async -> AccessibilityWindowCapture {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let candidate {
            return .candidate(candidate)
        }
        return .unsupported
    }
}

private final class MockAppRuleDecider: AppRuleDeciding, @unchecked Sendable {
    var decisionResult: AppRuleDecision = .included

    func decision(for bundleIdentifier: String?) async -> AppRuleDecision {
        decisionResult
    }
}

final class EdgeSnapTargetResolverTests: XCTestCase {
    // MARK: - Generational Guard (D-10)

    func testStaleResolutionIsCancelledAndNeverRetargets() async {
        let sampler = MockWindowServerSampler()
        sampler.candidate = (windowID: 42, bounds: CGRect(x: 100, y: 100, width: 600, height: 400), processID: 100)

        let ax = MockAccessibilityWindowAdapter()
        let identity = WindowIdentity()
        ax.candidate = AccessibilityWindowCandidate(identity: identity, capabilities: .mockWindowMoveCapabilities)
        ax.delayNanoseconds = 100_000_000 // 100 ms

        let rules = MockAppRuleDecider()
        let resolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: ax,
            appRules: rules,
            timeoutMilliseconds: 300
        )

        // Start resolve for generation 1
        async let resultGen1 = resolver.resolveTarget(
            at: CGPoint(x: 200, y: 200),
            generation: 1,
            activeGeneration: { 2 } // Generation bumped to 2 while gen 1 was resolving
        )

        let outcome = await resultGen1
        XCTAssertEqual(outcome, .failure(.staleGeneration))
    }

    // MARK: - Bounded Timeout (~0.3 s) (D-10)

    func testUnresponsiveApplicationTimesOutWithinLimit() async {
        let sampler = MockWindowServerSampler()
        sampler.candidate = (windowID: 42, bounds: CGRect(x: 100, y: 100, width: 600, height: 400), processID: 100)

        let ax = MockAccessibilityWindowAdapter()
        let identity = WindowIdentity()
        ax.candidate = AccessibilityWindowCandidate(identity: identity, capabilities: .mockWindowMoveCapabilities)
        ax.delayNanoseconds = 500_000_000 // 500 ms (exceeds 250 ms timeout)

        let rules = MockAppRuleDecider()
        let resolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: ax,
            appRules: rules,
            timeoutMilliseconds: 250
        )

        let start = ContinuousClock.now
        let outcome = await resolver.resolveTarget(
            at: CGPoint(x: 200, y: 200),
            generation: 1,
            activeGeneration: { 1 }
        )
        let elapsed = ContinuousClock.now - start

        XCTAssertEqual(outcome, .failure(.timedOut))
        XCTAssertLessThan(elapsed, .milliseconds(450))
    }

    // MARK: - AppRuleKit Exclusions Fail Closed

    func testExcludedApplicationFailsClosed() async {
        let sampler = MockWindowServerSampler()
        sampler.candidate = (windowID: 42, bounds: CGRect(x: 100, y: 100, width: 600, height: 400), processID: 100)

        let ax = MockAccessibilityWindowAdapter()
        let identity = WindowIdentity()
        ax.candidate = AccessibilityWindowCandidate(identity: identity, capabilities: .mockWindowMoveCapabilities)

        let rules = MockAppRuleDecider()
        rules.decisionResult = .excluded // App is excluded by user rule

        let resolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: ax,
            appRules: rules,
            bundleIDResolver: { _ in "com.apple.excluded" }
        )

        let outcome = await resolver.resolveTarget(
            at: CGPoint(x: 200, y: 200),
            generation: 1,
            activeGeneration: { 1 }
        )

        XCTAssertEqual(outcome, .failure(.applicationExcluded))
    }

    // MARK: - Process ID Equality Guard (Blocker 1)

    func testMismatchedProcessIDBetweenWindowServerAndAccessibilityRejectsTarget() async {
        let sampler = MockWindowServerSampler()
        sampler.candidate = (windowID: 42, bounds: CGRect(x: 100, y: 100, width: 600, height: 400), processID: 100)

        let ax = MockAccessibilityWindowAdapter()
        // Window server candidate is PID 100, but AX focused window is PID 200 (e.g. frontmost app while dragging inactive window)
        let mismatchedIdentity = WindowIdentity(processID: 200)
        ax.candidate = AccessibilityWindowCandidate(identity: mismatchedIdentity, capabilities: .mockWindowMoveCapabilities)

        let rules = MockAppRuleDecider()
        rules.decisionResult = .included

        let resolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: ax,
            appRules: rules,
            bundleIDResolver: { _ in "com.example.editor" }
        )

        let outcome = await resolver.resolveTarget(
            at: CGPoint(x: 200, y: 200),
            generation: 1,
            activeGeneration: { 1 }
        )

        XCTAssertEqual(outcome, .failure(.noEligibleWindow))
    }

    // MARK: - Successful Resolution

    func testSuccessfulResolutionCapturesEligibleWindow() async {
        let sampler = MockWindowServerSampler()
        sampler.candidate = (windowID: 42, bounds: CGRect(x: 100, y: 100, width: 600, height: 400), processID: 100)

        let ax = MockAccessibilityWindowAdapter()
        let identity = WindowIdentity(processID: 100)
        ax.candidate = AccessibilityWindowCandidate(identity: identity, capabilities: .mockWindowMoveCapabilities)

        let rules = MockAppRuleDecider()
        rules.decisionResult = .included

        let resolver = EdgeSnapTargetResolver(
            sampler: sampler,
            accessibility: ax,
            appRules: rules,
            bundleIDResolver: { _ in "com.example.editor" }
        )

        let outcome = await resolver.resolveTarget(
            at: CGPoint(x: 200, y: 200),
            generation: 1,
            activeGeneration: { 1 }
        )

        switch outcome {
        case .success(let target):
            XCTAssertEqual(target.generation, 1)
            XCTAssertEqual(target.windowID, 42)
            XCTAssertEqual(target.initialFrame, CGRect(x: 100, y: 100, width: 600, height: 400))
            XCTAssertEqual(target.windowIdentity, identity)
            XCTAssertEqual(target.bundleIdentifier, "com.example.editor")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
}

private extension WindowCapabilities {
    static var mockWindowMoveCapabilities: WindowCapabilities {
        WindowCapabilities(
            isMovable: true,
            isResizable: true,
            minimized: .inactive,
            nativeFullScreen: .inactive
        )
    }
}
