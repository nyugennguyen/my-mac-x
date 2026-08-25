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
}
