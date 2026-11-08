import CoreGraphics
import Foundation
import XCTest
@testable import MyMacX

final class EdgeSnapZoneConfigurationStoreTests: XCTestCase {

    // MARK: - Z-06 Delta Compaction

    func testDefaultConfigurationEncodesToEmptyString() {
        let snapshot = EdgeSnapZoneConfigurationSnapshot()
        let encoded = EdgeSnapZoneDeltaCodec.encodeZoneActions(snapshot)
        XCTAssertEqual(encoded, "", "Unconfigured layout must serialize to empty string per Z-06")
    }

    func testCustomActionEncodesOnlyDeviationsFromDefaults() {
        var snapshot = EdgeSnapZoneConfigurationSnapshot()
        // Default for top is maximize; changing it to topHalf is a deviation
        snapshot.customActions[.top] = .topHalf
        // Left default is leftHalf; setting left to leftHalf is NOT a deviation
        snapshot.customActions[.left] = .leftHalf

        let encoded = EdgeSnapZoneDeltaCodec.encodeZoneActions(snapshot)
        XCTAssertEqual(encoded, "top=window.top-half")
    }

    func testPartitionedEdgeActionsEncodeWithPlusJoiner() {
        var snapshot = EdgeSnapZoneConfigurationSnapshot()
        snapshot.customPartitions[.right] = [.topHalf, .bottomHalf]

        let encoded = EdgeSnapZoneDeltaCodec.encodeZoneActions(snapshot)
        XCTAssertEqual(encoded, "right=window.top-half+window.bottom-half")
    }

    func testDeterministicAlphabeticalOrCanonicalSorting() {
        var snapshot = EdgeSnapZoneConfigurationSnapshot()
        snapshot.customActions[.bottom] = .bottomLeftQuarter
        snapshot.customActions[.top] = .topHalf

        let encoded = EdgeSnapZoneDeltaCodec.encodeZoneActions(snapshot)
        XCTAssertEqual(encoded, "bottom=window.bottom-left-quarter,top=window.top-half")
    }

    func testDecodeEmptyStringReturnsDefaults() {
        let (actions, partitions) = EdgeSnapZoneDeltaCodec.decodeZoneActions("")
        XCTAssertTrue(actions.isEmpty)
        XCTAssertTrue(partitions.isEmpty)
    }

    func testRoundTripCustomActionsAndPartitions() {
        var original = EdgeSnapZoneConfigurationSnapshot()
        original.customActions[.top] = .topHalf
        original.customPartitions[.right] = [.topHalf, .bottomHalf]

        let encoded = EdgeSnapZoneDeltaCodec.encodeZoneActions(original)
        let (decodedActions, decodedPartitions) = EdgeSnapZoneDeltaCodec.decodeZoneActions(encoded)

        XCTAssertEqual(decodedActions[.top], .topHalf)
        XCTAssertEqual(decodedPartitions[.right], [.topHalf, .bottomHalf])
        XCTAssertEqual(decodedActions[.right], .topHalf)
    }

    // MARK: - Z-07 Resilient Fallback on Malformed, Unknown or Future Entries

    func testMalformedTokenMissingEqualsIsDiscardedAndSurfacedToDiagnostics() {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)

        let (actions, _) = EdgeSnapZoneDeltaCodec.decodeZoneActions(
            "corruptToken,top=window.top-half",
            diagnostics: logger
        )

