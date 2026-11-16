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

enum DefaultHotkeyBindings {
    static let initial: [HotkeyBinding] = [
        HotkeyBinding(
            id: UUID(uuidString: "34169CC3-7C78-4A0D-932B-F8CEB5714EA5")!,
            hardwareKeyCode: 123,
            modifiers: [.option, .command],
            actionID: .leftHalf
        ),
        HotkeyBinding(
            id: UUID(uuidString: "908F1B1D-5B80-4E53-BB97-396700FCB397")!,
            hardwareKeyCode: 124,
            modifiers: [.option, .command],
            actionID: .rightHalf
        ),
        HotkeyBinding(
            id: UUID(uuidString: "687DBA69-3508-46C4-929D-38DD74CEBF12")!,
            hardwareKeyCode: 36,
            modifiers: [.option, .command],
            actionID: .maximize
        ),
        HotkeyBinding(
            id: UUID(uuidString: "73880A0D-8E70-4FCA-8567-3BFCB14CD983")!,
            hardwareKeyCode: 45,
            modifiers: [.option, .command],
            actionID: .moveDisplayNext
        ),
    ]
}
