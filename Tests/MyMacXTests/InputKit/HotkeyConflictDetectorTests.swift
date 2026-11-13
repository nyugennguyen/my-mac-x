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

import XCTest
@testable import MyMacX

final class HotkeyConflictDetectorTests: XCTestCase {
    func testV1BindableRangeBoundariesAreValid() {
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        for hardwareKeyCode: UInt16 in [0, 126] {
            let result = validator.validate(
                request(
                    candidate: HotkeyChord(
                        hardwareKeyCode: hardwareKeyCode,
                        modifiers: [.command]
                    )
                )
            )

            XCTAssertEqual(result, .valid)
        }
    }

    func testCandidateMatchingAnotherBindingReturnsTypedDuplicate() {
        let conflictingBinding = HotkeyBinding(
            id: UUID(uuidString: "2DB210DE-5A76-43DC-986C-F2972E135C09")!,
            hardwareKeyCode: 0x7B,
            modifiers: [.command, .option],
            actionID: .leftHalf
        )
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            HotkeyValidationRequest(
                editedBindingID: nil,
                actionID: .rightHalf,
                candidate: HotkeyChord(
                    hardwareKeyCode: 0x7B,
                    modifiers: [.command, .option]
                ),
                existingBindings: [conflictingBinding]
            )
        )

