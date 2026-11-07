import AppKit
import SwiftUI

// MARK: - Spacing Scale

public enum SettingsSpacing {
    public static let base: CGFloat = 4.0
    public static let xxSmall: CGFloat = 2.0
    public static let xSmall: CGFloat = 4.0
    public static let small: CGFloat = 8.0
    public static let medium: CGFloat = 12.0
    public static let large: CGFloat = 16.0
    public static let cardStackGap: CGFloat = 20.0
    public static let sectionGap: CGFloat = 28.0
    public static let panePadding: CGFloat = 36.0
    public static let maxContentWidth: CGFloat = 760.0
    public static let cardPadding: CGFloat = 16.0
    public static let rowSubcontentInset: CGFloat = 38.0
    public static let rowIconSize: CGFloat = 26.0
    public static let rowGap: CGFloat = 12.0
}

// MARK: - Corner Radii

public enum SettingsRadius {
    public static let keycap: CGFloat = 6.0
    public static let iconTile: CGFloat = 7.0
    public static let control: CGFloat = 8.0
    public static let card: CGFloat = 16.0
}

// MARK: - Motion Budget

public enum SettingsMotion {
    public static let minDuration: Double = 0.10
    public static let maxDuration: Double = 0.22
    public static let microInteractionDuration: Double = 0.15
    public static let reducedMotionDuration: Double = 0.10

    public static func animation(reduceMotion: Bool) -> Animation? {
        if reduceMotion {
            return .easeInOut(duration: reducedMotionDuration)
        }
        return .easeInOut(duration: microInteractionDuration)
    }
}

// MARK: - Typography

public enum SettingsTypography {
    public static let windowTitle = Font.system(size: 20, weight: .semibold)
    public static let paneTitle = Font.system(size: 28, weight: .bold)
    public static let sectionTitle = Font.system(size: 13, weight: .semibold)
    public static let cardHeader = Font.system(size: 11, weight: .semibold)
    public static let rowTitle = Font.system(size: 13, weight: .regular)
    public static let rowCaption = Font.system(size: 11, weight: .regular)
    public static let body = Font.system(size: 13, weight: .regular)
    public static let supporting = Font.system(size: 11, weight: .regular)
    public static let keycap = Font.system(size: 12, weight: .medium, design: .monospaced)
    public static let code = Font.system(size: 11, weight: .regular, design: .monospaced)
    public static let badge = Font.system(size: 8.5, weight: .bold)
    public static let stepper = Font.system(size: 12, weight: .regular, design: .monospaced)
}

// MARK: - Status Kind

public enum SettingsStatusKind: Equatable, Sendable {
    case ok
    case warning
    case error
}

// MARK: - Environment Context

public struct SettingsEnvironmentContext: Equatable, Sendable {
    public let colorScheme: ColorScheme
    public let reduceTransparency: Bool
    public let increaseContrast: Bool

    public init(
        colorScheme: ColorScheme = .light,
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false
    ) {
        self.colorScheme = colorScheme
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

// MARK: - Token Resolver

public enum SettingsTokenResolver {
    public static let standardCardFillOpacity: CGFloat = 0.35

    public static func cardFillOpacity(context: SettingsEnvironmentContext) -> CGFloat {
        if context.reduceTransparency {
            return 1.0
        }
        return standardCardFillOpacity
    }

    public static func cardBackgroundColor(context: SettingsEnvironmentContext) -> NSColor {
        if context.reduceTransparency {
            if context.colorScheme == .dark {
                return NSColor(deviceWhite: 0.17, alpha: cardFillOpacity(context: context))
            } else {
                return NSColor(deviceWhite: 1.0, alpha: cardFillOpacity(context: context))
            }
        }

        // Quaternary-like translucent fill (~35% of quaternary or ~4.5% black / 6.5% white)
        if context.colorScheme == .dark {
            return NSColor(deviceWhite: 1.0, alpha: 0.065)
        } else {
            return NSColor(deviceWhite: 0.0, alpha: 0.045)
        }
    }

    public static func cardBorderColor(context: SettingsEnvironmentContext) -> NSColor? {
        if context.increaseContrast {
            return NSColor.separatorColor.withAlphaComponent(0.40)
        }
        return nil
    }

    public static func dividerColor(context: SettingsEnvironmentContext) -> NSColor {
        if context.increaseContrast {
            return NSColor.separatorColor.withAlphaComponent(0.45)
        }
        if context.colorScheme == .dark {
            return NSColor.separatorColor.withAlphaComponent(0.12)
        } else {
            return NSColor.separatorColor.withAlphaComponent(0.11)
        }
    }

    public static func keycapBackgroundColor(context: SettingsEnvironmentContext) -> NSColor {
        if context.reduceTransparency {
            return NSColor.controlBackgroundColor
        }
        if context.colorScheme == .dark {
            return NSColor(deviceWhite: 1.0, alpha: 0.09)
        } else {
            return NSColor(deviceWhite: 0.0, alpha: 0.055)
        }
    }

    public static func keycapBorderColor(context: SettingsEnvironmentContext) -> NSColor {
        if context.increaseContrast {
            return NSColor.separatorColor.withAlphaComponent(0.50)
        }
        if context.colorScheme == .dark {
            return NSColor.separatorColor.withAlphaComponent(0.22)
        } else {
            return NSColor.separatorColor.withAlphaComponent(0.18)
        }
    }

    public static func accentFillColor(context: SettingsEnvironmentContext) -> NSColor {
        let alpha: CGFloat = (context.colorScheme == .dark) ? 0.18 : 0.12
        return NSColor.controlAccentColor.withAlphaComponent(alpha)
    }

    public static func statusColor(
        _ kind: SettingsStatusKind,
        context: SettingsEnvironmentContext
    ) -> NSColor {
        switch kind {
        case .ok:
            return NSColor.systemGreen
        case .warning:
            return NSColor.systemOrange
        case .error:
            return NSColor.systemRed
        }
    }

    // MARK: - SwiftUI Color Helpers

    public static func cardBackground(context: SettingsEnvironmentContext) -> Color {
        Color(nsColor: cardBackgroundColor(context: context))
    }

    public static func cardBorder(context: SettingsEnvironmentContext) -> Color? {
        guard let nsColor = cardBorderColor(context: context) else { return nil }
        return Color(nsColor: nsColor)
    }

    public static func divider(context: SettingsEnvironmentContext) -> Color {
        Color(nsColor: dividerColor(context: context))
    }

    public static func keycapBackground(context: SettingsEnvironmentContext) -> Color {
        Color(nsColor: keycapBackgroundColor(context: context))
    }

    public static func keycapBorder(context: SettingsEnvironmentContext) -> Color {
        Color(nsColor: keycapBorderColor(context: context))
    }

    public static func accentFill(context: SettingsEnvironmentContext) -> Color {
        Color(nsColor: accentFillColor(context: context))
    }

    public static func status(_ kind: SettingsStatusKind, context: SettingsEnvironmentContext) -> Color {
        Color(nsColor: statusColor(kind, context: context))
    }
}
