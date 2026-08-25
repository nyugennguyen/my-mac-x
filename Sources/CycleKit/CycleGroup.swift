import Foundation

/// A stable key for one ordered Cycle Group binding.
struct CycleGroupKey: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// An ordered set of Window Actions traversed by repeating one input binding.
struct CycleGroup: Equatable, Sendable {
    let key: CycleGroupKey
    let actions: [ActionID]

    init(key: CycleGroupKey, actions: [ActionID]) throws {
        guard !key.rawValue.isEmpty else {
            throw CycleGroupValidationError.emptyKey
        }
        guard !actions.isEmpty else {
            throw CycleGroupValidationError.emptyActions
        }
        self.key = key
        self.actions = actions
    }
}

enum CycleGroupValidationError: Error, Equatable, Sendable {
    case emptyKey
    case emptyActions
}

/// An opaque proposed transition. Its action may be planned and mutated by the caller, but it
/// advances the Cycle Group only when the caller commits verified success.
struct CycleGroupStaging: Hashable, Sendable {
    let action: ActionID
    private let rawValue: UUID

    init(action: ActionID) {
        self.action = action
        rawValue = UUID()
    }
}

/// Internal Cycle Group Interface owned by the Window Action Engine.
///
/// Callers stage the next action before mutation, commit only after verified read-back, and
/// discard on every failed or cancelled attempt. Reset models an explicit new cycle binding;
/// interruption clears all groups for the captured window.
protocol CycleGroupManaging: Sendable {
    func stageNext(window: WindowIdentity, in group: CycleGroup) async -> CycleGroupStaging
    func commit(_ staging: CycleGroupStaging) async
    func discard(_ staging: CycleGroupStaging) async
    func reset(window: WindowIdentity, group: CycleGroupKey) async
    func interrupt(window: WindowIdentity) async
    func prune(keeping windows: Set<WindowIdentity>) async
}

/// Bounded in-memory Cycle Group state for verified Window Actions.
///
/// This actor retains only opaque window identities and action identifiers. Cursor state is
/// keyed by the exact WindowIdentity and Cycle Group key, making same-application windows and
/// interleaved groups independent.
actor BoundedSessionCycleGroups: CycleGroupManaging {
    private struct CursorKey: Hashable, Sendable {
        let window: WindowIdentity
        let group: CycleGroupKey
    }

    private struct Cursor: Sendable {
        let actions: [ActionID]
        let nextIndex: Int
    }

    private struct PendingTransition: Sendable {
        let key: CursorKey
        let actions: [ActionID]
        let expectedNextIndex: Int
        let expectedRevision: UInt64
        let committedNextIndex: Int
    }

    private let capacity: Int
    private var cursors: [CursorKey: Cursor] = [:]
    private var revisions: [CursorKey: UInt64] = [:]
    private var commitOrder: [CursorKey] = []
    private var pending: [CycleGroupStaging: PendingTransition] = [:]

    init(capacity: Int = 32) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func stageNext(window: WindowIdentity, in group: CycleGroup) -> CycleGroupStaging {
        let key = CursorKey(window: window, group: group.key)
        let cursor = cursors[key]
        let isCurrentDefinition = cursor?.actions == group.actions
        let revision: UInt64

        if cursor != nil, !isCurrentDefinition {
            revision = advanceRevision(for: key)
            cursors[key] = Cursor(actions: group.actions, nextIndex: 0)
            discardPending(for: key)
        } else if !pending.values.contains(where: { $0.key == key }) {
            revision = currentRevision(for: key)
        } else if pending.values.contains(where: { $0.key == key && $0.actions != group.actions }) {
            revision = advanceRevision(for: key)
            discardPending(for: key)
        } else {
            revision = currentRevision(for: key)
        }

        let nextIndex = isCurrentDefinition ? cursor!.nextIndex : 0
        let staging = CycleGroupStaging(action: group.actions[nextIndex])
        pending[staging] = PendingTransition(
            key: key,
            actions: group.actions,
            expectedNextIndex: nextIndex,
            expectedRevision: revision,
            committedNextIndex: (nextIndex + 1) % group.actions.count
        )
        return staging
    }

    func commit(_ staging: CycleGroupStaging) {
        guard let transition = pending.removeValue(forKey: staging) else { return }
        guard currentRevision(for: transition.key) == transition.expectedRevision else { return }
        let current = cursors[transition.key]
        let currentDefinitionMatches = current?.actions == transition.actions
        let currentNextIndex = currentDefinitionMatches ? current!.nextIndex : 0
        guard (current == nil || currentDefinitionMatches),
              currentNextIndex == transition.expectedNextIndex
        else { return }

        _ = advanceRevision(for: transition.key)
        cursors[transition.key] = Cursor(
            actions: transition.actions,
            nextIndex: transition.committedNextIndex
        )
        touch(transition.key)
        evictExcessCursors()
    }

    func discard(_ staging: CycleGroupStaging) {
        pending.removeValue(forKey: staging)
    }

    func reset(window: WindowIdentity, group: CycleGroupKey) {
        let key = CursorKey(window: window, group: group)
        _ = advanceRevision(for: key)
        cursors.removeValue(forKey: key)
        commitOrder.removeAll { $0 == key }
        discardPending(for: key)
    }

    func interrupt(window: WindowIdentity) {
        let affected = Set(cursors.keys.filter { $0.window == window })
            .union(pending.values.filter { $0.key.window == window }.map(\.key))
            .union(revisions.keys.filter { $0.window == window })
        for key in affected {
            _ = advanceRevision(for: key)
        }
        cursors = cursors.filter { $0.key.window != window }
        commitOrder.removeAll { $0.window == window }
        pending = pending.filter { _, transition in transition.key.window != window }
    }

    func prune(keeping windows: Set<WindowIdentity>) {
        let staleKeys = Set(cursors.keys.filter { !windows.contains($0.window) })
            .union(pending.values.filter { !windows.contains($0.key.window) }.map(\.key))
            .union(revisions.keys.filter { !windows.contains($0.window) })
        for key in staleKeys {
            _ = advanceRevision(for: key)
        }
        cursors = cursors.filter { windows.contains($0.key.window) }
        commitOrder.removeAll { !windows.contains($0.window) }
        pending = pending.filter { _, transition in windows.contains(transition.key.window) }
        revisions = revisions.filter { windows.contains($0.key.window) }
    }

    private func touch(_ key: CursorKey) {
        commitOrder.removeAll { $0 == key }
        commitOrder.append(key)
    }

    private func evictExcessCursors() {
        while cursors.count > capacity, let evicted = commitOrder.first {
            commitOrder.removeFirst()
            _ = advanceRevision(for: evicted)
            cursors.removeValue(forKey: evicted)
            discardPending(for: evicted)
            revisions.removeValue(forKey: evicted)
        }
    }

    private func currentRevision(for key: CursorKey) -> UInt64 {
        revisions[key, default: 0]
    }

    private func advanceRevision(for key: CursorKey) -> UInt64 {
        let current = currentRevision(for: key)
        precondition(current < .max, "Cycle Group revision exhausted")
        let next = current + 1
        revisions[key] = next
        return next
    }

    private func discardPending(for key: CursorKey) {
        pending = pending.filter { _, transition in transition.key != key }
    }
}
