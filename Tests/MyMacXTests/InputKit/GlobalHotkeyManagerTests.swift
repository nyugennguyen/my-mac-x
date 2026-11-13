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

final class GlobalHotkeyManagerTests: XCTestCase {
    func testReconcileRegistersDesiredBindingAndPublishesItsInvocation() async throws {
        let system = InMemoryGlobalHotkeySystem()
        let manager: any GlobalHotkeyManaging = GlobalHotkeyManager(system: system)
        let binding = HotkeyBinding(
            id: UUID(uuidString: "8E57E1C7-2EF0-49C7-AB86-C2E7F84569C8")!,
            hardwareKeyCode: 0x00,
            modifiers: [.command, .option],
            actionID: .leftHalf
        )

        let snapshot = await manager.reconcile([binding])
        let events = await manager.events
        let invocation = try await withThrowingTaskGroup(of: HotkeyInvocation.self) { group in
            group.addTask {
                for await event in events {
                    return event
                }
                throw HotkeyTestFailure.streamFinished
            }
            group.addTask {
                try await Task.sleep(for: .seconds(1))
                throw HotkeyTestFailure.timedOut
            }

            await system.invoke(bindingID: binding.id)
            let value = try await group.next()!
            group.cancelAll()
            return value
        }

        XCTAssertEqual(snapshot, .active(bindingIDs: [binding.id]))
        XCTAssertEqual(invocation, HotkeyInvocation(bindingID: binding.id, actionID: .leftHalf))
    }

    func testReconcilingUnchangedSnapshotDoesNotRegisterAgain() async {
        let system = InMemoryGlobalHotkeySystem()
        let manager: any GlobalHotkeyManaging = GlobalHotkeyManager(system: system)
        let binding = HotkeyBinding(
            id: UUID(uuidString: "EB49B6EA-4DAB-4224-A226-281336E2EF8A")!,
            hardwareKeyCode: 0x02,
            modifiers: [.control, .option],
            actionID: .rightHalf
        )

        _ = await manager.reconcile([binding])
        _ = await manager.reconcile([binding])

        let registrationPassCount = await system.registrationPassCount
        XCTAssertEqual(registrationPassCount, 1)
    }

    func testFailedReplacementPreservesLastValidBindingsAndReportsDegradation() async {
        let system = InMemoryGlobalHotkeySystem()
        let manager: any GlobalHotkeyManaging = GlobalHotkeyManager(system: system)
        let original = HotkeyBinding(
            id: UUID(uuidString: "36FD6D46-34C9-42E2-9FC4-8B46A64CB10F")!,
            hardwareKeyCode: 0x00,
            modifiers: [.command, .option],
            actionID: .leftHalf
        )
        let replacement = HotkeyBinding(
            id: UUID(uuidString: "5320FD42-0C5C-4868-9727-B26AF2010F9E")!,
            hardwareKeyCode: 0x02,
            modifiers: [.command, .option],
            actionID: .rightHalf
        )

        _ = await manager.reconcile([original])
        await system.failNextReconciliation(
            with: .chordUnavailable(bindingID: replacement.id)
        )

        let snapshot = await manager.reconcile([replacement])
        let activeBindingIDs = await system.activeBindingIDs

        XCTAssertEqual(
            snapshot,
            .degraded(
                activeBindingIDs: [original.id],
                failures: [.chordUnavailable(bindingID: replacement.id)]
            )
        )
        XCTAssertEqual(activeBindingIDs, [original.id])
    }

    func testReconcilingPriorSnapshotAfterFailedReplacementReturnsActive() async {
        let system = InMemoryGlobalHotkeySystem()
        let manager: any GlobalHotkeyManaging = GlobalHotkeyManager(system: system)
        let original = HotkeyBinding(
            id: UUID(uuidString: "4C7484D5-CE33-4E77-8718-356700866269")!,
            hardwareKeyCode: 0x00,
            modifiers: [.command, .option],
            actionID: .leftHalf
        )
        let replacement = HotkeyBinding(
            id: UUID(uuidString: "8C98DC64-C338-46BC-93F6-A370311C259E")!,
            hardwareKeyCode: 0x02,
            modifiers: [.command, .option],
            actionID: .rightHalf
        )

        _ = await manager.reconcile([original])
        await system.failNextReconciliation(
            with: .chordUnavailable(bindingID: replacement.id)
        )
        _ = await manager.reconcile([replacement])

        let snapshot = await manager.reconcile([original])
        let registrationPassCount = await system.registrationPassCount

        XCTAssertEqual(snapshot, .active(bindingIDs: [original.id]))
        XCTAssertEqual(registrationPassCount, 2)
    }

