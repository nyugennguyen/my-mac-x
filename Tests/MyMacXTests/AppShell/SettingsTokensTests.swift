import AppKit
import SwiftUI
import XCTest
@testable import MyMacX

final class SettingsTokensTests: XCTestCase {
    // MARK: - Spacing Scale Tests

    func testSpacingScaleConformsToBaseScaleAndSpecMeasurements() {
        XCTAssertEqual(SettingsSpacing.base, 4.0, "Base spacing must be 4 pt")
        XCTAssertEqual(SettingsSpacing.xxSmall, 2.0)
        XCTAssertEqual(SettingsSpacing.xSmall, 4.0)
        XCTAssertEqual(SettingsSpacing.small, 8.0)
        XCTAssertEqual(SettingsSpacing.medium, 12.0)
        XCTAssertEqual(SettingsSpacing.large, 16.0)
        XCTAssertEqual(SettingsSpacing.cardStackGap, 20.0, "Card stack gap must be 20 pt per spec")
        XCTAssertEqual(SettingsSpacing.maxContentWidth, 760.0, "Content column max width must be 760 pt per spec")
        XCTAssertEqual(SettingsSpacing.cardPadding, 16.0, "SettingsCard padding must be 16 pt per spec")
        XCTAssertEqual(SettingsSpacing.rowSubcontentInset, 38.0, "Row sub-content inset must be 38 pt (26 pt icon + 12 pt gap)")
        XCTAssertEqual(SettingsSpacing.rowIconSize, 26.0, "Row icon tile must be 26x26 pt per spec")
    }

    func testRadiusMeasurementsMatchSpec() {
        XCTAssertEqual(SettingsRadius.keycap, 6.0, "Keycap continuous radius must be r6")
        XCTAssertEqual(SettingsRadius.iconTile, 7.0, "Icon tile continuous radius must be r7")
        XCTAssertEqual(SettingsRadius.card, 16.0, "SettingsCard continuous radius must be r16")
    }

    // MARK: - Motion Budget Tests

    func testMotionBudgetWithinTenToTwentyTwoHundredthsOfASecond() {
        XCTAssertGreaterThanOrEqual(SettingsMotion.microInteractionDuration, 0.10, "Motion budget lower bound is 0.10s")
        XCTAssertLessThanOrEqual(SettingsMotion.microInteractionDuration, 0.22, "Motion budget upper bound is 0.22s")
        XCTAssertGreaterThanOrEqual(SettingsMotion.reducedMotionDuration, 0.08)
        XCTAssertLessThanOrEqual(SettingsMotion.reducedMotionDuration, 0.12)
    }

    func testMotionHonorsPrefersReducedMotionWithFadeFallback() {
        let normalAnimation = SettingsMotion.animation(reduceMotion: false)
        let reducedAnimation = SettingsMotion.animation(reduceMotion: true)

        XCTAssertNotNil(normalAnimation)
        XCTAssertNotNil(reducedAnimation)
    }

    // MARK: - Token Resolution Across Environment Matrix

    func testCardFillIsTranslucentInStandardMode() {
        let lightContext = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: false,
            increaseContrast: false
        )
        let lightFill = SettingsTokenResolver.cardBackgroundColor(context: lightContext)
        XCTAssertLessThan(lightFill.alphaComponent, 1.0, "Standard card background must be translucent")
        XCTAssertGreaterThan(lightFill.alphaComponent, 0.0)

