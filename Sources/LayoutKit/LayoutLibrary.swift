import CoreGraphics
import Foundation

/// An editable representation of a Layout Region.
///
/// Unlike `LayoutRegion`, a draft may temporarily contain invalid geometry so the editor can
/// report a precise validation failure instead of trapping or discarding the user's changes.
struct LayoutRegionDraft: Equatable, Sendable {
    let id: LayoutRegionID
    let normalizedFrame: CGRect

    init(id: LayoutRegionID, normalizedFrame: CGRect) {
        self.id = id
        self.normalizedFrame = normalizedFrame
    }
}

/// One user-named Layout as edited in the Layout Library.
struct LayoutDraft: Equatable, Sendable {
    let id: String
    let name: String
    let regions: [LayoutRegionDraft]

    init(id: String, name: String, regions: [LayoutRegionDraft]) {
        self.id = id
        self.name = name
        self.regions = regions
    }
}

extension LayoutDraft {
    static let halves = LayoutDraft(
        id: "preset-halves",
        name: "Halves",
        regions: [
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "left"), normalizedFrame: CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "right"), normalizedFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        ]
    )

    static let quarters = LayoutDraft(
        id: "preset-quarters",
        name: "Quarters",
        regions: [
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "bottom-left"), normalizedFrame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "bottom-right"), normalizedFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "top-left"), normalizedFrame: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "top-right"), normalizedFrame: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
        ]
    )

    static let thirds = LayoutDraft(
        id: "preset-thirds",
        name: "Thirds",
        regions: [
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "left"), normalizedFrame: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)),
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "center"), normalizedFrame: CGRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)),
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "right"), normalizedFrame: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)),
        ]
    )

    static let center = LayoutDraft(
        id: "preset-center",
        name: "Center",
        regions: [
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "center"), normalizedFrame: CGRect(x: 0.15, y: 0.125, width: 0.7, height: 0.75)),
        ]
    )

    static let coding = LayoutDraft(
        id: "custom-coding",
        name: "Coding",
        regions: [
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "editor"), normalizedFrame: CGRect(x: 0, y: 0, width: 0.625, height: 1)),
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "terminal"), normalizedFrame: CGRect(x: 0.625, y: 0, width: 0.375, height: 0.5)),
            LayoutRegionDraft(id: LayoutRegionID(rawValue: "preview"), normalizedFrame: CGRect(x: 0.625, y: 0.5, width: 0.375, height: 0.5)),
        ]
    )

    static let standardPresets: [LayoutDraft] = [.halves, .quarters, .thirds, .center]
}

enum LayoutLibraryFailure: Error, Equatable, Sendable {
    case emptyLayoutID
    case emptyLayoutName
    case emptyLayout
    case emptyRegionID
    case duplicateRegionID(LayoutRegionID)
    case nonFiniteRegion(LayoutRegionID)
    case emptyRegion(LayoutRegionID)
    case regionOutsideCanvas(LayoutRegionID)
    case overlappingRegions(LayoutRegionID, LayoutRegionID)
    case regionNotFound(LayoutRegionID)
    case invalidSplitFraction
    case replacementRegionIDCollision(LayoutRegionID)
    case mergeRequiresAtLeastTwoRegions
    case selectedRegionsDoNotFormRectangle
}

/// The direction in which one Layout Region is divided.
enum LayoutSplitDirection: Equatable, Sendable {
    /// Creates left and right regions; the first region is on the left.
    case columns
    /// Creates bottom and top regions in AppKit coordinates; the first region is on the bottom.
    case rows
}

enum LayoutEdit: Equatable, Sendable {
    case split(
        regionID: LayoutRegionID,
        direction: LayoutSplitDirection,
        firstFraction: CGFloat,
        firstRegionID: LayoutRegionID,
        secondRegionID: LayoutRegionID
    )
    case merge(regionIDs: [LayoutRegionID], mergedRegionID: LayoutRegionID)
}

/// Pure split/merge editing behind one command-oriented Interface.
struct LayoutEditor: Sendable {
    init() {}