        XCTAssertEqual(actions[.top], .topHalf)
        XCTAssertNil(actions[.topLeft])
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])
    }

    func testUnknownZoneNameIsDiscardedAndSurfacedToDiagnostics() {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)

        let (actions, _) = EdgeSnapZoneDeltaCodec.decodeZoneActions(
            "middleScreen=window.maximize,top=window.top-half",
            diagnostics: logger
        )

        XCTAssertEqual(actions[.top], .topHalf)
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])
    }

    func testDisallowedActionIsRejectedAndZoneRevertsToDefault() {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)

        // window.cycle-left-edge is a relative cycle action, not in permitted edge snap placement whitelist (Z-05)
        let (actions, _) = EdgeSnapZoneDeltaCodec.decodeZoneActions(
            "left=window.cycle-left-edge,top=window.top-half",
            diagnostics: logger
        )

        XCTAssertNil(actions[.left], "Rejected action must revert to default (absent from custom actions)")
        XCTAssertEqual(actions[.top], .topHalf, "Valid sibling zone must be preserved")
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])
    }

    func testCornerZoneExceedingSinglePartIsRejected() {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)

        // Corners have maximumParts = 1 (Z-03)
        let (actions, partitions) = EdgeSnapZoneDeltaCodec.decodeZoneActions(
            "topLeft=window.top-half+window.bottom-half,top=window.top-half",
            diagnostics: logger
        )

        XCTAssertNil(actions[.topLeft])
        XCTAssertNil(partitions[.topLeft])
        XCTAssertEqual(actions[.top], .topHalf)
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])
    }

    func testStraightEdgeExceedingMaximumFourPartsIsRejected() {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)

        // Edges have maximumParts = 4 (Z-03)
        let fiveParts = "right=window.top-half+window.bottom-half+window.left-half+window.right-half+window.maximize"
        let (actions, partitions) = EdgeSnapZoneDeltaCodec.decodeZoneActions(
            fiveParts,
            diagnostics: logger
        )

        XCTAssertNil(actions[.right])
        XCTAssertNil(partitions[.right])
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])
    }

    func testFaultIsolationWhenOneSubPartOfSplitEdgeIsInvalid() {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)

        // Second part is invalid action
        let (actions, partitions) = EdgeSnapZoneDeltaCodec.decodeZoneActions(
            "right=window.top-half+nonexistent.action,left=window.left-third",
            diagnostics: logger
        )

        XCTAssertNil(actions[.right], "Entire zone entry is discarded if any part fails validation per Z-07")
        XCTAssertNil(partitions[.right])
        XCTAssertEqual(actions[.left], .leftThird, "Valid sibling entry must be retained")
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])
    }

    // MARK: - Z-08 Disabled Zones

    func testEncodeDisabledZonesOnlyStoresDisabled() {
        var snapshot = EdgeSnapZoneConfigurationSnapshot()
        snapshot.disabledZones = [.top, .bottom]

        let encoded = EdgeSnapZoneDeltaCodec.encodeDisabledZones(snapshot)
        XCTAssertEqual(encoded, ["bottom", "top"])
    }

    func testDecodeDisabledZonesIgnoresUnknownAndLogsAnomaly() {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)

        let disabled = EdgeSnapZoneDeltaCodec.decodeDisabledZones(
            ["top", "unknownPerimeter", "bottom"],
            diagnostics: logger
        )

        XCTAssertEqual(disabled, [.top, .bottom])
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])
    }

    // MARK: - Seam Gate Settings

    func testSeamGateSettingsDefaultAndCustomRoundTrip() {
        let defaults = SeamGateSettings()
        XCTAssertTrue(defaults.isEnabled)
        XCTAssertEqual(defaults.crossingSpeedThreshold, 400.0)

        let custom = SeamGateSettings(isEnabled: false, crossingSpeedThreshold: 250.0)
        XCTAssertFalse(custom.isEnabled)
        XCTAssertEqual(custom.crossingSpeedThreshold, 250.0)
    }

    func testInvalidCrossingSpeedThresholdDegradesSafely() {
        let writer = RecordingDiagnosticsWriter()
        let logger = PrivacySafeDiagnosticsLogger(writer: writer)

        let validatedNegative = EdgeSnapZoneDeltaCodec.validateCrossingSpeedThreshold(-50.0, diagnostics: logger)
        XCTAssertEqual(validatedNegative, 400.0)
        XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: .persistenceDecodeAnomaly, severity: .error)])

        let validatedInfinity = EdgeSnapZoneDeltaCodec.validateCrossingSpeedThreshold(.infinity, diagnostics: logger)
        XCTAssertEqual(validatedInfinity, 400.0)
    }

    // MARK: - EdgeSnapZoneConfigurationStore Interface Contract

    @MainActor
    func testStoreInitializesWithDefaultsAndReportsDefaultState() {
        let store = EdgeSnapZoneConfigurationStore()

        XCTAssertTrue(store.isAllDefault)
        XCTAssertTrue(store.isDefault(zone: .top))
        XCTAssertEqual(store.action(for: .top), EdgeSnapZone.top.defaultAction)
        XCTAssertTrue(store.isEnabled(.top))
        XCTAssertEqual(store.seamGateSettings(), SeamGateSettings())

        let config = store.configuration
        XCTAssertEqual(config.action(for: .top), .maximize)
        XCTAssertTrue(config.isEnabled(.top))
    }

    @MainActor
    func testStoreSetActionMutatesAndNotifies() {
        let store = EdgeSnapZoneConfigurationStore()
        var notifiedSnapshot: EdgeSnapZoneConfigurationSnapshot?
        store.onConfigurationChanged = { snapshot in
            notifiedSnapshot = snapshot
        }

        store.setAction(.topHalf, for: .top)

        XCTAssertFalse(store.isAllDefault)
        XCTAssertFalse(store.isDefault(zone: .top))
        XCTAssertTrue(store.isDefault(zone: .bottom))
        XCTAssertEqual(store.action(for: .top), .topHalf)
        XCTAssertEqual(store.actions(for: .top), [.topHalf])
        XCTAssertEqual(notifiedSnapshot?.customActions[.top], .topHalf)
        XCTAssertEqual(store.configuration.action(for: .top), .topHalf)
    }

    @MainActor
    func testStoreSetPartitionsAndToggleEnabled() {
        let store = EdgeSnapZoneConfigurationStore()

        store.setActions([.topHalf, .bottomHalf], for: .right)
        XCTAssertEqual(store.actions(for: .right), [.topHalf, .bottomHalf])
        XCTAssertEqual(store.action(for: .right), .topHalf)

        store.setEnabled(false, for: .top)
        XCTAssertFalse(store.isEnabled(.top))
        XCTAssertFalse(store.configuration.isEnabled(.top))

        store.toggleEnabled(for: .top)
        XCTAssertTrue(store.isEnabled(.top))
        XCTAssertTrue(store.configuration.isEnabled(.top))
    }

    @MainActor
    func testStoreResetZoneAndResetAll() {
        let store = EdgeSnapZoneConfigurationStore()
        store.setAction(.topHalf, for: .top)
        store.setAction(.bottomLeftQuarter, for: .bottom)
        store.setEnabled(false, for: .left)
        store.setCrossingSpeedThreshold(200.0)

        XCTAssertFalse(store.isAllDefault)

        store.reset(zone: .top)
        XCTAssertTrue(store.isDefault(zone: .top))
        XCTAssertEqual(store.action(for: .top), EdgeSnapZone.top.defaultAction)
        XCTAssertFalse(store.isDefault(zone: .bottom))

        store.resetAllToDefaults()
        XCTAssertTrue(store.isAllDefault)
        XCTAssertTrue(store.isDefault(zone: .bottom))
        XCTAssertTrue(store.isEnabled(.left))
        XCTAssertEqual(store.seamGateSettings(), SeamGateSettings())
    }
}

private final class RecordingDiagnosticsWriter: DiagnosticsLogWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEntries: [DiagnosticsLogEntry] = []

    var entries: [DiagnosticsLogEntry] {
        lock.withLock { storedEntries }
    }

    func write(_ entry: DiagnosticsLogEntry) {
        lock.withLock {
            storedEntries.append(entry)
        }
    }
}
