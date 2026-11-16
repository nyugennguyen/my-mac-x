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

import CoreGraphics
import SwiftUI
import XCTest
@testable import MyMacX

@MainActor
final class ZoneMapPickerTests: XCTestCase {

    // MARK: - Picker ViewModel State & Selection Transitions

    func testViewModelInitialState() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        // Default selection is .top
        XCTAssertEqual(vm.selectedZone, .top)
        XCTAssertNil(vm.hoveredZone)
        XCTAssertTrue(vm.isAllDefault)
        XCTAssertTrue(vm.isZoneDefault(.top))
        XCTAssertTrue(vm.isZoneEnabled(.top))
        XCTAssertEqual(vm.partitionCount(for: .top), 1)
        XCTAssertEqual(vm.actions(for: .top), [.maximize])
    }

    func testZoneSelectionAndHoverTransitions() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        vm.select(zone: .left)
        XCTAssertEqual(vm.selectedZone, .left)

        vm.hover(zone: .right)
        XCTAssertEqual(vm.hoveredZone, .right)

        vm.hover(zone: nil)
        XCTAssertNil(vm.hoveredZone)
    }

    func testPerZoneToggleEnabledTransitions() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        XCTAssertTrue(vm.isZoneEnabled(.top))

        vm.setZoneEnabled(false, for: .top)
        XCTAssertFalse(vm.isZoneEnabled(.top))
        XCTAssertFalse(store.isEnabled(.top))

        vm.toggleZoneEnabled(for: .top)
        XCTAssertTrue(vm.isZoneEnabled(.top))
        XCTAssertTrue(store.isEnabled(.top))
    }

    // MARK: - Partition Editing (1..4 Areas)

    func testPartitionCountTransitionsOnStraightEdge() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        // Initial top is 1 part: maximize
        XCTAssertEqual(vm.partitionCount(for: .top), 1)

        // Set 2 partitions -> leftHalf, rightHalf
        vm.setPartitionCount(2, for: .top)
        XCTAssertEqual(vm.partitionCount(for: .top), 2)
        XCTAssertEqual(vm.actions(for: .top), [.leftHalf, .rightHalf])

        // Set 3 partitions -> leftThird, centerThird, rightThird
        vm.setPartitionCount(3, for: .top)
        XCTAssertEqual(vm.partitionCount(for: .top), 3)
        XCTAssertEqual(vm.actions(for: .top), [
            .leftThird,
            ActionID(rawValue: "window.center-third"),
            ActionID(rawValue: "window.right-third")
        ])

        // Set 4 partitions -> 4 quarter columns
        vm.setPartitionCount(4, for: .top)
        XCTAssertEqual(vm.partitionCount(for: .top), 4)
        XCTAssertEqual(vm.actions(for: .top).count, 4)

        // Clamped at 4
        vm.setPartitionCount(5, for: .top)
        XCTAssertEqual(vm.partitionCount(for: .top), 4)

        // Clamped at 1
        vm.setPartitionCount(0, for: .top)
        XCTAssertEqual(vm.partitionCount(for: .top), 1)
    }

    func testCornerPartitionCountIsStrictlyOne() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        XCTAssertEqual(vm.partitionCount(for: .topLeft), 1)
        vm.setPartitionCount(3, for: .topLeft)
        // Corners remain 1
        XCTAssertEqual(vm.partitionCount(for: .topLeft), 1)
        XCTAssertEqual(vm.actions(for: .topLeft), [.topLeftQuarter])
    }

    func testSetActionForSubPartition() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        vm.setPartitionCount(2, for: .top)
        // Top currently has [.leftHalf, .rightHalf]
        // Change part 1 to .leftTwoThirds
        vm.setAction(.leftTwoThirds, for: .top, at: 1)
        XCTAssertEqual(vm.actions(for: .top), [.leftHalf, .leftTwoThirds])

        // Corner action change
        vm.setAction(.topRightQuarter, for: .topLeft, at: 0)
        XCTAssertEqual(vm.actions(for: .topLeft), [.topRightQuarter])
    }

    // MARK: - Per-Zone Reset and Reset-All

    func testPerZoneReset() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        vm.setPartitionCount(2, for: .top)
        vm.setZoneEnabled(false, for: .top)
        XCTAssertFalse(vm.isZoneDefault(.top))

        vm.resetZone(.top)
        XCTAssertTrue(vm.isZoneDefault(.top))
        XCTAssertTrue(vm.isZoneEnabled(.top))
        XCTAssertEqual(vm.actions(for: .top), [.maximize])
    }

    func testResetAllZonesToDefaults() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        vm.setPartitionCount(3, for: .top)
        vm.setZoneEnabled(false, for: .left)
        vm.setAction(.bottomHalf, for: .bottom, at: 0)
        XCTAssertFalse(vm.isAllDefault)

        vm.resetAllZones()
        XCTAssertTrue(vm.isAllDefault)
        XCTAssertTrue(vm.isZoneDefault(.top))
        XCTAssertTrue(vm.isZoneDefault(.left))
        XCTAssertTrue(vm.isZoneDefault(.bottom))
    }

    // MARK: - Normalized Glyph Regions

    func testGlyphRegionsForActions() {
        let store = EdgeSnapZoneConfigurationStore()
        let vm = ZoneMapPickerViewModel(store: store)

        // Default top: maximize -> 1 full rect
        let maxRegions = vm.glyphRegions(for: .top)
        XCTAssertEqual(maxRegions, [CGRect(x: 0, y: 0, width: 1, height: 1)])

        // Split top into 2 parts: 2 columns
        vm.setPartitionCount(2, for: .top)
        let twoCols = vm.glyphRegions(for: .top)
        XCTAssertEqual(twoCols.count, 2)
        XCTAssertEqual(twoCols[0], CGRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(twoCols[1], CGRect(x: 0.5, y: 0, width: 0.5, height: 1))

        // Split left into 2 parts: 2 rows (top row, bottom row)
        vm.setPartitionCount(2, for: .left)
        let twoRows = vm.glyphRegions(for: .left)
        XCTAssertEqual(twoRows.count, 2)
        XCTAssertEqual(twoRows[0], CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        XCTAssertEqual(twoRows[1], CGRect(x: 0, y: 0, width: 1, height: 0.5))
    }

    // MARK: - Save Debounce Policy

    func testSaveDebounceCoalescesRapidMutations() async {
        let store = EdgeSnapZoneConfigurationStore()
        var savedSnapshots: [EdgeSnapZoneConfigurationSnapshot] = []

        let vm = ZoneMapPickerViewModel(
            store: store,
            debounceDelay: 0.05,
            onSave: { snapshot in
                savedSnapshots.append(snapshot)
            }
        )

        // Rapid mutations
        vm.setPartitionCount(2, for: .top)
        vm.setPartitionCount(3, for: .top)
        vm.setPartitionCount(4, for: .top)

        // Immediately after, nothing saved yet because of debounce
        XCTAssertTrue(savedSnapshots.isEmpty)

        // Wait past debounce interval
        try? await Task.sleep(nanoseconds: 80_000_000)

        // Exactly one save occurred with the final 4-part state
        XCTAssertEqual(savedSnapshots.count, 1)
        XCTAssertEqual(savedSnapshots.first?.customPartitions[.top]?.count, 4)
    }

    func testSaveDebounceFlushImmediatelyCommits() {
        let store = EdgeSnapZoneConfigurationStore()
        var savedSnapshots: [EdgeSnapZoneConfigurationSnapshot] = []

        let vm = ZoneMapPickerViewModel(
            store: store,
            debounceDelay: 10.0, // long delay
            onSave: { snapshot in
                savedSnapshots.append(snapshot)
            }
        )

        vm.setZoneEnabled(false, for: .top)
        XCTAssertTrue(savedSnapshots.isEmpty)

        // Calling flush immediately executes save
        vm.flushSave()
        XCTAssertEqual(savedSnapshots.count, 1)
        XCTAssertTrue(savedSnapshots.first?.disabledZones.contains(.top) == true)
    }

    // MARK: - Stand-down Banner Visibility Logic

    func testStandDownBannerVisibilityLogic() {
        // macOS 15 state with tiling enabled
        let stoodDownState = SystemTilingState(
            isEdgeTilingEnabled: true,
            isTopTilingEnabled: true,
            isOptionAcceleratorEnabled: false,
            screensHaveSeparateSpaces: true,
            operatingSystemMajorVersion: 15
        )
        let stoodDownStatus = SystemTilingCoexistenceStatus.stoodDown(reason: SystemTilingStandDownReason(
            isEdgeTilingEnabled: true,
            isTopTilingEnabled: true,
            isOptionAcceleratorEnabled: false,
            screensHaveSeparateSpaces: true
        ))
        XCTAssertTrue(stoodDownStatus.isStoodDown)

        // macOS 14 state or disabled tiling
        let activeStatus = SystemTilingCoexistenceStatus.active
        XCTAssertFalse(activeStatus.isStoodDown)

        // Approved copy matches verbatim
        let copy = SettingsCopy.systemTilingStandDownBannerMessage
        XCTAssertTrue(copy.contains("macOS system tiling owns screen edges"))
        XCTAssertTrue(copy.contains("Edge Snap stands down on outer edges"))
        XCTAssertTrue(copy.contains("Shared display seams remain active"))
    }
}
