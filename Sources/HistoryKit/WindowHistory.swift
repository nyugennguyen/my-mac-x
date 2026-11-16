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
import Foundation

/// An opaque reference to one verified Window Snapshot.
///
/// Callers can retain and compare a token, but cannot construct or inspect its identity.
public struct UndoToken: Hashable, Sendable {
    private let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

/// Whether the verified destination is a Layout placement or a user-defined placement.
///
/// A non-layout destination becomes the new Restore anchor. Layout destinations retain the
/// previous non-layout anchor, which lets Restore survive consecutive Snaps.
enum WindowHistoryPlacement: Sendable {
    case layout
    case nonLayout
}

/// A Restore target expressed without a persisted Display identity.
///
/// The Window Action Engine evaluates this canonical AppKit frame against fresh screen topology
/// before mutation, so a disconnected or reordered Display cannot be used as a history key.
struct WindowRestoreAnchor: Equatable, Sendable {
    let frame: AppKitGlobalLogicalFrame

    init(_ frame: AppKitGlobalLogicalFrame) {
        self.frame = frame
    }
}

/// Opaque pending state between capturing a Window Snapshot and verified mutation.
struct WindowHistoryStaging: Hashable, Sendable {
    private let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

/// A staged Undo target. Commit it only after the caller has verified its mutation.
struct WindowHistoryUndo: Hashable, Sendable {
    let targetFrame: AppKitGlobalLogicalFrame
    private let rawValue: UUID

    init(targetFrame: AppKitGlobalLogicalFrame) {
        self.targetFrame = targetFrame
        rawValue = UUID()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

/// The internal Window History Interface.
///
/// `stage` captures a Window Snapshot before Accessibility mutation. `commit` adds history only
/// after the caller's read-back succeeds; `discard` leaves no history behind. Undo follows the
/// same two-phase rule, so a failed Undo never destroys its exact source entry.
protocol WindowHistoryManaging: Sendable {
    func stage(
        window: WindowIdentity,
        before: AppKitGlobalLogicalFrame,
        destination: WindowHistoryPlacement
    ) async -> WindowHistoryStaging

    func commit(
        _ staging: WindowHistoryStaging,
        actualFrame: AppKitGlobalLogicalFrame
    ) async -> UndoToken?

    func discard(_ staging: WindowHistoryStaging) async

    func stageUndo(token: UndoToken?, for window: WindowIdentity) async -> WindowHistoryUndo?
    func commit(_ undo: WindowHistoryUndo) async
    func discard(_ undo: WindowHistoryUndo) async

    func restore(for window: WindowIdentity) async -> WindowRestoreAnchor?
    func prune(keeping windows: Set<WindowIdentity>) async
}

/// Bounded session history used in production.
///
/// This Adapter holds no Accessibility objects, process identifiers, titles, or document data.
/// Entries are evicted in verified commit order, producing deterministic bounded retention.
actor BoundedSessionWindowHistory: WindowHistoryManaging {
    private struct PendingStage: Sendable {
        let window: WindowIdentity
        let before: AppKitGlobalLogicalFrame
        let restoreAnchor: WindowRestoreAnchor
        let destination: WindowHistoryPlacement
    }

    private struct Entry: Sendable {
        let revision: UInt64
        let token: UndoToken
        let window: WindowIdentity
        let before: AppKitGlobalLogicalFrame
        let after: AppKitGlobalLogicalFrame
        let restoreAnchor: WindowRestoreAnchor
    }

    private struct PendingUndo: Sendable {
        let window: WindowIdentity
        let token: UndoToken
        let revision: UInt64
    }

    private let capacity: Int
    private var pendingStages: [WindowHistoryStaging: PendingStage] = [:]
    private var entries: [Entry] = []
    private var pendingUndos: [WindowHistoryUndo: PendingUndo] = [:]
    private var nextRevision: UInt64 = 0

    init(capacity: Int = 32) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func stage(
        window: WindowIdentity,
        before: AppKitGlobalLogicalFrame,
        destination: WindowHistoryPlacement
    ) -> WindowHistoryStaging {
        let staging = WindowHistoryStaging()
        pendingStages[staging] = PendingStage(
            window: window,
            before: before,
            restoreAnchor: latestEntry(for: window)?.restoreAnchor ?? WindowRestoreAnchor(before),
            destination: destination
        )
        return staging
    }

    func commit(
        _ staging: WindowHistoryStaging,
        actualFrame: AppKitGlobalLogicalFrame
    ) -> UndoToken? {
        guard let pending = pendingStages.removeValue(forKey: staging),
              Self.isValid(pending.before.cgRect),
              Self.isValid(actualFrame.cgRect) else {
            return nil
        }

        let token = UndoToken()
        precondition(nextRevision < UInt64.max)
        let revision = nextRevision
        nextRevision += 1
        let restoreAnchor: WindowRestoreAnchor
        switch pending.destination {
        case .layout:
            restoreAnchor = pending.restoreAnchor
        case .nonLayout:
            restoreAnchor = WindowRestoreAnchor(actualFrame)
        }

        entries.append(Entry(
            revision: revision,
            token: token,
            window: pending.window,
            before: pending.before,
            after: actualFrame,
            restoreAnchor: restoreAnchor
        ))
        while entries.count > capacity {
            entries.removeFirst()
        }
        return token
    }

    func discard(_ staging: WindowHistoryStaging) {
        pendingStages.removeValue(forKey: staging)
    }

    func stageUndo(token: UndoToken?, for window: WindowIdentity) -> WindowHistoryUndo? {
        let entry: Entry?
        if let token {
            entry = entries.last(where: { $0.token == token && $0.window == window })
        } else {
            entry = latestEntry(for: window)
        }
        guard let entry else { return nil }

        let undo = WindowHistoryUndo(targetFrame: entry.before)
        pendingUndos[undo] = PendingUndo(
            window: window,
            token: entry.token,
            revision: entry.revision
        )
        return undo
    }

    func commit(_ undo: WindowHistoryUndo) {
        guard let pending = pendingUndos.removeValue(forKey: undo),
              entries.contains(where: {
                  $0.token == pending.token
                      && $0.window == pending.window
                      && $0.revision == pending.revision
              }) else {
            return
        }
        entries.removeAll {
            $0.window == pending.window && $0.revision >= pending.revision
        }
    }

    func discard(_ undo: WindowHistoryUndo) {
        pendingUndos.removeValue(forKey: undo)
    }

    func restore(for window: WindowIdentity) -> WindowRestoreAnchor? {
        latestEntry(for: window)?.restoreAnchor
    }

    func prune(keeping windows: Set<WindowIdentity>) {
        entries.removeAll { !windows.contains($0.window) }
        pendingStages = Dictionary(
            uniqueKeysWithValues: pendingStages.filter { _, pending in
                windows.contains(pending.window)
            }
        )
        pendingUndos = Dictionary(
            uniqueKeysWithValues: pendingUndos.filter { _, pending in
                windows.contains(pending.window)
            }
        )
    }

    private func latestEntry(for window: WindowIdentity) -> Entry? {
        entries.last(where: { $0.window == window })
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.size.width > 0
            && frame.size.height > 0
            && frame.maxX.isFinite
            && frame.maxY.isFinite
    }
}
