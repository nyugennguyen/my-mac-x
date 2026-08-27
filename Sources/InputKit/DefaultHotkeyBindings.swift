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
