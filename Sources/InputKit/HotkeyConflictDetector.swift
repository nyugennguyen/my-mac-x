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

struct HotkeyValidationRequest: Equatable, Sendable {
    let editedBindingID: UUID?
    let actionID: ActionID
    let candidate: HotkeyChord
    let existingBindings: [HotkeyBinding]
}

protocol HotkeyConflictValidating: Sendable {
    func validate(_ request: HotkeyValidationRequest) -> HotkeyValidationResult
}

enum HotkeyValidationResult: Equatable, Sendable {
    case valid
    case invalid(InvalidHotkeyReason)
    case reserved(ReservedHotkeyConflict)
    case duplicate(DuplicateHotkeyConflict)
}

enum InvalidHotkeyReason: Equatable, Sendable {
    case requiresModifier
    case unsupportedModifierBits(rawValue: UInt32)
    case modifierOnlyPrimaryKey
    case unsupportedHardwareKeyCode(UInt16)
}

struct DuplicateHotkeyConflict: Equatable, Sendable {
    let conflicts: [ConflictingHotkeyBinding]
}

struct ConflictingHotkeyBinding: Equatable, Sendable {
    let bindingID: UUID
    let actionID: ActionID
}

struct ReservedHotkeyConflict: Equatable, Sendable {
    let reservationID: ReservedHotkeyID
    let replacementAllowed: Bool
}

struct ReservedHotkeyID: RawRepresentable, Equatable, Hashable, Sendable {
    let rawValue: String
}

private enum V1HotkeyValidationPolicy {
    static let bindableHardwareKeyCodes: ClosedRange<UInt16> = 0...126
    static let modifierOnlyHardwareKeyCodes: ClosedRange<UInt16> = 54...63
    static let reservedCatalog: [HotkeyChord: ReservedHotkeyID] = [
        HotkeyChord(
            hardwareKeyCode: 49,
            modifiers: [.command]
        ): ReservedHotkeyID(rawValue: "system.spotlight"),
        HotkeyChord(
            hardwareKeyCode: 48,
            modifiers: [.command]
        ): ReservedHotkeyID(rawValue: "system.app-switcher"),
        HotkeyChord(
            hardwareKeyCode: 53,
            modifiers: [.command, .option]
        ): ReservedHotkeyID(rawValue: "system.force-quit"),
        HotkeyChord(
            hardwareKeyCode: 20,
            modifiers: [.command, .shift]
        ): ReservedHotkeyID(rawValue: "system.screenshot-full"),
        HotkeyChord(
            hardwareKeyCode: 21,
            modifiers: [.command, .shift]
        ): ReservedHotkeyID(rawValue: "system.screenshot-selection"),
        HotkeyChord(
            hardwareKeyCode: 23,
            modifiers: [.command, .shift]
        ): ReservedHotkeyID(rawValue: "system.screenshot-options"),
    ]
}

struct HotkeyConflictDetector: HotkeyConflictValidating {
    private static let supportedModifierMask =
        HotkeyModifiers.command.rawValue
        | HotkeyModifiers.option.rawValue
        | HotkeyModifiers.control.rawValue
        | HotkeyModifiers.shift.rawValue

    func validate(_ request: HotkeyValidationRequest) -> HotkeyValidationResult {
        let unsupportedModifierBits =
            request.candidate.modifiers.rawValue & ~Self.supportedModifierMask
        guard unsupportedModifierBits == 0 else {
            return .invalid(
                .unsupportedModifierBits(rawValue: unsupportedModifierBits)
            )
        }

        guard request.candidate.modifiers.rawValue != 0 else {
            return .invalid(.requiresModifier)
        }
        guard !V1HotkeyValidationPolicy.modifierOnlyHardwareKeyCodes.contains(
            request.candidate.hardwareKeyCode
        ) else {
            return .invalid(.modifierOnlyPrimaryKey)
        }
        guard V1HotkeyValidationPolicy.bindableHardwareKeyCodes.contains(
            request.candidate.hardwareKeyCode
        ) else {
            return .invalid(
                .unsupportedHardwareKeyCode(request.candidate.hardwareKeyCode)
            )
        }
        if let reservationID = V1HotkeyValidationPolicy.reservedCatalog[
            request.candidate
        ] {
            return .reserved(
                ReservedHotkeyConflict(
                    reservationID: reservationID,
                    replacementAllowed: false
                )
            )
        }

        let conflicts = request.existingBindings
            .filter {
                $0.id != request.editedBindingID && $0.chord == request.candidate
            }
            .map {
                ConflictingHotkeyBinding(
                    bindingID: $0.id,
                    actionID: $0.actionID
                )
            }
            .sorted { $0.bindingID.uuidString < $1.bindingID.uuidString }

        guard conflicts.isEmpty else {
            return .duplicate(DuplicateHotkeyConflict(conflicts: conflicts))
        }
        return .valid
    }
}
