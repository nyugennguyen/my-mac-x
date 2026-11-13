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

import Foundation

/// Internal Native Full Screen Interface used by the Window Action Module.
///
/// An accepted request is deliberately not success: public cross-process APIs expose a
/// documented Full Screen control, but no documented attribute that verifies the state.
protocol NativeFullScreenActionPerforming: Sendable {
    func perform(on window: WindowIdentity) async -> NativeFullScreenActionResult
}

enum NativeFullScreenActionResult: Equatable, Sendable {
    case acceptedButUnverified
    case rejected
    case accessibilityPermissionRequired
    case windowDisappeared
    case temporarilyUnavailable
    case timedOut
    case cancelled
}

protocol NativeFullScreenAccessibilityAdapting: Sendable {
    func requestNativeFullScreen(
        for identity: WindowIdentity
    ) async -> NativeFullScreenRequestResult

    /// Probes only whether the exact captured AX element remains usable.
    /// It does not infer Full Screen state from geometry or any private attribute.
    func probeWindow(_ identity: WindowIdentity) async -> NativeFullScreenProbeResult
}

enum NativeFullScreenRequestResult: Equatable, Sendable {
    case accepted
    case rejected
    case accessibilityPermissionRequired
    case windowDisappeared
    case temporarilyUnavailable
    case cancelled
}

enum NativeFullScreenProbeResult: Equatable, Sendable {
    case present
    case rejected
    case accessibilityPermissionRequired
    case windowDisappeared
    case temporarilyUnavailable
    case cancelled
}

protocol NativeFullScreenClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousNativeFullScreenClock: NativeFullScreenClock {
    private let clock = ContinuousClock()

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}

struct NativeFullScreenActionPolicy: Sendable {
    static let standard = Self(settleDelay: .milliseconds(750), deadline: .seconds(5))

    let settleDelay: Duration
    let deadline: Duration

    init(settleDelay: Duration, deadline: Duration) {
        precondition(settleDelay > .zero)
        precondition(deadline > settleDelay)
        self.settleDelay = settleDelay
        self.deadline = deadline
    }
}

/// Finite, stateless strategy for requesting Native Full Screen on one Captured Window.
///
/// The strategy deliberately owns no per-window lane. Each call races independently against
/// its deadline, so an awaiting request cannot serialize a request for another window.
struct NativeFullScreenActionStrategy: NativeFullScreenActionPerforming {
    private let adapter: any NativeFullScreenAccessibilityAdapting
    private let clock: any NativeFullScreenClock
    private let policy: NativeFullScreenActionPolicy

    init(
        adapter: any NativeFullScreenAccessibilityAdapting,
        clock: any NativeFullScreenClock = ContinuousNativeFullScreenClock(),
        policy: NativeFullScreenActionPolicy = .standard
    ) {
        self.adapter = adapter
        self.clock = clock
        self.policy = policy
    }

    func perform(on window: WindowIdentity) async -> NativeFullScreenActionResult {
        guard !Task.isCancelled else { return .cancelled }

        let coordinator = NativeFullScreenRaceCoordinator()
        let action = Task { [weak coordinator] in
            let result = await requestAndSettle(window)
            await coordinator?.resolve(result)
        }
        let deadline = Task { [weak coordinator] in
            do {
                try await clock.sleep(for: policy.deadline)
                await coordinator?.resolve(.timedOut)
            } catch {
                // The action or caller resolved first and cancelled this losing task.
            }
        }

        await coordinator.track(action: action, deadline: deadline)
        return await coordinator.result()
    }

    private func requestAndSettle(_ identity: WindowIdentity) async -> NativeFullScreenActionResult {
        switch await adapter.requestNativeFullScreen(for: identity) {
        case .accepted:
            break
        case .rejected:
            return .rejected
        case .accessibilityPermissionRequired:
            return .accessibilityPermissionRequired
        case .windowDisappeared:
            return .windowDisappeared
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .cancelled:
            return .cancelled
        }

        guard !Task.isCancelled else { return .cancelled }
        do {
            try await clock.sleep(for: policy.settleDelay)
        } catch {
            return .cancelled
        }

        guard !Task.isCancelled else { return .cancelled }
        switch await adapter.probeWindow(identity) {
        case .present:
            return .acceptedButUnverified
        case .rejected:
            return .rejected
        case .accessibilityPermissionRequired:
            return .accessibilityPermissionRequired
        case .windowDisappeared:
            return .windowDisappeared
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .cancelled:
            return .cancelled
        }
    }
}

/// Resolves one action exactly once without structurally awaiting the losing task.
///
/// Cancellation is still sent to the loser as cleanup. If an Adapter ignores cancellation,
/// its late result reaches `resolve` after the token is closed and is discarded.
private actor NativeFullScreenRaceCoordinator {
    private typealias Continuation = CheckedContinuation<NativeFullScreenActionResult, Never>

    private var action: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var continuation: Continuation?
    private var resolvedResult: NativeFullScreenActionResult?

    func track(action: Task<Void, Never>, deadline: Task<Void, Never>) {
        guard resolvedResult == nil else {
            action.cancel()
            deadline.cancel()
            return
        }

        self.action = action
        self.deadline = deadline
    }

    func result() async -> NativeFullScreenActionResult {
        if Task.isCancelled {
            resolve(.cancelled)
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                install(continuation)
            }
        } onCancel: {
            Task { await self.resolve(.cancelled) }
        }
    }

    func resolve(_ result: NativeFullScreenActionResult) {
        guard resolvedResult == nil else { return }

        resolvedResult = result
        let waitingContinuation = continuation
        continuation = nil

        action?.cancel()
        deadline?.cancel()
        action = nil
        deadline = nil

        waitingContinuation?.resume(returning: result)
    }

    private func install(_ continuation: Continuation) {
        if let resolvedResult {
            continuation.resume(returning: resolvedResult)
        } else {
            precondition(self.continuation == nil)
            self.continuation = continuation
        }
    }
}
