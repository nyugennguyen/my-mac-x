import AppKit
import SwiftUI

// MARK: - Section Anchors

public enum SettingsAnchorID: String, CaseIterable, Identifiable, Sendable {
    case generalPermissions = "general.permissions"
    case generalStartup = "general.startup"
    case snappingMaster = "snapping.master"
    case snappingTrigger = "snapping.trigger"
    case snappingPreview = "snapping.preview"
    case snappingReducedEffects = "snapping.reduced_effects"
    case snappingZoneMap = "snapping.zone_map"
    case snappingSeamGating = "snapping.seam_gating"
    case hotkeysSuperMode = "hotkeys.super_mode"
    case hotkeysCommandTree = "hotkeys.command_tree"
    case hotkeysGlobal = "hotkeys.global"
    case layoutsLibrary = "layouts.library"
    case displayProfiles = "displays.profiles"
    case appRules = "app_rules.rules"
    case transferBackup = "transfer.backup"
    case aboutDiagnostics = "about.diagnostics"

    public var id: String { rawValue }

    public var section: SettingsSection {
        switch self {
        case .generalPermissions, .generalStartup:
            return .general
        case .snappingMaster, .snappingTrigger, .snappingPreview, .snappingReducedEffects, .snappingZoneMap, .snappingSeamGating:
            return .snapping
        case .hotkeysSuperMode, .hotkeysCommandTree, .hotkeysGlobal:
            return .hotkeys
        case .layoutsLibrary:
            return .layouts
        case .displayProfiles:
            return .displays
        case .appRules:
            return .appRules
        case .transferBackup:
            return .transfer
        case .aboutDiagnostics:
            return .about
        }
    }

    public var title: String {
        switch self {
        case .generalPermissions:
            return "Permissions"
        case .generalStartup:
            return "Startup"
        case .snappingMaster:
            return "Window Snapping"
        case .snappingTrigger:
            return "Trigger & Activation Delay"
        case .snappingPreview:
            return "Placement Preview"
        case .snappingReducedEffects:
            return "Reduce Visual Effects"
        case .snappingZoneMap:
            return "Perimeter Zone Map"
        case .snappingSeamGating:
            return "Multi-Display Seam Gating"
        case .hotkeysSuperMode:
            return "Super Mode"
        case .hotkeysCommandTree:
            return "Command Tree"
        case .hotkeysGlobal:
            return "Global Hotkeys"
        case .layoutsLibrary:
            return "Layout Library"
        case .displayProfiles:
            return "Display Profiles"
        case .appRules:
            return "Application Rules"
        case .transferBackup:
            return "Configuration Backup"
        case .aboutDiagnostics:
            return "About & Diagnostics"
        }
    }
}

// MARK: - Search Item & Result Group

public struct SettingsSearchItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let section: SettingsSection
    public let anchor: SettingsAnchorID
    public let title: String
    public let caption: String
    public let keywords: [String]

    public init(
        anchor: SettingsAnchorID,
        title: String,
        caption: String,
        keywords: [String] = []
    ) {
        self.id = anchor.rawValue + "." + title.lowercased().replacingOccurrences(of: " ", with: "_")
        self.section = anchor.section
        self.anchor = anchor
        self.title = title
        self.caption = caption
        self.keywords = keywords
    }

    public func matches(query: String) -> Bool {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return false }

        let searchable = [
            title.lowercased(),
            caption.lowercased(),
            section.title.lowercased(),
        ] + keywords.map { $0.lowercased() }

        return terms.allSatisfy { term in
            searchable.contains { $0.contains(term) }
        }
    }
}

public struct SettingsSearchResultGroup: Identifiable, Equatable, Sendable {
    public var id: SettingsSection { section }
    public let section: SettingsSection
    public let items: [SettingsSearchItem]

    public init(section: SettingsSection, items: [SettingsSearchItem]) {
        self.section = section
        self.items = items
    }
}

// MARK: - Search Index

public struct SettingsSearchIndex: Sendable {
    public let items: [SettingsSearchItem]