    func apply(
        _ edit: LayoutEdit,
        to draft: LayoutDraft
    ) -> Result<LayoutDraft, LayoutLibraryFailure> {
        if let failure = LayoutDraftValidator.firstFailure(in: draft) {
            return .failure(failure)
        }

        switch edit {
        case let .split(
            regionID,
            direction,
            firstFraction,
            firstRegionID,
            secondRegionID
        ):
            return split(
                regionID: regionID,
                direction: direction,
                firstFraction: firstFraction,
                firstRegionID: firstRegionID,
                secondRegionID: secondRegionID,
                in: draft
            )
        case let .merge(regionIDs, mergedRegionID):
            return merge(regionIDs: regionIDs, mergedRegionID: mergedRegionID, in: draft)
        }
    }

    private func split(
        regionID: LayoutRegionID,
        direction: LayoutSplitDirection,
        firstFraction: CGFloat,
        firstRegionID: LayoutRegionID,
        secondRegionID: LayoutRegionID,
        in draft: LayoutDraft
    ) -> Result<LayoutDraft, LayoutLibraryFailure> {
        guard firstFraction.isFinite, firstFraction > 0, firstFraction < 1 else {
            return .failure(.invalidSplitFraction)
        }
        guard let regionIndex = draft.regions.firstIndex(where: { $0.id == regionID }) else {
            return .failure(.regionNotFound(regionID))
        }
        guard !firstRegionID.rawValue.isEmpty else { return .failure(.emptyRegionID) }
        guard !secondRegionID.rawValue.isEmpty else { return .failure(.emptyRegionID) }
        guard firstRegionID != secondRegionID else {
            return .failure(.replacementRegionIDCollision(firstRegionID))
        }

        let retainedIDs = Set(
            draft.regions.lazy.filter { $0.id != regionID }.map(\.id)
        )
        if retainedIDs.contains(firstRegionID) {
            return .failure(.replacementRegionIDCollision(firstRegionID))
        }
        if retainedIDs.contains(secondRegionID) {
            return .failure(.replacementRegionIDCollision(secondRegionID))
        }

        let frame = draft.regions[regionIndex].normalizedFrame
        let firstFrame: CGRect
        let secondFrame: CGRect
        switch direction {
        case .columns:
            let firstWidth = frame.width * firstFraction
            firstFrame = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: firstWidth,
                height: frame.height
            )
            secondFrame = CGRect(
                x: frame.minX + firstWidth,
                y: frame.minY,
                width: frame.width - firstWidth,
                height: frame.height
            )
        case .rows:
            let firstHeight = frame.height * firstFraction
            firstFrame = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: firstHeight
            )
            secondFrame = CGRect(
                x: frame.minX,
                y: frame.minY + firstHeight,
                width: frame.width,
                height: frame.height - firstHeight
            )
        }

        var regions = draft.regions
        regions.replaceSubrange(
            regionIndex...regionIndex,
            with: [
                LayoutRegionDraft(id: firstRegionID, normalizedFrame: firstFrame),
                LayoutRegionDraft(id: secondRegionID, normalizedFrame: secondFrame),
            ]
        )
        return .success(LayoutDraft(id: draft.id, name: draft.name, regions: regions))
    }

    private func merge(
        regionIDs: [LayoutRegionID],
        mergedRegionID: LayoutRegionID,
        in draft: LayoutDraft
    ) -> Result<LayoutDraft, LayoutLibraryFailure> {
        let selectedIDs = Set(regionIDs)
        guard selectedIDs.count >= 2 else {
            return .failure(.mergeRequiresAtLeastTwoRegions)
        }
        for id in selectedIDs where !draft.regions.contains(where: { $0.id == id }) {
            return .failure(.regionNotFound(id))
        }
        guard !mergedRegionID.rawValue.isEmpty else { return .failure(.emptyRegionID) }
        if draft.regions.contains(where: {
            !selectedIDs.contains($0.id) && $0.id == mergedRegionID
        }) {
            return .failure(.replacementRegionIDCollision(mergedRegionID))
        }

        let selected = draft.regions.filter { selectedIDs.contains($0.id) }
        let boundingFrame = selected.dropFirst().reduce(selected[0].normalizedFrame) {
            $0.union($1.normalizedFrame)
        }
        let selectedArea = selected.reduce(CGFloat.zero) {
            $0 + $1.normalizedFrame.width * $1.normalizedFrame.height
        }
        let boundingArea = boundingFrame.width * boundingFrame.height
        let scale = max(1, abs(selectedArea), abs(boundingArea))
        guard abs(selectedArea - boundingArea) <= scale * 1e-9 else {
            return .failure(.selectedRegionsDoNotFormRectangle)
        }

        let insertionIndex = draft.regions.firstIndex {
            selectedIDs.contains($0.id)
        }!
        var mergedRegions: [LayoutRegionDraft] = []
        for (index, region) in draft.regions.enumerated() {
            if index == insertionIndex {
                mergedRegions.append(LayoutRegionDraft(
                    id: mergedRegionID,
                    normalizedFrame: boundingFrame
                ))
            }
            if !selectedIDs.contains(region.id) {
                mergedRegions.append(region)
            }
        }
        let merged = LayoutDraft(id: draft.id, name: draft.name, regions: mergedRegions)
        if let failure = LayoutDraftValidator.firstFailure(in: merged) {
            return .failure(failure)
        }
        return .success(merged)
    }
}

