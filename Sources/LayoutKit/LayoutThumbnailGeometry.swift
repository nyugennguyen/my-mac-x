import CoreGraphics

/// Pure geometry calculator for rendering normalized Layout Regions inside a mini-screen thumbnail canvas.
///
/// Insets interior region edges by `gap / 2` while keeping outer canvas edges flush,
/// ensuring crisp split thumbnails matching the Notch Chooser and prototype glyphs.
public struct LayoutRegionThumbnailGeometry: Equatable, Sendable {
    public static func pixelRect(
        for normalizedFrame: CGRect,
        in canvasRect: CGRect,
        gap: CGFloat = 1.5
    ) -> CGRect {
        guard canvasRect.width > 0, canvasRect.height > 0 else {
            return .zero
        }

        let isAtLeft = normalizedFrame.minX <= 0.001
        let isAtRight = normalizedFrame.maxX >= 0.999
        let isAtBottom = normalizedFrame.minY <= 0.001
        let isAtTop = normalizedFrame.maxY >= 0.999

        let leadingInset = isAtLeft ? 0.0 : gap / 2.0
        let trailingInset = isAtRight ? 0.0 : gap / 2.0
        let bottomInset = isAtBottom ? 0.0 : gap / 2.0
        let topInset = isAtTop ? 0.0 : gap / 2.0

        let x = canvasRect.minX + normalizedFrame.minX * canvasRect.width + leadingInset
        let y = canvasRect.minY + normalizedFrame.minY * canvasRect.height + bottomInset
        let width = normalizedFrame.width * canvasRect.width - leadingInset - trailingInset
        let height = normalizedFrame.height * canvasRect.height - bottomInset - topInset

        return CGRect(
            x: x,
            y: y,
            width: max(0, width),
            height: max(0, height)
        )
    }

    public static func pixelRects(
        for regions: [CGRect],
        in canvasRect: CGRect,
        gap: CGFloat = 1.5
    ) -> [CGRect] {
        regions.map { pixelRect(for: $0, in: canvasRect, gap: gap) }
    }
}
