import AppKit
import SwiftUI

// MARK: - Key Chord & Modifiers

public enum KeyModifier: String, CaseIterable, Equatable, Hashable, Sendable, Comparable {
    case control = "⌃"
    case option = "⌥"
    case shift = "⇧"
    case command = "⌘"

    public static func < (lhs: KeyModifier, rhs: KeyModifier) -> Bool {
        let order: [KeyModifier] = [.control, .option, .shift, .command]
        guard let li = order.firstIndex(of: lhs), let ri = order.firstIndex(of: rhs) else { return false }
        return li < ri
    }
}

public struct KeyChord: Equatable, Hashable, Sendable {
    public let modifiers: [KeyModifier]
    public let key: String

    public init(modifiers: [KeyModifier] = [], key: String) {
        self.modifiers = modifiers.sorted()
        self.key = key
    }

    public var displayKeys: [String] {
        modifiers.map(\.rawValue) + [key]
    }

    public var displayString: String {
        displayKeys.joined()
    }
}

// MARK: - Shortcut Recorder State & Model

public enum ShortcutRecorderState: Equatable, Sendable {
    case idle(chord: KeyChord?)
    case listening
    case conflict(chord: KeyChord, reason: String)
}

public struct ShortcutRecorderModel: Equatable, Sendable {
    public private(set) var state: ShortcutRecorderState
    private var lastRecordedChord: KeyChord?
    public let defaultChord: KeyChord?
    public var conflictValidator: (@Sendable (KeyChord) -> String?)?

    public static func == (lhs: ShortcutRecorderModel, rhs: ShortcutRecorderModel) -> Bool {
        lhs.state == rhs.state && lhs.defaultChord == rhs.defaultChord
    }

    public init(
        currentChord: KeyChord? = nil,
        defaultChord: KeyChord? = nil,
        conflictValidator: (@Sendable (KeyChord) -> String?)? = nil
    ) {
        self.state = .idle(chord: currentChord)
        self.lastRecordedChord = currentChord
        self.defaultChord = defaultChord
        self.conflictValidator = conflictValidator
    }

    public var currentChord: KeyChord? {
        switch state {
        case let .idle(chord):
            return chord
        case let .conflict(chord, _):
            return chord
        case .listening:
            return nil
        }
    }

    public var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    public var conflictMessage: String? {
        if case let .conflict(_, reason) = state { return reason }
        return nil
    }

    public var hasConflict: Bool {
        conflictMessage != nil
    }

    public var canClear: Bool {
        currentChord != nil && !isListening
    }

    public var canReset: Bool {
        guard let defaultChord else { return false }
        return currentChord != defaultChord && !isListening
    }

    public mutating func startRecording() {
        if let chord = currentChord {
            lastRecordedChord = chord
        }
        state = .listening
    }

    public mutating func cancelRecording() {
        state = .idle(chord: lastRecordedChord)
    }

    public mutating func record(chord: KeyChord) {
        lastRecordedChord = chord
        if let validator = conflictValidator, let reason = validator(chord) {
            state = .conflict(chord: chord, reason: reason)
        } else {
            state = .idle(chord: chord)
        }
    }

    public mutating func clear() {
        lastRecordedChord = nil
        state = .idle(chord: nil)
    }

    public mutating func reset() {
        lastRecordedChord = defaultChord
        state = .idle(chord: defaultChord)
    }
}

public enum ShortcutRecorderLayout {
    public static let buttonWidth: CGFloat = 108.0
    public static let buttonHeight: CGFloat = 26.0
    public static let font = SettingsTypography.keycap
}

// MARK: - Keycap Layout & Model

public enum KeycapLayout {
    public static let minWidth: CGFloat = 20.0
    public static let height: CGFloat = 22.0
    public static let radius: CGFloat = 6.0
    public static let horizontalPadding: CGFloat = 6.0
}

public enum KeycapChainSegment: Equatable, Sendable {
    case key(String)
    case keyGroup([String])
    case arrow
}

public struct KeycapChainModel: Equatable, Sendable {
    public let segments: [KeycapChainSegment]
    public let hasArrowSeparators: Bool
    public let accessibleText: String

    public init(keys: [String]) {
        self.segments = keys.map { .key($0) }
        self.hasArrowSeparators = false
        self.accessibleText = KeycapChainModel.accessibleDescription(forKeys: keys, joiner: ", ")
    }

