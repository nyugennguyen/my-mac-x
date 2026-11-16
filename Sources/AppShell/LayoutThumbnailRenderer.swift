// MyMacX
// Copyright (C) 2026 NyugenNguyen
//
// This program is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the LICENSE file for details.

import AppKit
import SwiftUI

@MainActor
extension WindowsSnapGlyphRenderer {
    /// Renders a mini-screen thumbnail glyph for an arbitrary collection of normalized Layout Regions,
    /// sharing the visual design, bezel, stroke, and contrast treatment of the Notch Chooser snap glyphs.
    static func layoutThumbnail(
        for regions: [CGRect],
        size: CGSize = CGSize(width: 80, height: 52),
        isSelected: Bool = false,
        contrast: OverlayContrastTreatment = .standard
    ) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)

            // Outer screen bezel
            let screenPath = NSBezierPath(roundedRect: bounds, xRadius: 4.0, yRadius: 4.0)
            let screenFill = NSColor.windowBackgroundColor.withAlphaComponent(0.5)
            screenFill.setFill()
            screenPath.fill()

            let screenBorderColor: NSColor = contrast == .increased
                ? .labelColor
                : (isSelected
                    ? NSColor.controlAccentColor.withAlphaComponent(0.9)
                    : NSColor.separatorColor.withAlphaComponent(0.5))
            screenBorderColor.setStroke()
            screenPath.lineWidth = contrast == .increased ? 1.5 : (isSelected ? 1.5 : 0.8)
            screenPath.stroke()

            // Inner area for regions
            let innerRect = bounds.insetBy(dx: 3.0, dy: 3.0)
            let gap: CGFloat = 1.5
            let zoneRadius: CGFloat = 2.0

            let activeColor: NSColor = contrast == .increased
                ? (isSelected ? .labelColor : .secondaryLabelColor)
                : (isSelected ? .controlAccentColor : .secondaryLabelColor.withAlphaComponent(0.55))
            let zoneStrokeColor: NSColor = contrast == .increased
                ? .separatorColor
                : (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.3) : NSColor.clear)

            let pixelRects = LayoutRegionThumbnailGeometry.pixelRects(
                for: regions,
                in: innerRect,
                gap: gap
            )

            for zoneRect in pixelRects {
                guard zoneRect.width > 0, zoneRect.height > 0 else { continue }
                let path = NSBezierPath(roundedRect: zoneRect, xRadius: zoneRadius, yRadius: zoneRadius)
                activeColor.setFill()
                path.fill()
                if contrast == .increased || isSelected {
                    zoneStrokeColor.setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                }
            }

            return true
        }
    }
}

/// SwiftUI thumbnail view displaying a normalized Layout glyph.
public struct LayoutThumbnailView: View {
    public let regions: [CGRect]
    public let isSelected: Bool
    public let size: CGSize

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        regions: [CGRect],
        isSelected: Bool = false,
        size: CGSize = CGSize(width: 80, height: 52)
    ) {
        self.regions = regions
        self.isSelected = isSelected
        self.size = size
    }

    public var body: some View {
        let contrast: OverlayContrastTreatment = (colorSchemeContrast == .increased) ? .increased : .standard
        let image = WindowsSnapGlyphRenderer.layoutThumbnail(
            for: regions,
            size: size,
            isSelected: isSelected,
            contrast: contrast
        )
        Image(nsImage: image)
            .renderingMode(.original)
            .frame(width: size.width, height: size.height)
    }
}
