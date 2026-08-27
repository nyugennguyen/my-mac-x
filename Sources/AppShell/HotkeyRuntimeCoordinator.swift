import Foundation

@MainActor
final class HotkeyRuntimeCoordinator {
    private let manager: any GlobalHotkeyManaging
    private let bindingUpdater: any HotkeyRuntimeBindingUpdating
    private let dispatcher: HotkeyActionDispatcher
    private var eventTask: Task<Void, Never>?

    init(
        manager: any GlobalHotkeyManaging,
        bindingUpdater: any HotkeyRuntimeBindingUpdating,
        dispatcher: HotkeyActionDispatcher
    ) {
        self.manager = manager
        self.bindingUpdater = bindingUpdater
        self.dispatcher = dispatcher
    }

    func start() {
        guard eventTask == nil else { return }

        eventTask = Task { [manager, bindingUpdater, dispatcher] in
            let events = await manager.events
            _ = await bindingUpdater.start()
            for await invocation in events {
                guard !Task.isCancelled else { return }
                _ = await dispatcher.dispatch(invocation)
            }
        }
    }

    deinit {
        eventTask?.cancel()
    }
}
