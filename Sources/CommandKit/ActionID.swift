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

import Foundation

public struct ActionID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension ActionID {
    static let maximize = Self(rawValue: "window.maximize")
    static let nativeFullScreen = Self(rawValue: "window.native-full-screen")
    static let leftHalf = Self(rawValue: "window.left-half")
    static let rightHalf = Self(rawValue: "window.right-half")
    static let topHalf = Self(rawValue: "window.top-half")
    static let bottomHalf = Self(rawValue: "window.bottom-half")
    static let topLeftQuarter = Self(rawValue: "window.top-left-quarter")
    static let topRightQuarter = Self(rawValue: "window.top-right-quarter")
    static let bottomLeftQuarter = Self(rawValue: "window.bottom-left-quarter")
    static let bottomRightQuarter = Self(rawValue: "window.bottom-right-quarter")

    static let restore = Self(rawValue: "window.restore")
    static let moveDisplayNext = Self(rawValue: "window.move-display-next")
    static let moveDisplayPrevious = Self(rawValue: "window.move-display-previous")
    static let cycleLeftEdge = Self(rawValue: "window.cycle-left-edge")
    static let leftThird = Self(rawValue: "window.left-third")
    static let leftTwoThirds = Self(rawValue: "window.left-two-thirds")

    static let openSettings = Self(rawValue: "app.open-settings")
    static let toggleGaps = Self(rawValue: "layout.toggle-gaps")
    static let selectProfile = Self(rawValue: "profile.select")
}
