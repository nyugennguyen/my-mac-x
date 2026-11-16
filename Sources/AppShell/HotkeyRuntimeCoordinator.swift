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
