import CoreGraphics
import XCTest
@testable import MyMacX

final class LayoutLibraryTests: XCTestCase {
    func testSaveMaterializesAValidDraftForWindowPlacement() throws {
        var library = LayoutLibrary()
        let draft = LayoutDraft(
            id: "writing",
            name: "Writing",
            regions: [
                region("editor", x: 0, y: 0, width: 0.7, height: 1),
                region("notes", x: 0.7, y: 0, width: 0.3, height: 1),
            ]
        )

        let result = library.save(draft)

        XCTAssertEqual(result, .success(try materialized(draft)))
        XCTAssertEqual(library.draft(withID: "writing"), draft)
        XCTAssertEqual(library.layout(withID: "writing"), try materialized(draft))
    }

    func testSaveRejectsOverlapWithoutReplacingTheLastValidLayout() throws {
        let original = LayoutDraft(
            id: "work",
            name: "Work",
            regions: [region("full", x: 0, y: 0, width: 1, height: 1)]
        )
        var library = LayoutLibrary()
        XCTAssertEqual(library.save(original), .success(try materialized(original)))

        let invalid = LayoutDraft(
            id: "work",
            name: "Work",
            regions: [
                region("left", x: 0, y: 0, width: 0.6, height: 1),
                region("right", x: 0.5, y: 0, width: 0.5, height: 1),
            ]
        )

        XCTAssertEqual(
            library.save(invalid),
            .failure(.overlappingRegions(
                LayoutRegionID(rawValue: "left"),
                LayoutRegionID(rawValue: "right")
            ))
        )
        XCTAssertEqual(library.draft(withID: "work"), original)
    }

    func testSaveRejectsRegionOutsideNormalizedCanvas() {
        var library = LayoutLibrary()
        let invalid = LayoutDraft(
            id: "unsafe",
            name: "Unsafe",
            regions: [region("escaped", x: 0.8, y: 0, width: 0.3, height: 1)]
        )

        XCTAssertEqual(
            library.save(invalid),
            .failure(.regionOutsideCanvas(LayoutRegionID(rawValue: "escaped")))
        )
        XCTAssertNil(library.draft(withID: "unsafe"))
    }

    func testSplitColumnsReplacesOneRegionWithTwoNonOverlappingRegions() {
        let draft = LayoutDraft(
            id: "main-side",
            name: "Main and Side",
            regions: [region("whole", x: 0, y: 0, width: 1, height: 1)]
        )

        let result = LayoutEditor().apply(
            .split(
                regionID: LayoutRegionID(rawValue: "whole"),
                direction: .columns,
                firstFraction: 0.65,
                firstRegionID: LayoutRegionID(rawValue: "main"),
                secondRegionID: LayoutRegionID(rawValue: "side")
            ),
            to: draft
        )

        XCTAssertEqual(
            result,
            .success(LayoutDraft(
                id: "main-side",
                name: "Main and Side",
                regions: [
                    region("main", x: 0, y: 0, width: 0.65, height: 1),
                    region("side", x: 0.65, y: 0, width: 0.35, height: 1),
                ]
            ))
        )
    }

    func testMergeRejectsRegionsThatDoNotFormOneRectangle() {
        let draft = LayoutDraft(
            id: "l-shape",
            name: "L Shape",
            regions: [
                region("top-left", x: 0, y: 0.5, width: 0.5, height: 0.5),
                region("top-right", x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                region("bottom-left", x: 0, y: 0, width: 0.5, height: 0.5),
            ]
        )

        let result = LayoutEditor().apply(
            .merge(
                regionIDs: [
                    LayoutRegionID(rawValue: "top-left"),
                    LayoutRegionID(rawValue: "top-right"),
                    LayoutRegionID(rawValue: "bottom-left"),
                ],
                mergedRegionID: LayoutRegionID(rawValue: "not-a-rectangle")
            ),
            to: draft
        )

        XCTAssertEqual(result, .failure(.selectedRegionsDoNotFormRectangle))
    }

    func testMergeCreatesTheBoundingRegionForAdjacentSelection() {
        let draft = LayoutDraft(
            id: "thirds",
            name: "Thirds",
            regions: [
                region("left", x: 0, y: 0, width: 0.3, height: 1),
                region("middle", x: 0.3, y: 0, width: 0.4, height: 1),
                region("right", x: 0.7, y: 0, width: 0.3, height: 1),
            ]
        )

        let result = LayoutEditor().apply(
            .merge(
                regionIDs: [
                    LayoutRegionID(rawValue: "middle"),
                    LayoutRegionID(rawValue: "right"),
                ],
                mergedRegionID: LayoutRegionID(rawValue: "wide-right")
            ),
            to: draft
        )

        XCTAssertEqual(
            result,
            .success(LayoutDraft(
                id: "thirds",
                name: "Thirds",
                regions: [
                    region("left", x: 0, y: 0, width: 0.3, height: 1),
                    region("wide-right", x: 0.3, y: 0, width: 0.7, height: 1),
                ]
            ))
        )
    }

    private func region(
        _ id: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> LayoutRegionDraft {
        LayoutRegionDraft(
            id: LayoutRegionID(rawValue: id),
            normalizedFrame: CGRect(x: x, y: y, width: width, height: height)
        )
    }

    private func materialized(_ draft: LayoutDraft) throws -> Layout {
        try Layout(
            id: draft.id,
            regions: draft.regions.map {
                try LayoutRegion(id: $0.id, normalizedFrame: $0.normalizedFrame)
            }
        )
    }
}