    func testReplacingBindingMakesOldChordIneffective() async throws {
        let system = InMemoryGlobalHotkeySystem()
        let manager: any GlobalHotkeyManaging = GlobalHotkeyManager(system: system)
        let original = HotkeyBinding(
            id: UUID(uuidString: "D6C840A0-F10A-4F65-A6FB-6F1FEC78BAA7")!,
            hardwareKeyCode: 0x00,
            modifiers: [.command, .option],
            actionID: .leftHalf
        )
        let replacement = HotkeyBinding(
            id: UUID(uuidString: "300170EC-CC02-4446-A4E6-5BF4DF18C291")!,
            hardwareKeyCode: 0x02,
            modifiers: [.command, .option],
            actionID: .rightHalf
        )

        _ = await manager.reconcile([original])
        let snapshot = await manager.reconcile([replacement])
        let events = await manager.events

        await system.invoke(bindingID: original.id)
        await system.invoke(bindingID: replacement.id)
        let invocation = try await firstEvent(from: events)

        XCTAssertEqual(snapshot, .active(bindingIDs: [replacement.id]))
        XCTAssertEqual(
            invocation,
            HotkeyInvocation(bindingID: replacement.id, actionID: .rightHalf)
        )
    }

    func testEmptyReconciliationReleasesEveryBinding() async throws {
        let system = InMemoryGlobalHotkeySystem()
        let manager: any GlobalHotkeyManaging = GlobalHotkeyManager(system: system)
        let binding = HotkeyBinding(
            id: UUID(uuidString: "472C2202-27C2-4739-B971-8901257F4D9E")!,
            hardwareKeyCode: 0x01,
            modifiers: [.command, .shift],
            actionID: .maximize
        )

        _ = await manager.reconcile([binding])
        let snapshot = await manager.reconcile([])
        let events = await manager.events

        await system.invoke(bindingID: binding.id)
        let invocation = await firstEvent(from: events, within: .milliseconds(50))

        XCTAssertEqual(snapshot, .active(bindingIDs: []))
        XCTAssertNil(invocation)
    }

    func testSleepWakeRestoresOneRegistrationAndRepeatedWakeIsANoOp() async {
        let system = InMemoryGlobalHotkeySystem()
        let manager: any GlobalHotkeyManaging = GlobalHotkeyManager(system: system)
        let binding = HotkeyBinding(
            id: UUID(uuidString: "0F4AA3A0-A12E-4E18-A21D-B7FEF1C6F4F5")!,
            hardwareKeyCode: 0x0D,
            modifiers: [.control, .option],
            actionID: .topHalf
        )

        _ = await manager.reconcile([binding])
        _ = await manager.reconcile([binding])
        await system.simulateSleep()
        await system.simulateWake()
        await system.simulateWake()

        let activeBindingIDs = await system.activeBindingIDs
        let registrationPassCount = await system.registrationPassCount
        let lifecycleObservationCount = await system.lifecycleObservationCount
        XCTAssertEqual(activeBindingIDs, [binding.id])
        XCTAssertEqual(registrationPassCount, 3)
        XCTAssertEqual(lifecycleObservationCount, 1)
    }
}

private enum HotkeyTestFailure: Error {
    case streamFinished
    case timedOut
}

private func firstEvent(
    from events: AsyncStream<HotkeyInvocation>
) async throws -> HotkeyInvocation {
    try await withThrowingTaskGroup(of: HotkeyInvocation.self) { group in
        group.addTask {
            for await event in events {
                return event
            }
            throw HotkeyTestFailure.streamFinished
        }
        group.addTask {
            try await Task.sleep(for: .seconds(1))
            throw HotkeyTestFailure.timedOut
        }

        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}

private func firstEvent(
    from events: AsyncStream<HotkeyInvocation>,
    within duration: Duration
) async -> HotkeyInvocation? {
    await withTaskGroup(of: HotkeyInvocation?.self) { group in
        group.addTask {
            for await event in events {
                return event
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: duration)
            return nil
        }

        let value = await group.next()!
        group.cancelAll()
        return value
    }
}
