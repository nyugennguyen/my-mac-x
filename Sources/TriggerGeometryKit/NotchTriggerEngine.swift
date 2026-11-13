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

import CoreGraphics

/// The Notch Trigger associated with the physical Display currently under the pointer.
///
/// The trigger is copied from one validated ScreenKit topology capture. Its Display identity
/// is scoped to that capture and must not be retained across screen-parameter changes.
struct NotchTriggerResolution: Equatable, Sendable {
    let displayID: DisplayID
    let trigger: NotchTrigger
    let pointerIsInsideTrigger: Bool
}

/// Resolves pointer locations against validated, global AppKit logical Display geometry.
///
/// This pure-data Module neither reads screen state nor converts to pixels. ScreenKit already
/// validates Notch/top-center fallback geometry, and all Displays remain in one logical-point
/// coordinate space regardless of backing scale.
struct NotchTriggerEngine: Sendable {
    init() {}

    func resolve(
        pointerLocation: CGPoint,
        topology: DisplayTopologySnapshot
    ) -> NotchTriggerResolution? {
        guard pointerLocation.x.isFinite,
              pointerLocation.y.isFinite
        else {
            return nil
        }

        // CGRect is half-open at maxX/maxY. Prefer that rule at shared Display edges, then
        // admit an exact outer edge so the physical top edge remains triggerable.
        let display = topology.displays.first(where: {
            $0.frame.contains(pointerLocation)
        }) ?? topology.displays.first(where: {
            Self.containsIncludingMaximumEdges($0.frame, pointerLocation)
        })
        guard let display else { return nil }

        return NotchTriggerResolution(
            displayID: display.id,
            trigger: display.notchTrigger,
            pointerIsInsideTrigger: Self.containsIncludingMaximumEdges(
                display.notchTrigger.region,
                pointerLocation
            )
        )
    }

    private static func containsIncludingMaximumEdges(
        _ rectangle: CGRect,
        _ point: CGPoint
    ) -> Bool {
        point.x >= rectangle.minX
            && point.x <= rectangle.maxX
            && point.y >= rectangle.minY
            && point.y <= rectangle.maxY
    }
}
