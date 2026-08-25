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