        let darkContext = SettingsEnvironmentContext(
            colorScheme: .dark,
            reduceTransparency: false,
            increaseContrast: false
        )
        let darkFill = SettingsTokenResolver.cardBackgroundColor(context: darkContext)
        XCTAssertLessThan(darkFill.alphaComponent, 1.0, "Dark card background must be translucent")
        XCTAssertGreaterThan(darkFill.alphaComponent, 0.0)
    }

    func testCardFillBecomesOpaqueWhenReduceTransparencyIsActive() {
        let lightReduced = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: true,
            increaseContrast: false
        )
        let lightFill = SettingsTokenResolver.cardBackgroundColor(context: lightReduced)
        XCTAssertEqual(lightFill.alphaComponent, 1.0, accuracy: 0.001, "Reduce transparency must produce an opaque card fill (alpha = 1.0)")

        let darkReduced = SettingsEnvironmentContext(
            colorScheme: .dark,
            reduceTransparency: true,
            increaseContrast: false
        )
        let darkFill = SettingsTokenResolver.cardBackgroundColor(context: darkReduced)
        XCTAssertEqual(darkFill.alphaComponent, 1.0, accuracy: 0.001, "Reduce transparency must produce an opaque card fill (alpha = 1.0)")
    }

    func testCardFillOpacityResolvesThroughTokenLayer() {
        let standardContext = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: false,
            increaseContrast: false
        )
        XCTAssertEqual(
            SettingsTokenResolver.cardFillOpacity(context: standardContext),
            SettingsTokenResolver.standardCardFillOpacity,
            "Standard card fill opacity must resolve to standard card fill opacity token (0.35)"
        )
        XCTAssertEqual(SettingsCardLayout.fillOpacity, 0.35, accuracy: 0.001)

        let reducedContext = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: true,
            increaseContrast: false
        )
        XCTAssertEqual(
            SettingsTokenResolver.cardFillOpacity(context: reducedContext),
            1.0,
            "Reduce transparency must resolve to 1.0 (opaque)"
        )
    }

    func testStandardCardHasNoBorderWhileIncreaseContrastAddsContrastBorder() {
        let standard = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: false,
            increaseContrast: false
        )
        XCTAssertNil(
            SettingsTokenResolver.cardBorderColor(context: standard),
            "SettingsCard must have no border or shadow in standard mode per spec"
        )

        let highContrast = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: false,
            increaseContrast: true
        )
        let contrastBorder = SettingsTokenResolver.cardBorderColor(context: highContrast)
        XCTAssertNotNil(contrastBorder, "Increase contrast must add a high-contrast border")
        if let border = contrastBorder {
            XCTAssertGreaterThanOrEqual(border.alphaComponent, 0.35)
        }
    }

    func testDividerContrastIncreasesWithIncreaseContrast() {
        let standard = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: false,
            increaseContrast: false
        )
        let highContrast = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: false,
            increaseContrast: true
        )

        let standardDivider = SettingsTokenResolver.dividerColor(context: standard)
        let contrastDivider = SettingsTokenResolver.dividerColor(context: highContrast)

        XCTAssertGreaterThan(
            contrastDivider.alphaComponent,
            standardDivider.alphaComponent,
            "Increase contrast must strictly increase divider opacity/contrast"
        )
    }

    func testAccentFillAdaptsAcrossColorSchemes() {
        let lightContext = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: false,
            increaseContrast: false
        )
        let darkContext = SettingsEnvironmentContext(
            colorScheme: .dark,
            reduceTransparency: false,
            increaseContrast: false
        )

        let lightAccentFill = SettingsTokenResolver.accentFillColor(context: lightContext)
        let darkAccentFill = SettingsTokenResolver.accentFillColor(context: darkContext)

        XCTAssertEqual(lightAccentFill.alphaComponent, 0.12, accuracy: 0.01, "Light accent fill is ~12%")
        XCTAssertEqual(darkAccentFill.alphaComponent, 0.18, accuracy: 0.01, "Dark accent fill is ~18%")
    }

    func testStatusColorsUseSemanticSystemPalette() {
        let context = SettingsEnvironmentContext(
            colorScheme: .light,
            reduceTransparency: false,
            increaseContrast: false
        )

        let okColor = SettingsTokenResolver.statusColor(.ok, context: context)
        let warnColor = SettingsTokenResolver.statusColor(.warning, context: context)
        let errColor = SettingsTokenResolver.statusColor(.error, context: context)

        XCTAssertNotNil(okColor)
        XCTAssertNotNil(warnColor)
        XCTAssertNotNil(errColor)
    }
}