    public static let defaultItems: [SettingsSearchItem] = [
        // General
        SettingsSearchItem(
            anchor: .generalPermissions,
            title: "Permissions",
            caption: "Accessibility and Input Monitoring system permissions.",
            keywords: ["accessibility", "input monitoring", "security", "privacy", "grant"]
        ),
        SettingsSearchItem(
            anchor: .generalStartup,
            title: "Launch at Login",
            caption: "Start My Mac X automatically when you log in.",
            keywords: ["startup", "boot", "login", "auto start"]
        ),

        // Snapping
        SettingsSearchItem(
            anchor: .snappingMaster,
            title: "Enable Window Snapping",
            caption: "Snap windows to screen edges and the top-notch trigger area.",
            keywords: ["notch", "edge snap", "trigger", "drag"]
        ),
        SettingsSearchItem(
            anchor: .snappingTrigger,
            title: "Snapping Trigger",
            caption: "Choose between Notch or Top-center trigger bar.",
            keywords: ["notch trigger", "top-center", "delay", "dwell", "activation"]
        ),
        SettingsSearchItem(
            anchor: .snappingTrigger,
            title: "Activation Delay",
            caption: "Dwell time before snapping zones appear.",
            keywords: ["dwell", "delay", "milliseconds", "timing", "wait"]
        ),
        SettingsSearchItem(
            anchor: .snappingPreview,
            title: "Placement Preview",
            caption: "Show transparent outline overlay of window placement before committing.",
            keywords: ["overlay", "preview", "outline", "ghost", "frame"]
        ),
        SettingsSearchItem(
            anchor: .snappingReducedEffects,
            title: "Reduce Visual Effects",
            caption: "Simplify overlay motion and transparency during window snapping.",
            keywords: ["reduced motion", "transparency", "performance", "contrast"]
        ),
        SettingsSearchItem(
            anchor: .snappingZoneMap,
            title: "Perimeter Zone Map",
            caption: "Configure screen edge and corner docking actions and partitions.",
            keywords: ["zone map", "edge snap", "corners", "partitions", "half", "quarter", "third"]
        ),
        SettingsSearchItem(
            anchor: .snappingSeamGating,
            title: "Multi-Display Seam Gating",
            caption: "Prevent accidental docking across connected screens with pointer speed gating.",
            keywords: ["seam gating", "multi-display", "threshold", "crossing speed", "screens"]
        ),

        // Hotkeys & Super Mode
        SettingsSearchItem(
            anchor: .hotkeysSuperMode,
            title: "Super Mode",
            caption: "Sequential prefix-driven keyboard shortcuts for instant window management.",
            keywords: ["shortcut", "prefix", "modal", "leader", "keyboard"]
        ),
        SettingsSearchItem(
            anchor: .hotkeysCommandTree,
            title: "Command Tree",
            caption: "View and edit key sequences assigned to window actions.",
            keywords: ["key sequences", "actions", "tree", "bindings", "commands"]
        ),
        SettingsSearchItem(
            anchor: .hotkeysGlobal,
            title: "Global Hotkeys",
            caption: "Instant system-wide keyboard shortcuts for window placement.",
            keywords: ["shortcut", "hotkey", "instant", "global", "chord"]
        ),

        // Layout Library
        SettingsSearchItem(
            anchor: .layoutsLibrary,
            title: "Layout Library",
            caption: "Define and organize multi-window placement presets and split zones.",
            keywords: ["zones", "regions", "columns", "rows", "merge", "split", "grid"]
        ),

        // Display Profiles
        SettingsSearchItem(
            anchor: .displayProfiles,
            title: "Display Profiles",
            caption: "Per-display window gaps, layout assignments, and stable display identities.",
            keywords: ["display", "monitor", "screens", "gap", "padding", "stable display id"]
        ),

        // App Rules
        SettingsSearchItem(
            anchor: .appRules,
            title: "App Rules",
            caption: "Include or exclude specific applications from window management.",
            keywords: ["bundle id", "whitelist", "blacklist", "exclude", "ignore", "apps"]
        ),

        // Import & Export
        SettingsSearchItem(
            anchor: .transferBackup,
            title: "Configuration Backup",
            caption: "Export your settings to a portable file or restore from a backup.",
            keywords: ["backup", "import", "export", "restore", "transfer", "json"]
        ),

        // About & Diagnostics
        SettingsSearchItem(
            anchor: .aboutDiagnostics,
            title: "Diagnostics & System Report",
            caption: "View version, OS details, permission state, and copy diagnostic report.",
            keywords: ["diagnostics", "version", "system", "report", "troubleshoot", "logs", "build"]
        ),
    ]

    public init(items: [SettingsSearchItem] = SettingsSearchIndex.defaultItems) {
        self.items = items
    }

    public func search(query: String) -> [SettingsSearchResultGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let matchingItems = items.filter { $0.matches(query: trimmed) }
        guard !matchingItems.isEmpty else { return [] }

        var grouped: [SettingsSection: [SettingsSearchItem]] = [:]
        for item in matchingItems {
            grouped[item.section, default: []].append(item)
        }

        // Return sorted according to SettingsSection.allCases order
        return SettingsSection.allCases.compactMap { section in
            guard let itemsForSection = grouped[section], !itemsForSection.isEmpty else { return nil }
            return SettingsSearchResultGroup(section: section, items: itemsForSection)
        }
    }
}