/// Owns validated user Layouts and is the only save seam for editor drafts.
struct LayoutLibrary: Sendable {
    private var savedDraftsByID: [String: LayoutDraft] = [:]
    private var layoutOrder: [String] = []

    init() {}

    var drafts: [LayoutDraft] {
        layoutOrder.compactMap { savedDraftsByID[$0] }
    }

    mutating func save(_ draft: LayoutDraft) -> Result<Layout, LayoutLibraryFailure> {
        if let failure = LayoutDraftValidator.firstFailure(in: draft) {
            return .failure(failure)
        }

        do {
            let layout = try Layout(
                id: draft.id,
                regions: draft.regions.map {
                    try LayoutRegion(id: $0.id, normalizedFrame: $0.normalizedFrame)
                }
            )
            if savedDraftsByID[draft.id] == nil {
                layoutOrder.append(draft.id)
            }
            savedDraftsByID[draft.id] = draft
            return .success(layout)
        } catch {
            preconditionFailure("Layout draft validation and Layout invariants diverged: \(error)")
        }
    }

    func draft(withID id: String) -> LayoutDraft? {
        savedDraftsByID[id]
    }

    func layout(withID id: String) -> Layout? {
        guard let draft = savedDraftsByID[id] else { return nil }
        return try? Layout(
            id: draft.id,
            regions: draft.regions.map {
                try LayoutRegion(id: $0.id, normalizedFrame: $0.normalizedFrame)
            }
        )
    }
}

private enum LayoutDraftValidator {
    static func firstFailure(in draft: LayoutDraft) -> LayoutLibraryFailure? {
        guard !draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emptyLayoutID
        }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emptyLayoutName
        }
        guard !draft.regions.isEmpty else { return .emptyLayout }

        var regionIDs = Set<LayoutRegionID>()
        for region in draft.regions {
            guard !region.id.rawValue.isEmpty else { return .emptyRegionID }
            guard regionIDs.insert(region.id).inserted else {
                return .duplicateRegionID(region.id)
            }

            let frame = region.normalizedFrame
            guard frame.origin.x.isFinite,
                  frame.origin.y.isFinite,
                  frame.width.isFinite,
                  frame.height.isFinite else {
                return .nonFiniteRegion(region.id)
            }
            guard frame.width > 0, frame.height > 0 else {
                return .emptyRegion(region.id)
            }
            guard frame.minX >= 0,
                  frame.minY >= 0,
                  frame.maxX <= 1,
                  frame.maxY <= 1 else {
                return .regionOutsideCanvas(region.id)
            }
        }

        for leftIndex in draft.regions.indices {
            for rightIndex in draft.regions.indices where rightIndex > leftIndex {
                let left = draft.regions[leftIndex]
                let right = draft.regions[rightIndex]
                let intersection = left.normalizedFrame.intersection(right.normalizedFrame)
                if !intersection.isNull, intersection.width > 0, intersection.height > 0 {
                    return .overlappingRegions(left.id, right.id)
                }
            }
        }
        return nil
    }
}