        XCTAssertEqual(
            result,
            .duplicate(
                DuplicateHotkeyConflict(
                    conflicts: [
                        ConflictingHotkeyBinding(
                            bindingID: conflictingBinding.id,
                            actionID: .leftHalf
                        ),
                    ]
                )
            )
        )
    }

    func testDuplicateAppliesWhenBindingsTargetSameAction() {
        let existingBinding = HotkeyBinding(
            id: UUID(uuidString: "E28ED215-4345-46A5-B971-0DB2F4494045")!,
            hardwareKeyCode: 124,
            modifiers: [.control],
            actionID: .rightHalf
        )
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            request(
                candidate: existingBinding.chord,
                existingBindings: [existingBinding]
            )
        )

        XCTAssertEqual(
            result,
            .duplicate(
                DuplicateHotkeyConflict(
                    conflicts: [
                        ConflictingHotkeyBinding(
                            bindingID: existingBinding.id,
                            actionID: .rightHalf
                        ),
                    ]
                )
            )
        )
    }

    func testEditingBindingWithUnchangedChordDoesNotConflictWithItself() {
        let editedBinding = HotkeyBinding(
            id: UUID(uuidString: "B10BFE71-E723-4D10-AF54-38AFD568E773")!,
            hardwareKeyCode: 0x7C,
            modifiers: [.control, .option],
            actionID: .maximize
        )
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            HotkeyValidationRequest(
                editedBindingID: editedBinding.id,
                actionID: .maximize,
                candidate: editedBinding.chord,
                existingBindings: [editedBinding]
            )
        )

        XCTAssertEqual(result, .valid)
    }

    func testCandidateWithoutModifierIsInvalid() {
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            request(candidate: HotkeyChord(hardwareKeyCode: 0x00, modifiers: []))
        )

        XCTAssertEqual(result, .invalid(.requiresModifier))
    }

    func testCandidateWithUnsupportedModifierBitsIsInvalid() {
        let unsupportedBit: UInt32 = 1 << 8
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            request(
                candidate: HotkeyChord(
                    hardwareKeyCode: 0x00,
                    modifiers: HotkeyModifiers(
                        rawValue: HotkeyModifiers.command.rawValue | unsupportedBit
                    )
                )
            )
        )

        XCTAssertEqual(
            result,
            .invalid(.unsupportedModifierBits(rawValue: unsupportedBit))
        )
    }

    func testModifierOnlyPrimaryKeyRangeBoundariesAreInvalid() {
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        for hardwareKeyCode: UInt16 in [54, 63] {
            let result = validator.validate(
                request(
                    candidate: HotkeyChord(
                        hardwareKeyCode: hardwareKeyCode,
                        modifiers: [.command]
                    )
                )
            )

            XCTAssertEqual(result, .invalid(.modifierOnlyPrimaryKey))
        }
    }

    func testHardwareKeyCodeOutsideV1BindableSetIsInvalid() {
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            request(
                candidate: HotkeyChord(
                    hardwareKeyCode: 127,
                    modifiers: [.option]
                )
            )
        )

        XCTAssertEqual(result, .invalid(.unsupportedHardwareKeyCode(127)))
    }

    func testV1ReservedCatalogReturnsStableTypedConflicts() {
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()
        let reservedCases: [(HotkeyChord, String)] = [
            (
                HotkeyChord(hardwareKeyCode: 49, modifiers: [.command]),
                "system.spotlight"
            ),
            (
                HotkeyChord(hardwareKeyCode: 48, modifiers: [.command]),
                "system.app-switcher"
            ),
            (
                HotkeyChord(
                    hardwareKeyCode: 53,
                    modifiers: [.command, .option]
                ),
                "system.force-quit"
            ),
            (
                HotkeyChord(
                    hardwareKeyCode: 20,
                    modifiers: [.command, .shift]
                ),
                "system.screenshot-full"
            ),
            (
                HotkeyChord(
                    hardwareKeyCode: 21,
                    modifiers: [.command, .shift]
                ),
                "system.screenshot-selection"
            ),
            (
                HotkeyChord(
                    hardwareKeyCode: 23,
                    modifiers: [.command, .shift]
                ),
                "system.screenshot-options"
            ),
        ]

        for (chord, reservationID) in reservedCases {
            XCTAssertEqual(
                validator.validate(request(candidate: chord)),
                .reserved(
                    ReservedHotkeyConflict(
                        reservationID: ReservedHotkeyID(rawValue: reservationID),
                        replacementAllowed: false
                    )
                )
            )
        }
    }

    func testAppCommandCollisionsAreNotInProtectedGlobalCatalog() {
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        for hardwareKeyCode: UInt16 in [12, 13, 4, 46] {
            let result = validator.validate(
                request(
                    candidate: HotkeyChord(
                        hardwareKeyCode: hardwareKeyCode,
                        modifiers: [.command]
                    )
                )
            )

            XCTAssertEqual(result, .valid)
        }
    }

    func testReservedCandidateTakesPrecedenceOverDamagedDuplicateSnapshot() {
        let candidate = HotkeyChord(
            hardwareKeyCode: 49,
            modifiers: [.command]
        )
        let damagedBinding = HotkeyBinding(
            id: UUID(uuidString: "D67E65C0-E32A-4966-97A8-66D653F49B95")!,
            hardwareKeyCode: candidate.hardwareKeyCode,
            modifiers: candidate.modifiers,
            actionID: .leftHalf
        )
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            request(
                candidate: candidate,
                existingBindings: [damagedBinding]
            )
        )

        XCTAssertEqual(
            result,
            .reserved(
                ReservedHotkeyConflict(
                    reservationID: ReservedHotkeyID(
                        rawValue: "system.spotlight"
                    ),
                    replacementAllowed: false
                )
            )
        )
    }

    func testMultipleDuplicateBindingsAreReturnedInStableUUIDOrder() {
        let candidate = HotkeyChord(
            hardwareKeyCode: 124,
            modifiers: [.command, .option]
        )
        let laterBinding = HotkeyBinding(
            id: UUID(uuidString: "F6274E6C-1538-4628-A290-B82BA02E82F1")!,
            hardwareKeyCode: candidate.hardwareKeyCode,
            modifiers: candidate.modifiers,
            actionID: .maximize
        )
        let earlierBinding = HotkeyBinding(
            id: UUID(uuidString: "0119512B-3A9C-424B-9C93-7E8477922F74")!,
            hardwareKeyCode: candidate.hardwareKeyCode,
            modifiers: candidate.modifiers,
            actionID: .leftHalf
        )
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            request(
                candidate: candidate,
                existingBindings: [laterBinding, earlierBinding]
            )
        )

        XCTAssertEqual(
            result,
            .duplicate(
                DuplicateHotkeyConflict(
                    conflicts: [
                        ConflictingHotkeyBinding(
                            bindingID: earlierBinding.id,
                            actionID: earlierBinding.actionID
                        ),
                        ConflictingHotkeyBinding(
                            bindingID: laterBinding.id,
                            actionID: laterBinding.actionID
                        ),
                    ]
                )
            )
        )
    }

    func testInvalidCandidateTakesPrecedenceOverDuplicateSnapshot() {
        let candidate = HotkeyChord(hardwareKeyCode: 0x00, modifiers: [])
        let damagedBinding = HotkeyBinding(
            id: UUID(uuidString: "B6E10DFA-3025-40AF-B99C-95F573BD4BBE")!,
            hardwareKeyCode: candidate.hardwareKeyCode,
            modifiers: candidate.modifiers,
            actionID: .leftHalf
        )
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let result = validator.validate(
            request(
                candidate: candidate,
                existingBindings: [damagedBinding]
            )
        )

        XCTAssertEqual(result, .invalid(.requiresModifier))
    }

    func testChordEqualityUsesHardwareCodeAndNormalizedModifiers() {
        let existingBinding = HotkeyBinding(
            id: UUID(uuidString: "8698C1B9-AE92-410C-A5C5-937B53BCFE65")!,
            hardwareKeyCode: 123,
            modifiers: [.command],
            actionID: .leftHalf
        )
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let differentHardwareCode = validator.validate(
            request(
                candidate: HotkeyChord(
                    hardwareKeyCode: 124,
                    modifiers: [.command]
                ),
                existingBindings: [existingBinding]
            )
        )
        let differentModifiers = validator.validate(
            request(
                candidate: HotkeyChord(
                    hardwareKeyCode: 123,
                    modifiers: [.option]
                ),
                existingBindings: [existingBinding]
            )
        )

        XCTAssertEqual(differentHardwareCode, .valid)
        XCTAssertEqual(differentModifiers, .valid)
    }

    func testValidationIsDeterministicAndDoesNotMutateRequest() {
        let existingBinding = HotkeyBinding(
            id: UUID(uuidString: "3F369D22-0D96-470B-A880-7A9593800D29")!,
            hardwareKeyCode: 124,
            modifiers: [.control, .option],
            actionID: .leftHalf
        )
        let originalRequest = request(
            candidate: existingBinding.chord,
            existingBindings: [existingBinding]
        )
        let knownRequest = originalRequest
        let validator: any HotkeyConflictValidating = HotkeyConflictDetector()

        let firstResult = validator.validate(originalRequest)
        let secondResult = validator.validate(originalRequest)

        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(originalRequest, knownRequest)
    }

    private func request(
        candidate: HotkeyChord,
        editedBindingID: UUID? = nil,
        existingBindings: [HotkeyBinding] = []
    ) -> HotkeyValidationRequest {
        HotkeyValidationRequest(
            editedBindingID: editedBindingID,
            actionID: .rightHalf,
            candidate: candidate,
            existingBindings: existingBindings
        )
    }
}
