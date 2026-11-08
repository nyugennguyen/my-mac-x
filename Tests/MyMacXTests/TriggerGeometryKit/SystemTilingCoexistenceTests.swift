import CoreGraphics
import XCTest

@testable import MyMacX

final class MockSystemTilingPreferencesReader: SystemTilingPreferencesReading, @unchecked Sendable {
    var preferences: [String: Any] = [:]
    var separateSpaces: Bool = true
    var osMajorVersion: Int = 15

    func readWindowManagerPreference(forKey key: String) -> Any? {
        preferences[key]
    }

    func screensHaveSeparateSpaces() -> Bool {
        separateSpaces
    }

    func operatingSystemMajorVersion() -> Int {
        osMajorVersion
    }
}

final class SystemTilingCoexistenceTests: XCTestCase {
    // MARK: - Unwritten Defaults Rule (Z-09)

    func testUnwrittenPreferencesOnMacOS15DefaultToEnabled() {
        let mock = MockSystemTilingPreferencesReader()
        mock.osMajorVersion = 15
        mock.preferences = [:] // unwritten

        let reader = SystemTilingPreferenceReader(reader: mock)
        let state = reader.readState()

        XCTAssertTrue(state.isEdgeTilingEnabled, "Unwritten EnableTilingByEdgeDrag must default to true on macOS 15+")
        XCTAssertTrue(state.isTopTilingEnabled, "Unwritten EnableTopTilingByEdgeDrag must default to true on macOS 15+")
        XCTAssertFalse(state.isOptionAcceleratorEnabled, "Unwritten EnableTilingOptionAccelerator defaults to false")
        XCTAssertTrue(state.screensHaveSeparateSpaces)
        XCTAssertEqual(state.operatingSystemMajorVersion, 15)
    }

    func testExplicitFalseOverridesDefaultOnMacOS15() {
        let mock = MockSystemTilingPreferencesReader()
        mock.osMajorVersion = 15
        mock.preferences = [
            SystemTilingPreferenceReader.edgeTilingKey: false,
            SystemTilingPreferenceReader.topTilingKey: false,
            SystemTilingPreferenceReader.optionAcceleratorKey: true
        ]

        let reader = SystemTilingPreferenceReader(reader: mock)
        let state = reader.readState()

        XCTAssertFalse(state.isEdgeTilingEnabled)
        XCTAssertFalse(state.isTopTilingEnabled)
        XCTAssertTrue(state.isOptionAcceleratorEnabled)
    }

    func testExplicitTruePreservedOnMacOS15() {
        let mock = MockSystemTilingPreferencesReader()
        mock.osMajorVersion = 15
        mock.preferences = [
            SystemTilingPreferenceReader.edgeTilingKey: true,
            SystemTilingPreferenceReader.topTilingKey: false,
        ]

        let reader = SystemTilingPreferenceReader(reader: mock)
        let state = reader.readState()

        XCTAssertTrue(state.isEdgeTilingEnabled)
        XCTAssertFalse(state.isTopTilingEnabled)
    }

    func testMacOS14AlwaysEvaluatesTilingToDisabled() {
        let mock = MockSystemTilingPreferencesReader()
        mock.osMajorVersion = 14
        mock.preferences = [
            SystemTilingPreferenceReader.edgeTilingKey: true,
            SystemTilingPreferenceReader.topTilingKey: true
        ]

        let reader = SystemTilingPreferenceReader(reader: mock)
        let state = reader.readState()

        XCTAssertFalse(state.isEdgeTilingEnabled, "macOS 14 has no native tiling")
        XCTAssertFalse(state.isTopTilingEnabled, "macOS 14 has no native tiling")
        XCTAssertFalse(state.isOptionAcceleratorEnabled)
    }

    func testScreensHaveSeparateSpacesReflected() {
        let mock = MockSystemTilingPreferencesReader()
        mock.separateSpaces = false

        let reader = SystemTilingPreferenceReader(reader: mock)
        let state = reader.readState()

        XCTAssertFalse(state.screensHaveSeparateSpaces)
    }

    // MARK: - Coexistence Detector & Seam Gating Rules

    func testSharedDisplaySeamsNeverStandDown() {
        let detector = SystemTilingCoexistenceDetector()
        let state = SystemTilingState(
            isEdgeTilingEnabled: true,
            isTopTilingEnabled: true,
            isOptionAcceleratorEnabled: false,
            screensHaveSeparateSpaces: true,
            operatingSystemMajorVersion: 15
        )

        // All zones across shared seams must NOT stand down
        for zone in EdgeSnapZone.allCases {
            XCTAssertFalse(
                detector.standsDown(for: zone, isSharedSeam: true, state: state),
                "Shared display seam for zone \(zone) must never stand down for system tiling"
            )
        }
    }

