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
@testable import MyMacX

@MainActor
final class InMemoryHotkeyRecorderInputAdapter: HotkeyRecorderInputMonitoring {
    private var sessionID: UUID?
    private var handler: (@Sendable (HotkeyRecorderInputEvent) -> Void)?

    func startCapturing(
        sessionID: UUID,
        handler: @escaping @Sendable (HotkeyRecorderInputEvent) -> Void
    ) {
        self.sessionID = sessionID
        self.handler = handler
    }

    func stopCapturing(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.sessionID = nil
        handler = nil
    }

    func send(_ event: HotkeyRecorderInputEvent) {
        handler?(event)
    }
}
