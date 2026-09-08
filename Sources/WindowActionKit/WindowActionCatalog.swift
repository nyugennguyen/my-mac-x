import CoreGraphics

struct WindowActionCatalog: Sendable {
    enum Operation: Sendable {
        case layout(layoutID: String, region: LayoutRegion)
        case moveDisplay(DisplayMoveDirection)
        case restore
        case cycle(CycleGroup)
        case nativeFullScreen
    }

    struct Definition: Sendable {
        let id: ActionID
        let operation: Operation
        let isEnabled: Bool
        let supportsPreview: Bool

        init(
            id: ActionID,
            operation: Operation,
            isEnabled: Bool = true,
            supportsPreview: Bool = true
        ) {
            self.id = id
            self.operation = operation
            self.isEnabled = isEnabled
            self.supportsPreview = supportsPreview
        }
    }

    static let builtIn: Self = {
        var definitions: [Definition] = Layout.builtIn.regions.compactMap { region in
            guard let action = placementAction(for: region.id) else { return nil }
            return Definition(id: action, operation: .layout(layoutID: Layout.builtIn.id, region: region))
        }

        let leftThird = try! LayoutRegion(
            id: LayoutRegionID(rawValue: "left-third"),
            normalizedFrame: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
        )
        let leftTwoThirds = try! LayoutRegion(
            id: LayoutRegionID(rawValue: "left-two-thirds"),
            normalizedFrame: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)
        )
        let leftThirdID = ActionID(rawValue: "window.left-third")
        let leftTwoThirdsID = ActionID(rawValue: "window.left-two-thirds")
        definitions.append(Definition(id: leftThirdID, operation: .layout(layoutID: Layout.builtIn.id, region: leftThird)))
        definitions.append(Definition(id: leftTwoThirdsID, operation: .layout(layoutID: Layout.builtIn.id, region: leftTwoThirds)))
        definitions.append(
            Definition(
                id: .moveDisplayNext,
                operation: .moveDisplay(.right)
            )
        )
        definitions.append(
            Definition(
                id: .moveDisplayPrevious,
                operation: .moveDisplay(.left)
            )
        )
        definitions.append(
            Definition(id: .restore, operation: .restore, supportsPreview: false)
        )
        definitions.append(
            Definition(
                id: .cycleLeftEdge,
                operation: .cycle(
                    try! CycleGroup(
                        key: CycleGroupKey(rawValue: "left-edge"),
                        actions: [.leftHalf, leftTwoThirdsID, leftThirdID]
                    )
                ),
                supportsPreview: false
            )
        )
        definitions.append(
            Definition(
                id: .nativeFullScreen,
                operation: .nativeFullScreen,
                supportsPreview: false
            )
        )
        return Self(definitions: definitions)
    }()

    private let definitions: [ActionID: Definition]

    init(definitions: [Definition]) {
        self.definitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
    }

    func definition(for action: ActionID) -> Definition? {
        definitions[action]
    }

    private static func placementAction(for region: LayoutRegionID) -> ActionID? {
        let actions: [LayoutRegionID: ActionID] = [
            .maximize: .maximize,
            .leftHalf: .leftHalf,
            .rightHalf: .rightHalf,
            .topHalf: .topHalf,
            .bottomHalf: .bottomHalf,
            .topLeftQuarter: .topLeftQuarter,
            .topRightQuarter: .topRightQuarter,
            .bottomLeftQuarter: .bottomLeftQuarter,
            .bottomRightQuarter: .bottomRightQuarter,
        ]
        return actions[region]
    }
}