    func testOuterWallsStandDownWhenNativeTilingEnabledOnMacOS15() {
        let detector = SystemTilingCoexistenceDetector()
        let state = SystemTilingState(
            isEdgeTilingEnabled: true,
            isTopTilingEnabled: true,
            isOptionAcceleratorEnabled: false,
            screensHaveSeparateSpaces: true,
            operatingSystemMajorVersion: 15
        )

        XCTAssertTrue(detector.standsDown(for: .left, isSharedSeam: false, state: state))
        XCTAssertTrue(detector.standsDown(for: .right, isSharedSeam: false, state: state))
        XCTAssertTrue(detector.standsDown(for: .top, isSharedSeam: false, state: state))
    }

    func testOuterWallsActiveWhenNativeTilingDisabled() {
        let detector = SystemTilingCoexistenceDetector()
        let state = SystemTilingState(
            isEdgeTilingEnabled: false,
            isTopTilingEnabled: false,
            isOptionAcceleratorEnabled: false,
            screensHaveSeparateSpaces: true,
            operatingSystemMajorVersion: 15
        )

        XCTAssertFalse(detector.standsDown(for: .left, isSharedSeam: false, state: state))
        XCTAssertFalse(detector.standsDown(for: .right, isSharedSeam: false, state: state))
        XCTAssertFalse(detector.standsDown(for: .top, isSharedSeam: false, state: state))
    }

    // MARK: - Spans Displays / Separate Spaces Disabled (Major 4, Z-09)

    func testOuterWallsActiveWhenSeparateSpacesDisabledEvenWithTilingEnabled() {
        let detector = SystemTilingCoexistenceDetector()
        // When separate Spaces is disabled (spans-displays = true), macOS 15 tiling is inert
        let state = SystemTilingState(
            isEdgeTilingEnabled: true,
            isTopTilingEnabled: true,
            isOptionAcceleratorEnabled: false,
            screensHaveSeparateSpaces: false,
            operatingSystemMajorVersion: 15
        )

        XCTAssertFalse(detector.standsDown(for: .left, isSharedSeam: false, state: state), "Must not stand down on left edge when separate spaces is disabled")
        XCTAssertFalse(detector.standsDown(for: .right, isSharedSeam: false, state: state), "Must not stand down on right edge when separate spaces is disabled")
        XCTAssertFalse(detector.standsDown(for: .top, isSharedSeam: false, state: state), "Must not stand down on top edge when separate spaces is disabled")
        XCTAssertFalse(detector.standsDown(for: .bottom, isSharedSeam: false, state: state), "Must not stand down on bottom edge when separate spaces is disabled")
        XCTAssertFalse(detector.standsDown(for: .topLeft, isSharedSeam: false, state: state), "Must not stand down on corners when separate spaces is disabled")
    }

    // MARK: - Observable Status Model

    @MainActor
    func testObservableStatusModelUpdatesStateAndStatus() {
        let mock = MockSystemTilingPreferencesReader()
        mock.osMajorVersion = 15
        mock.preferences = [SystemTilingPreferenceReader.edgeTilingKey: true]

        let reader = SystemTilingPreferenceReader(reader: mock)
        let model = SystemTilingCoexistenceModel(reader: reader)

        XCTAssertEqual(
            model.status,
            .stoodDown(reason: SystemTilingStandDownReason(
                isEdgeTilingEnabled: true,
                isTopTilingEnabled: true,
                isOptionAcceleratorEnabled: false,
                screensHaveSeparateSpaces: true
            ))
        )

        // Now user toggles tiling off in System Settings
        mock.preferences = [
            SystemTilingPreferenceReader.edgeTilingKey: false,
            SystemTilingPreferenceReader.topTilingKey: false
        ]
        model.refresh()

        XCTAssertEqual(model.status, .active)
    }

    @MainActor
    func testAppDidBecomeActiveNotificationTriggersPreferenceRefresh() {
        let mock = MockSystemTilingPreferencesReader()
        mock.preferences = [
            SystemTilingPreferenceReader.edgeTilingKey: true,
            SystemTilingPreferenceReader.topTilingKey: true
        ]
        let reader = SystemTilingPreferenceReader(reader: mock)
        let model = SystemTilingCoexistenceModel(reader: reader)
        XCTAssertEqual(
            model.status,
            .stoodDown(reason: SystemTilingStandDownReason(
                isEdgeTilingEnabled: true,
                isTopTilingEnabled: true,
                isOptionAcceleratorEnabled: false,
                screensHaveSeparateSpaces: true
            ))
        )

        // Preferences change externally (cross-process write via cfprefsd)
        mock.preferences = [
            SystemTilingPreferenceReader.edgeTilingKey: false,
            SystemTilingPreferenceReader.topTilingKey: false
        ]

        // App becomes active
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        // The model observes on the main queue; drain it before asserting.
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)

        XCTAssertEqual(model.status, .active, "App activation must refresh system tiling preferences")
    }
}