    public init(steps: [[String]]) {
        var segs: [KeycapChainSegment] = []
        var stepDescriptions: [String] = []
        for (index, step) in steps.enumerated() {
            if index > 0 {
                segs.append(.arrow)
            }
            segs.append(.keyGroup(step))
            stepDescriptions.append(step.map { KeycapChainModel.accessibleName(for: $0) }.joined(separator: " "))
        }
        self.segments = segs
        self.hasArrowSeparators = steps.count > 1
        self.accessibleText = stepDescriptions.joined(separator: " then ")
    }

    private static func accessibleName(for symbol: String) -> String {
        switch symbol {
        case "⌃": return "Control"
        case "⌥": return "Option"
        case "⇧": return "Shift"
        case "⌘": return "Command"
        case "←": return "Left Arrow"
        case "→": return "Right Arrow"
        case "↑": return "Up Arrow"
        case "↓": return "Down Arrow"
        case "⌫": return "Backspace"
        case "⌦": return "Forward Delete"
        case "↩": return "Return"
        case "⇥": return "Tab"
        case " ": return "Space"
        default: return symbol
        }
    }

    private static func accessibleDescription(forKeys keys: [String], joiner: String) -> String {
        keys.map { accessibleName(for: $0) }.joined(separator: joiner)
    }
}

// MARK: - Badge & Status Models

public struct CapsuleBadgeModel: Equatable, Sendable {
    public let text: String
    public let tint: NSColor
    public let fontSize: CGFloat
    public let isBold: Bool

    public init(
        text: String,
        tint: NSColor = .controlAccentColor,
        fontSize: CGFloat = 8.5,
        isBold: Bool = true
    ) {
        self.text = text.uppercased()
        self.tint = tint
        self.fontSize = fontSize
        self.isBold = isBold
    }

    public static let beta = CapsuleBadgeModel(text: "BETA", tint: .controlAccentColor)
    public static let experimental = CapsuleBadgeModel(text: "EXPERIMENTAL", tint: .systemOrange)
}

public enum StatusDotLayout {
    public static let diameter: CGFloat = 6.0
}

public enum StatusDotState: Equatable, Sendable {
    case active
    case inactive
    case warning
    case error
}

public struct StatusDotModel: Equatable, Sendable {
    public let state: StatusDotState
    public let color: NSColor
    public let accessibilityLabel: String

    public init(state: StatusDotState) {
        self.state = state
        switch state {
        case .active:
            self.color = .systemGreen
            self.accessibilityLabel = "Active"
        case .inactive:
            self.color = .tertiaryLabelColor
            self.accessibilityLabel = "Inactive"
        case .warning:
            self.color = .systemOrange
            self.accessibilityLabel = "Warning"
        case .error:
            self.color = .systemRed
            self.accessibilityLabel = "Error"
        }
    }
}

// MARK: - Card, Row & IconTile Layout

public enum SettingsCardLayout {
    public static let padding: CGFloat = 16.0
    public static let cornerRadius: CGFloat = 16.0
    public static let stackGap: CGFloat = 20.0
    public static let maxContentWidth: CGFloat = 760.0
    public static let fillOpacity: CGFloat = 0.35
}

public enum IconTileLayout {
    public static let size: CGFloat = 26.0
    public static let cornerRadius: CGFloat = 7.0
    public static let fillOpacity: CGFloat = 0.12
    public static let symbolPointSize: CGFloat = 12.0
}

public enum SettingsRowLayout {
    public static let subcontentInset: CGFloat = 38.0
    public static let dividerHeight: CGFloat = 0.5
    public static let titleFontSize: CGFloat = 13.0
    public static let captionFontSize: CGFloat = 11.0
    public static let captionsWrapNeverTruncate: Bool = true
}

// MARK: - SwiftUI Views

/// 26x26 accent-tinted icon tile (r7 continuous radius, 12% fill, 12 pt semibold SF Symbol)
public struct IconTile: View {
    public let systemName: String
    public let tint: Color

    public init(systemName: String, tint: Color = Color(nsColor: .controlAccentColor)) {
        self.systemName = systemName
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: IconTileLayout.cornerRadius, style: .continuous)
                .fill(tint.opacity(IconTileLayout.fillOpacity))
            Image(systemName: systemName)
                .font(.system(size: IconTileLayout.symbolPointSize, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: IconTileLayout.size, height: IconTileLayout.size)
    }
}

/// 5-6 pt status indicator dot
public struct StatusDot: View {
    public let model: StatusDotModel

    public init(state: StatusDotState = .active) {
        self.model = StatusDotModel(state: state)
    }

