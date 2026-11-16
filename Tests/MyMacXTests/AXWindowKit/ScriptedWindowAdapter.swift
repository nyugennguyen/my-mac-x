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
@testable import MyMacX

actor ScriptedWindowAdapter: AccessibilityWindowAdapting, AccessibilityWindowMutationAdapting {
    enum MutationStep: Sendable {
        case inspect(
            WindowIdentity,
            frame: CGRect,
            kind: WindowKind = .standard,
            capabilities: WindowCapabilities
        )
        case inspectFailure(WindowIdentity, AccessibilityWindowOperationFailure)
        case writeTarget(
            WindowIdentity,
            frame: CGRect,
            result: AccessibilityWindowWriteResult
        )
        case writeTargetAxes(
            WindowIdentity,
            frame: CGRect,
            axes: AccessibilityFrameAxes,
            result: AccessibilityWindowWriteResult
        )
        case writeRollback(
            WindowIdentity,
            frame: CGRect,
            result: AccessibilityWindowWriteResult
        )
        case writeRollbackAxes(
            WindowIdentity,
            frame: CGRect,
            axes: AccessibilityFrameAxes,
            result: AccessibilityWindowWriteResult
        )
    }

    private var captures: [AccessibilityWindowCapture]
    private var mutationSteps: [MutationStep]
    private(set) var captureCount = 0
    private(set) var inspectionCount = 0
    private(set) var targetWriteCount = 0
    private(set) var rollbackWriteCount = 0

    var remainingMutationStepCount: Int {
        mutationSteps.count
    }

    init(
        captures: [AccessibilityWindowCapture],
        mutationSteps: [MutationStep] = []
    ) {
        precondition(!captures.isEmpty)
        self.captures = captures
        self.mutationSteps = mutationSteps
    }

    func captureFocusedWindow() -> AccessibilityWindowCapture {
        captureCount += 1

        if captures.count == 1 {
            return captures[0]
        }

        return captures.removeFirst()
    }

    func inspectWindow(_ identity: WindowIdentity) -> AccessibilityWindowInspectionResult {
        inspectionCount += 1
        guard !mutationSteps.isEmpty else { return .failure(.rejected) }

        switch mutationSteps.removeFirst() {
        case let .inspect(expectedIdentity, frame, kind, capabilities)
                where expectedIdentity == identity:
            return .available(
                AccessibilityWindowInspection(
                    frame: frame,
                    kind: kind,
                    capabilities: capabilities
                )
            )
        case let .inspectFailure(expectedIdentity, failure)
                where expectedIdentity == identity:
            return .failure(failure)
        case .inspect, .inspectFailure, .writeTarget, .writeTargetAxes,
                .writeRollback, .writeRollbackAxes:
            return .failure(.rejected)
        }
    }

    func writeFrame(
        _ request: AccessibilityFrameWriteRequest,
        to identity: WindowIdentity
    ) -> AccessibilityWindowWriteResult {
        guard !mutationSteps.isEmpty else { return .failure(.rejected) }

        switch (request.mode, mutationSteps.removeFirst()) {
        case let (.target, .writeTarget(expectedIdentity, expectedFrame, result))
                where expectedIdentity == identity
                && expectedFrame == request.frame.cgRect
                && request.axes == .all:
            targetWriteCount += 1
            return result
        case let (.target, .writeTargetAxes(expectedIdentity, expectedFrame, axes, result))
                where expectedIdentity == identity
                && expectedFrame == request.frame.cgRect
                && axes == request.axes:
            targetWriteCount += 1
            return result
        case let (.rollback, .writeRollback(expectedIdentity, expectedFrame, result))
                where expectedIdentity == identity
                && expectedFrame == request.frame.cgRect
                && request.axes == .all:
            rollbackWriteCount += 1
            return result
        case let (.rollback, .writeRollbackAxes(expectedIdentity, expectedFrame, axes, result))
                where expectedIdentity == identity
                && expectedFrame == request.frame.cgRect
                && axes == request.axes:
            rollbackWriteCount += 1
            return result
        default:
            return .failure(.rejected)
        }
    }
}

extension WindowCapabilities {
    static let movableAndResizable = WindowCapabilities(
        isMovable: true,
        isResizable: true,
        minimized: .inactive,
        nativeFullScreen: .unavailable
    )
}

actor ScriptedWindowMutationClock: WindowMutationClock {
    private var instants: [Duration]

    init(instants: [Duration]) {
        precondition(!instants.isEmpty)
        self.instants = instants
    }

    func now() -> Duration {
        if instants.count == 1 {
            return instants[0]
        }
        return instants.removeFirst()
    }
}
