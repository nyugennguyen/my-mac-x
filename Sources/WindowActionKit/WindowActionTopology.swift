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

struct WindowActionTopologySnapshot: Equatable, Sendable {
    let generation: DisplayTopologyGeneration
    let topology: DisplayTopologySnapshot
}

enum WindowActionTopologyResult: Equatable, Sendable {
    case available(WindowActionTopologySnapshot)
    case unavailable
}

protocol WindowActionTopologyProviding: Sendable {
    func captureTopology() async -> WindowActionTopologyResult
}

/// Long-lived Adapter over ScreenKit's in-session topology observation scope.
actor ObservedWindowActionTopologyAdapter: WindowActionTopologyProviding {
    private let observer: any DisplayTopologyObserving
    private var latest: DisplayTopologyState?
    private var startupWaiters: [CheckedContinuation<Void, Never>] = []
    private var observationTask: Task<Void, Never>?

    init(observer: any DisplayTopologyObserving) {
        self.observer = observer
    }

    func captureTopology() async -> WindowActionTopologyResult {
        startIfNeeded()
        if latest == nil {
            await withCheckedContinuation { startupWaiters.append($0) }
        }

        guard case let .available(versioned) = latest else {
            return .unavailable
        }
        return .available(WindowActionTopologySnapshot(
            generation: versioned.generation,
            topology: versioned.topology
        ))
    }

    private func startIfNeeded() {
        guard observationTask == nil else { return }
        let observer = observer
        observationTask = Task { [weak self] in
            let updates = await observer.updates()
            for await state in updates {
                guard let self else { return }
                await self.accept(state)
            }
        }
    }

    private func accept(_ state: DisplayTopologyState) {
        latest = state
        let waiters = startupWaiters
        startupWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