// MARK: - Highlight Coordinator

@MainActor
public final class SettingsHighlightCoordinator: ObservableObject {
    @Published public private(set) var activeAnchor: SettingsAnchorID?
    @Published public private(set) var isHighlighted: Bool = false

    public let fadeDuration: TimeInterval
    private var fadeTask: Task<Void, Never>?

    public init(fadeDuration: TimeInterval = 1.8) {
        self.fadeDuration = fadeDuration
    }

    deinit {
        fadeTask?.cancel()
    }

    public func land(on anchor: SettingsAnchorID, reduceMotion: Bool = false) {
        fadeTask?.cancel()
        activeAnchor = anchor

        if reduceMotion {
            isHighlighted = false
            return
        }

        isHighlighted = true
        fadeTask = Task { @MainActor [weak self, fadeDuration] in
            let nanoseconds = UInt64(fadeDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: SettingsMotion.reducedMotionDuration)) {
                self.isHighlighted = false
            }
        }
    }

    public func clear() {
        fadeTask?.cancel()
        fadeTask = nil
        activeAnchor = nil
        isHighlighted = false
    }
}

// MARK: - View Modifiers

public struct SettingsSectionAnchorModifier: ViewModifier {
    public let anchor: SettingsAnchorID
    @ObservedObject public var coordinator: SettingsHighlightCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .id(anchor)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsRadius.card, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .controlAccentColor),
                        lineWidth: 2.0
                    )
                    .opacity(coordinator.activeAnchor == anchor && coordinator.isHighlighted ? 1.0 : 0.0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: coordinator.fadeDuration),
                        value: coordinator.isHighlighted
                    )
            )
    }
}

public extension View {
    func settingsSectionAnchor(
        _ anchor: SettingsAnchorID,
        coordinator: SettingsHighlightCoordinator
    ) -> some View {
        modifier(SettingsSectionAnchorModifier(anchor: anchor, coordinator: coordinator))
    }

    func settingsSectionAnchor(_ anchor: SettingsAnchorID) -> some View {
        modifier(SettingsAnchorEnvironmentModifier(anchor: anchor))
    }
}

private struct SettingsAnchorEnvironmentModifier: ViewModifier {
    let anchor: SettingsAnchorID
    @EnvironmentObject private var coordinator: SettingsHighlightCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .id(anchor)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsRadius.card, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .controlAccentColor),
                        lineWidth: 2.0
                    )
                    .opacity(coordinator.activeAnchor == anchor && coordinator.isHighlighted ? 1.0 : 0.0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: coordinator.fadeDuration),
                        value: coordinator.isHighlighted
                    )
            )
    }
}

// MARK: - Chord Bridge (Composition Layer)

extension KeyChord {
    init(hotkeyChord: HotkeyChord, presenter: any HotkeyChordPresenting) {
        let presentation = presenter.present(hotkeyChord)
        var mods: [KeyModifier] = []
        if hotkeyChord.modifiers.contains(.command) { mods.append(.command) }
        if hotkeyChord.modifiers.contains(.option) { mods.append(.option) }
        if hotkeyChord.modifiers.contains(.control) { mods.append(.control) }
        if hotkeyChord.modifiers.contains(.shift) { mods.append(.shift) }

        self.init(modifiers: mods, key: presentation.keyLabel)
    }

    init(presentation: HotkeyChordPresentation) {
        let mods: [KeyModifier] = presentation.modifierSymbols.compactMap { sym in
            switch sym {
            case .control: return .control
            case .option: return .option
            case .shift: return .shift
            case .command: return .command
            }
        }
        self.init(modifiers: mods, key: presentation.keyLabel)
    }

    var hotkeyModifiers: HotkeyModifiers {
        var mods = HotkeyModifiers()
        for mod in modifiers {
            switch mod {
            case .command: mods.insert(.command)
            case .option: mods.insert(.option)
            case .control: mods.insert(.control)
            case .shift: mods.insert(.shift)
            }
        }
        return mods
    }
}

extension HotkeyModifiers {
    init(keyModifiers: [KeyModifier]) {
        self.init()
        for mod in keyModifiers {
            switch mod {
            case .command: insert(.command)
            case .option: insert(.option)
            case .control: insert(.control)
            case .shift: insert(.shift)
            }
        }
    }
}
