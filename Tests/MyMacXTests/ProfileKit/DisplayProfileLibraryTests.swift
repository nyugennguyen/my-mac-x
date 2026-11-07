import XCTest
@testable import MyMacX

final class DisplayProfileLibraryTests: XCTestCase {
    func testRuntimeToggleGapsChangesFutureLayoutDecisionsWithoutReplacingProfiles() async throws {
        let displayID = DisplayID(rawValue: 7)
        let stableID = try StableDisplayID(rawValue: "uuid:studio")
        let runtime = try DisplayProfileLayoutRuntime(
            stableDisplays: ProfileFixedStableDisplays([displayID: stableID]),
            profiles: [
                try DisplayProfile(
                    stableDisplayID: stableID,
                    gap: 24,
                    layoutIDs: ["built-in"]
                ),
            ]
        )

        let enabled = await runtime.decision(for: "built-in", on: displayID)
        let gapsRemainEnabled = await runtime.toggleGaps()
        let disabled = await runtime.decision(for: "built-in", on: displayID)

        XCTAssertEqual(enabled, .available(LayoutConstraints(gap: 24)))
        XCTAssertFalse(gapsRemainEnabled)
        XCTAssertEqual(disabled, .available(LayoutConstraints(gap: 0)))
    }

    func testReconnectWithTheSameStableDisplayIDResolvesGapAndLayoutSet() throws {
        let firstConnection = try StableDisplayID(rawValue: "uuid:37D8832A-2D66-02CA-B9F7-8F30A301B230")
        var library = DisplayProfileLibrary()
        let profile = try DisplayProfile(
            stableDisplayID: firstConnection,
            gap: 12,
            layoutIDs: ["built-in", "writing"]
        )

        library.assign(profile)

        let reconnected = try StableDisplayID(rawValue: "uuid:37D8832A-2D66-02CA-B9F7-8F30A301B230")
        XCTAssertEqual(library.profile(for: reconnected), profile)
    }

    func testTopologyScopedDisplayIDCannotBeUsedAsAProfileKey() throws {
        var library = DisplayProfileLibrary()
        let stableID = try StableDisplayID(rawValue: "vendor:display-1")
        let profile = try DisplayProfile(
            stableDisplayID: stableID,
            gap: 8,
            layoutIDs: ["built-in"]
        )
        library.assign(profile)

        XCTAssertEqual(library.profile(for: stableID), profile)
        XCTAssertNil(library.profile(for: try StableDisplayID(rawValue: "42")))
    }

    func testProfileRejectsUnsafeGapAndDuplicateLayoutIDs() throws {
        let stableID = try StableDisplayID(rawValue: "uuid:display")

        XCTAssertThrowsError(
            try DisplayProfile(stableDisplayID: stableID, gap: -.infinity, layoutIDs: ["built-in"])
        ) { error in
            XCTAssertEqual(error as? DisplayProfileFailure, .invalidGap)
        }
        XCTAssertThrowsError(
            try DisplayProfile(
                stableDisplayID: stableID,
                gap: 8,
                layoutIDs: ["writing", "writing"]
            )
        ) { error in
            XCTAssertEqual(error as? DisplayProfileFailure, .duplicateLayoutID("writing"))
        }
    }

    func testStableDisplayIDRejectsBlankControlAndOversizedValues() {
        for rawValue in ["", "display\nserial", String(repeating: "x", count: 129)] {
            XCTAssertThrowsError(try StableDisplayID(rawValue: rawValue)) { error in
                XCTAssertEqual(error as? DisplayProfileFailure, .invalidStableDisplayID)
            }
        }
    }

    func testAssignReplacesOnlyTheMatchingStableDisplayProfile() throws {
        let leftID = try StableDisplayID(rawValue: "uuid:left")
        let rightID = try StableDisplayID(rawValue: "uuid:right")
        var library = try DisplayProfileLibrary(profiles: [
            DisplayProfile(stableDisplayID: leftID, gap: 4, layoutIDs: ["built-in"]),
            DisplayProfile(stableDisplayID: rightID, gap: 6, layoutIDs: ["writing"]),
        ])

        let replacement = try DisplayProfile(
            stableDisplayID: leftID,
            gap: 14,
            layoutIDs: ["coding"]
        )
        library.assign(replacement)

        XCTAssertEqual(library.profile(for: leftID), replacement)
        XCTAssertEqual(library.profile(for: rightID)?.gap, 6)
        XCTAssertEqual(library.profiles.map(\.stableDisplayID), [leftID, rightID])
    }

    func testProfileGapValidationAndClamping() throws {
        XCTAssertEqual(DisplayProfile.clampedGap(8), 8)
        XCTAssertEqual(DisplayProfile.clampedGap(12), 12)
        XCTAssertEqual(DisplayProfile.clampedGap(-5), 0)
        XCTAssertEqual(DisplayProfile.clampedGap(250), 200)
        XCTAssertEqual(DisplayProfile.clampedGap(Double.nan), 0)
        XCTAssertEqual(DisplayProfile.clampedGap(Double.infinity), 200)

        XCTAssertTrue(DisplayProfile.isValidGap(0))
        XCTAssertTrue(DisplayProfile.isValidGap(8))
        XCTAssertTrue(DisplayProfile.isValidGap(200))
        XCTAssertFalse(DisplayProfile.isValidGap(-1))
        XCTAssertFalse(DisplayProfile.isValidGap(201))
        XCTAssertFalse(DisplayProfile.isValidGap(Double.nan))
    }

    func testLayoutAssignmentToggleMaintainsAtLeastOneLayout() throws {
        var layoutIDs = ["halves", "quarters"]

        // Toggling an unassigned layout adds it
        layoutIDs = DisplayProfile.toggleLayoutAssignment("thirds", in: layoutIDs)
        XCTAssertEqual(layoutIDs, ["halves", "quarters", "thirds"])

        // Toggling an assigned layout removes it if more than 1 remains
        layoutIDs = DisplayProfile.toggleLayoutAssignment("halves", in: layoutIDs)
        XCTAssertEqual(layoutIDs, ["quarters", "thirds"])

        // Removing down to 1
        layoutIDs = DisplayProfile.toggleLayoutAssignment("quarters", in: layoutIDs)
        XCTAssertEqual(layoutIDs, ["thirds"])

        // Attempting to remove the last layout preserves it (cannot be empty)
        layoutIDs = DisplayProfile.toggleLayoutAssignment("thirds", in: layoutIDs)
        XCTAssertEqual(layoutIDs, ["thirds"])
    }

    func testDisplayProfileCaptionsUseVerbatimStableDisplayID() throws {
        let stableID = try StableDisplayID(rawValue: "4280A3F1")
        let caption = DisplayProfile.caption(for: stableID)
        XCTAssertTrue(caption.contains("Stable Display ID"))
        XCTAssertEqual(caption, "Stable Display ID: 4280A3F1")
    }
}

private struct ProfileFixedStableDisplays: StableDisplayIdentifying {
    let values: [DisplayID: StableDisplayID]

    init(_ values: [DisplayID: StableDisplayID]) {
        self.values = values
    }

    func stableDisplayID(for displayID: DisplayID) -> StableDisplayID? {
        values[displayID]
    }
}
