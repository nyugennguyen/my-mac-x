import Foundation
@testable import MyMacX

actor InMemoryGlobalHotkeySystem: GlobalHotkeySystem {
    private var bindings: [UUID: HotkeyBinding] = [:]
    private var onInvocation: (@Sendable (HotkeyInvocation) -> Void)?
    private var lifecycleHandler: (@Sendable (GlobalHotkeyLifecycleEvent) async -> Void)?
    private var nextFailure: HotkeyRegistrationFailure?
    private(set) var registrationPassCount = 0
    private(set) var lifecycleObservationCount = 0

    var activeBindingIDs: [UUID] {
        bindings.keys.sorted { $0.uuidString < $1.uuidString }
    }

    func observeLifecycle(
        _ handler: @escaping @Sendable (GlobalHotkeyLifecycleEvent) async -> Void
    ) {
        lifecycleObservationCount += 1
        lifecycleHandler = handler
    }

    func reconcile(
        _ bindings: [HotkeyBinding],
        onInvocation: @escaping @Sendable (HotkeyInvocation) -> Void
    ) -> HotkeySystemReconciliation {
        registrationPassCount += 1
        if let nextFailure {
            self.nextFailure = nil
            return .degraded(
                activeBindingIDs: activeBindingIDs,
                failures: [nextFailure]
            )
        }
        self.bindings = Dictionary(uniqueKeysWithValues: bindings.map { ($0.id, $0) })
        self.onInvocation = onInvocation
        return .active(bindingIDs: bindings.map(\.id))
    }

    func failNextReconciliation(with failure: HotkeyRegistrationFailure) {
        nextFailure = failure
    }

    func simulateSleep() async {
        await lifecycleHandler?(.willSleep)
    }

    func simulateWake() async {
        await lifecycleHandler?(.didWake)
    }

    func invoke(bindingID: UUID) {
        guard let binding = bindings[bindingID] else { return }
        onInvocation?(
            HotkeyInvocation(bindingID: binding.id, actionID: binding.actionID)
        )
    }
}
