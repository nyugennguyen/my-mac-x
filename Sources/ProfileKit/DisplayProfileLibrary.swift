import AppKit
import Foundation

/// A reconnect-stable physical Display identity supplied by a system Adapter.
///
/// This is deliberately distinct from ScreenKit's topology-scoped `DisplayID`, which must never
/// be persisted or used to correlate a Display after reconnect.
struct StableDisplayID: Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        guard !rawValue.isEmpty,
              rawValue.utf8.count <= 128,
              rawValue.unicodeScalars.allSatisfy(allowed.contains) else {
            throw DisplayProfileFailure.invalidStableDisplayID
        }
        self.rawValue = rawValue
    }
}

/// Gap and ordered Layout set selected for one physical Display.
struct DisplayProfile: Equatable, Sendable {
    static let maximumGap: Double = 200

    let stableDisplayID: StableDisplayID
    let gap: Double
    let layoutIDs: [String]

    init(
        stableDisplayID: StableDisplayID,
        gap: Double,
        layoutIDs: [String]
    ) throws {
        guard gap.isFinite, gap >= 0, gap <= Self.maximumGap else {
            throw DisplayProfileFailure.invalidGap
        }
        guard !layoutIDs.isEmpty else {
            throw DisplayProfileFailure.emptyLayoutSet
        }

        var seenLayoutIDs = Set<String>()
        for layoutID in layoutIDs {
            let trimmed = layoutID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard layoutID == trimmed,
                  !layoutID.isEmpty,
                  layoutID.utf8.count <= 128,
                  !layoutID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                throw DisplayProfileFailure.invalidLayoutID(layoutID)
            }
            guard seenLayoutIDs.insert(layoutID).inserted else {
                throw DisplayProfileFailure.duplicateLayoutID(layoutID)
            }
        }

        self.stableDisplayID = stableDisplayID
        self.gap = gap
        self.layoutIDs = layoutIDs
    }
}

extension DisplayProfile {
    static func isValidGap(_ gap: Double) -> Bool {
        gap.isFinite && gap >= 0 && gap <= maximumGap
    }

    static func clampedGap(_ gap: Double) -> Double {
        guard gap.isFinite else {
            return gap.isInfinite && gap > 0 ? maximumGap : 0
        }
        return min(max(gap, 0), maximumGap)
    }

    static func toggleLayoutAssignment(_ layoutID: String, in currentIDs: [String]) -> [String] {
        if currentIDs.contains(layoutID) {
            if currentIDs.count > 1 {
                return currentIDs.filter { $0 != layoutID }
            }
            return currentIDs
        } else {
            return currentIDs + [layoutID]
        }
    }

    static func caption(for stableDisplayID: StableDisplayID) -> String {
        "Stable Display ID: \(stableDisplayID.rawValue)"
    }
}

enum DisplayProfileFailure: Error, Equatable, Sendable {
    case invalidStableDisplayID
    case invalidGap
    case emptyLayoutSet
    case invalidLayoutID(String)
    case duplicateLayoutID(String)
    case duplicateStableDisplayID(StableDisplayID)
}

/// Owns Display profiles keyed exclusively by reconnect-stable identity.
struct DisplayProfileLibrary: Sendable {
    private var profilesByStableID: [StableDisplayID: DisplayProfile]
    private var stableIDOrder: [StableDisplayID]

    init() {
        profilesByStableID = [:]
        stableIDOrder = []
    }

    init(profiles: [DisplayProfile]) throws {
        var byID: [StableDisplayID: DisplayProfile] = [:]
        var order: [StableDisplayID] = []
        for profile in profiles {
            guard byID[profile.stableDisplayID] == nil else {
                throw DisplayProfileFailure.duplicateStableDisplayID(profile.stableDisplayID)
            }
            byID[profile.stableDisplayID] = profile
            order.append(profile.stableDisplayID)
        }
        profilesByStableID = byID
        stableIDOrder = order
    }

    var profiles: [DisplayProfile] {
        stableIDOrder.compactMap { profilesByStableID[$0] }
    }

    mutating func assign(_ profile: DisplayProfile) {
        if profilesByStableID[profile.stableDisplayID] == nil {
            stableIDOrder.append(profile.stableDisplayID)
        }
        profilesByStableID[profile.stableDisplayID] = profile
    }

    func profile(for stableDisplayID: StableDisplayID) -> DisplayProfile? {
        profilesByStableID[stableDisplayID]
    }
}

enum DisplayProfileLayoutDecision: Equatable, Sendable {
    case available(LayoutConstraints)
    case layoutUnavailable
}

/// Resolves all per-Display profile policy needed by the Window Action Module.
protocol DisplayProfileLayoutResolving: Sendable {
    func decision(for layoutID: String, on displayID: DisplayID) async -> DisplayProfileLayoutDecision
}

struct DefaultDisplayProfileLayoutResolver: DisplayProfileLayoutResolving {
    func decision(for layoutID: String, on displayID: DisplayID) async -> DisplayProfileLayoutDecision {
        .available(.default)
    }
}

protocol StableDisplayIdentifying: Sendable {
    func stableDisplayID(for displayID: DisplayID) -> StableDisplayID?
}

/// Production Adapter deriving reconnect-stable UUID identity from a live CoreGraphics Display.
struct CoreGraphicsStableDisplayAdapter: StableDisplayIdentifying {
    func stableDisplayID(for displayID: DisplayID) -> StableDisplayID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID.rawValue)?.takeRetainedValue()
        else { return nil }
        return try? StableDisplayID(rawValue: CFUUIDCreateString(nil, uuid) as String)
    }
}

/// Mutable production runtime for Display Profiles. Settings can replace its configuration
/// without rebuilding callers, while Window Actions resolve one coherent snapshot.
actor DisplayProfileLayoutRuntime: DisplayProfileLayoutResolving {
    private let stableDisplays: any StableDisplayIdentifying
    private var library: DisplayProfileLibrary
    private var gapsEnabled: Bool

    init(
        stableDisplays: any StableDisplayIdentifying,
        profiles: [DisplayProfile] = [],
        gapsEnabled: Bool = true
    ) throws {
        self.stableDisplays = stableDisplays
        library = try DisplayProfileLibrary(profiles: profiles)
        self.gapsEnabled = gapsEnabled
    }

    func replaceProfiles(_ profiles: [DisplayProfile]) throws {
        library = try DisplayProfileLibrary(profiles: profiles)
    }

    @discardableResult
    func toggleGaps() -> Bool {
        gapsEnabled.toggle()
        return gapsEnabled
    }

    func decision(for layoutID: String, on displayID: DisplayID) -> DisplayProfileLayoutDecision {
        guard let stableID = stableDisplays.stableDisplayID(for: displayID),
              let profile = library.profile(for: stableID) else {
            return .available(.default)
        }
        guard profile.layoutIDs.contains(layoutID) else { return .layoutUnavailable }
        return .available(LayoutConstraints(gap: gapsEnabled ? CGFloat(profile.gap) : 0))
    }
}