    public init(model: StatusDotModel) {
        self.model = model
    }

    public var body: some View {
        Circle()
            .fill(Color(nsColor: model.color))
            .frame(width: StatusDotLayout.diameter, height: StatusDotLayout.diameter)
            .accessibilityLabel(model.accessibilityLabel)
    }
}

/// Compact badge (BETA / EXPERIMENTAL, 8.5 pt bold uppercase)
public struct CapsuleBadge: View {
    public let model: CapsuleBadgeModel

    public init(model: CapsuleBadgeModel = .beta) {
        self.model = model
    }

    public init(_ text: String, tint: NSColor = .controlAccentColor) {
        self.model = CapsuleBadgeModel(text: text, tint: tint)
    }

    public var body: some View {
        Text(model.text)
            .font(.system(size: model.fontSize, weight: model.isBold ? .bold : .medium))
            .tracking(0.34) // ~0.04em tracking
            .foregroundStyle(Color(nsColor: model.tint))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: model.tint).opacity(0.12))
            )
    }
}

/// Keycap chip (min 20x22, r6, subtle fill + hairline)
public struct KeycapChip: View {
    public let label: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(label: String) {
        self.label = label
    }

    public var body: some View {
        let increaseContrast = colorSchemeContrast == .increased
        let context = SettingsEnvironmentContext(
            colorScheme: colorScheme,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )
        Text(label)
            .font(SettingsTypography.keycap)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, KeycapLayout.horizontalPadding)
            .frame(minWidth: KeycapLayout.minWidth, minHeight: KeycapLayout.height)
            .background(
                RoundedRectangle(cornerRadius: KeycapLayout.radius, style: .continuous)
                    .fill(SettingsTokenResolver.keycapBackground(context: context))
            )
            .overlay(
                RoundedRectangle(cornerRadius: KeycapLayout.radius, style: .continuous)
                    .strokeBorder(
                        SettingsTokenResolver.keycapBorder(context: context),
                        lineWidth: 0.5
                    )
            )
    }
}

/// Chain of keycaps connected with arrows
public struct KeycapSequenceView: View {
    public let model: KeycapChainModel

    public init(model: KeycapChainModel) {
        self.model = model
    }

    public init(keys: [String]) {
        self.model = KeycapChainModel(keys: keys)
    }

    public init(steps: [[String]]) {
        self.model = KeycapChainModel(steps: steps)
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(model.segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .key(key):
                    KeycapChip(label: key)
                case let .keyGroup(keys):
                    HStack(spacing: 3) {
                        ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                            KeycapChip(label: k)
                        }
                    }
                case .arrow:
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 1)
                }
            }
        }
        .accessibilityLabel(model.accessibleText)
    }
}

/// ShortcutRecorderButton: fixed width ~108 pt, single font in all states (no width jitter),
/// "Press keys..." listening state, clear (x) + text Reset column-aligned, inline orange caption for conflicts.
public struct ShortcutRecorderButton: View {
    @Binding public var model: ShortcutRecorderModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: Binding<ShortcutRecorderModel>) {
        self._model = model
    }

    public var body: some View {
        let increaseContrast = colorSchemeContrast == .increased
        let context = SettingsEnvironmentContext(
            colorScheme: colorScheme,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )

        HStack(spacing: 6) {
            // Main fixed-width recorder button
            Button {
                if model.isListening {
                    model.cancelRecording()
                } else {
                    model.startRecording()
                }
            } label: {
                ZStack {
                    if model.isListening {
                        Text("Press keys…")
                            .font(ShortcutRecorderLayout.font)
                            .foregroundStyle(Color(nsColor: .controlAccentColor))
                    } else if let chord = model.currentChord {
                        HStack(spacing: 2) {
                            ForEach(Array(chord.displayKeys.enumerated()), id: \.offset) { _, key in
                                KeycapChip(label: key)
                            }
                        }
                    } else {
                        Text("Record Shortcut")
                            .font(ShortcutRecorderLayout.font)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: ShortcutRecorderLayout.buttonWidth, height: ShortcutRecorderLayout.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            model.isListening
                                ? SettingsTokenResolver.accentFill(context: context)
                                : SettingsTokenResolver.keycapBackground(context: context)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            borderStrokeColor(context: context),
                            lineWidth: model.isListening || model.hasConflict ? 1.0 : 0.5
                        )
                )
            }
            .buttonStyle(.plain)
            .animation(SettingsMotion.animation(reduceMotion: reduceMotion), value: model.isListening)

            // Column-aligned clear (x) button
            Button {
                model.clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .opacity(model.canClear ? 1.0 : 0.0)
            }
            .buttonStyle(.plain)
            .disabled(!model.canClear)
            .accessibilityLabel("Clear shortcut")

            // Column-aligned reset button
            Button("Reset") {
                model.reset()
            }
            .font(SettingsTypography.rowCaption)
            .foregroundStyle(Color(nsColor: .controlAccentColor))
            .opacity(model.canReset ? 1.0 : 0.0)
            .buttonStyle(.plain)
            .disabled(!model.canReset)
        }
    }

    private func borderStrokeColor(context: SettingsEnvironmentContext) -> Color {
        if model.hasConflict {
            return Color(nsColor: .systemOrange)
        }
        if model.isListening {
            return Color(nsColor: .controlAccentColor)
        }
        return SettingsTokenResolver.keycapBorder(context: context)
    }
}

