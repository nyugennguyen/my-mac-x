import CoreGraphics
@testable import MyMacX

/// Literal, app-independent Display topology fixtures.
///
/// The two positive fixtures are copied from the approved current-machine
/// public-API evidence. The negative/invalid fixtures exercise topology
/// handling without consulting WindowServer or NSScreen.
enum GeometryFixtures {
    static let hkcExternal = DisplayGeometryCandidate(
        displayID: DisplayID(rawValue: 2),
        isPrimary: false,
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050),
        backingScaleFactor: 1,
        safeArea: DisplaySafeArea(
            insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
    )

    static let builtInRetina = DisplayGeometryCandidate(
        displayID: DisplayID(rawValue: 1),
        isPrimary: true,
        frame: CGRect(x: 1920, y: 124, width: 1470, height: 956),
        visibleFrame: CGRect(x: 1920, y: 124, width: 1470, height: 924),
        backingScaleFactor: 2,
        safeArea: DisplaySafeArea(
            insets: DisplayEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 1920, y: 1048, width: 646, height: 32),
            auxiliaryTopRightArea: CGRect(x: 2745, y: 1048, width: 645, height: 32)
        )
    )

    static let negativeX = DisplayGeometryCandidate(
        displayID: DisplayID(rawValue: 41),
        isPrimary: true,
        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 25, width: 1920, height: 1055),
        backingScaleFactor: 1.5,
        safeArea: noAuxiliarySafeArea
    )

    static let negativeY = DisplayGeometryCandidate(
        displayID: DisplayID(rawValue: 42),
        isPrimary: true,
        frame: CGRect(x: 300, y: -1080, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 300, y: -1080, width: 1920, height: 1055),
        backingScaleFactor: 2,
        safeArea: noAuxiliarySafeArea
    )

    static let negativeYWithUnsafeAuxiliaryAreas = DisplayGeometryCandidate(
        displayID: DisplayID(rawValue: 105),
        isPrimary: true,
        frame: CGRect(x: 300, y: -1080, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 300, y: -1080, width: 1920, height: 1055),
        backingScaleFactor: 2,
        safeArea: DisplaySafeArea(
            insets: DisplayEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 300, y: -32, width: 1100, height: 32),
            auxiliaryTopRightArea: CGRect(x: 1300, y: -32, width: 920, height: 32)
        )
    )

    static let invalidFrame = candidate(
        id: 52,
        frame: CGRect(x: 0, y: 0, width: 0, height: 900)
    )

    static let invalidVisibleFrame = candidate(
        id: 52,
        visibleFrame: CGRect(x: -1, y: 25, width: 1440, height: 875)
    )

    static let invalidScale = candidate(id: 52, backingScaleFactor: 0)

    static let noAuxiliarySafeArea = DisplaySafeArea(
        insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
    )

    static func candidate(
        id: UInt32,
        frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect = CGRect(x: 0, y: 25, width: 1440, height: 875),
        backingScaleFactor: CGFloat = 2,
        safeArea: DisplaySafeArea = noAuxiliarySafeArea,
        isPrimary: Bool = true
    ) -> DisplayGeometryCandidate {
        DisplayGeometryCandidate(
            displayID: DisplayID(rawValue: id),
            isPrimary: isPrimary,
            frame: frame,
            visibleFrame: visibleFrame,
            backingScaleFactor: backingScaleFactor,
            safeArea: safeArea
        )
    }
}