/// SettingsRow: 26x26 accent-tinted icon tile (r7, 12% fill, 12 pt semibold SF Symbol)
/// + title + one-line caption (captions wrap, never truncate) + trailing control; 38 pt text inset for sub-content; thin dividers.
public struct SettingsRow<Trailing: View, Subcontent: View>: View {
    public let icon: IconTile?
    public let title: String
    public let caption: String?
    public let conflictMessage: String?
    @ViewBuilder public let trailing: () -> Trailing
    @ViewBuilder public let subcontent: () -> Subcontent

    public init(
        icon: IconTile? = nil,
        title: String,
        caption: String? = nil,
        conflictMessage: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder subcontent: @escaping () -> Subcontent = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.caption = caption
        self.conflictMessage = conflictMessage
        self.trailing = trailing
        self.subcontent = subcontent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: SettingsSpacing.rowGap) {
                if let icon {
                    icon
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SettingsTypography.rowTitle)
                        .foregroundStyle(.primary)

                    if let caption {
                        Text(caption)
                            .font(SettingsTypography.rowCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let conflictMessage {
                        Text(conflictMessage)
                            .font(SettingsTypography.rowCaption)
                            .foregroundStyle(Color(nsColor: .systemOrange))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                trailing()
            }
            .frame(minHeight: 36)

            if !(Subcontent.self == EmptyView.self) {
                subcontent()
                    .padding(.leading, SettingsRowLayout.subcontentInset)
            }
        }
        .padding(.vertical, 4)
    }
}

// Convenience initializer without subcontent
public extension SettingsRow where Subcontent == EmptyView {
    init(
        icon: IconTile? = nil,
        title: String,
        caption: String? = nil,
        conflictMessage: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            icon: icon,
            title: title,
            caption: caption,
            conflictMessage: conflictMessage,
            trailing: trailing,
            subcontent: { EmptyView() }
        )
    }
}

/// SettingsCard: 16 pt padding, 16 pt continuous radius, quaternary ~35% fill,
/// no border/shadow, 20 pt card stack gap, max 760 pt content column.
public struct SettingsCard<Content: View>: View {
    public let label: String?
    @ViewBuilder public let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(label: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    public var body: some View {
        let increaseContrast = colorSchemeContrast == .increased
        let context = SettingsEnvironmentContext(
            colorScheme: colorScheme,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )

        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label.uppercased())
                    .font(SettingsTypography.cardHeader)
                    .foregroundStyle(.secondary)
                    .tracking(0.22)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(SettingsCardLayout.padding)
            .background(
                RoundedRectangle(cornerRadius: SettingsCardLayout.cornerRadius, style: .continuous)
                    .fill(SettingsTokenResolver.cardBackground(context: context))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsCardLayout.cornerRadius, style: .continuous)
                    .strokeBorder(
                        SettingsTokenResolver.cardBorder(context: context) ?? Color.clear,
                        lineWidth: increaseContrast ? 1.0 : 0.0
                    )
            )
        }
        .frame(maxWidth: SettingsCardLayout.maxContentWidth)
        .padding(.bottom, SettingsCardLayout.stackGap)
    }
}

/// Thin divider (0.5 pt) styled for settings rows
public struct SettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init() {}

    public var body: some View {
        let increaseContrast = colorSchemeContrast == .increased
        let context = SettingsEnvironmentContext(
            colorScheme: colorScheme,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        )
        Rectangle()
            .fill(SettingsTokenResolver.divider(context: context))
            .frame(height: SettingsRowLayout.dividerHeight)
    }
}
