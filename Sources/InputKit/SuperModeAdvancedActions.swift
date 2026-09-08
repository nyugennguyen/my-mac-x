enum SuperModeAppAction: Equatable, Sendable {
    case openSettings
    case toggleGaps
    case selectProfile
}

/// Stable non-Window Action identifiers understood by Super Mode.
///
/// These actions deliberately remain outside `ActionRegistry`, whose Interface describes
/// Window Actions. Until a production app-action Adapter exists, resolution is discoverable
/// but dispatch fails closed with a typed result.
struct SuperModeAppActionCatalog: Sendable {
    struct Definition: Equatable, Sendable {
        let id: ActionID
        let action: SuperModeAppAction
    }

    static let builtIn = Self(definitions: [
        Definition(id: .openSettings, action: .openSettings),
        Definition(id: .toggleGaps, action: .toggleGaps),
        Definition(id: .selectProfile, action: .selectProfile),
    ])

    let definitions: [Definition]

    private let actionsByID: [ActionID: SuperModeAppAction]

    init(definitions: [Definition]) {
        precondition(
            Set(definitions.map(\.id)).count == definitions.count,
            "SuperModeAppActionCatalog requires unique ActionID values"
        )
        self.definitions = definitions
        actionsByID = Dictionary(
            uniqueKeysWithValues: definitions.map { ($0.id, $0.action) }
        )
    }

    func action(for id: ActionID) -> SuperModeAppAction? {
        actionsByID[id]
    }
}

enum SuperModeAdvancedActionResolution: Equatable, Sendable {
    case window(ActionDescriptor)
    case app(SuperModeAppAction)
    case notRegistered
}

/// Resolves every completed Super Mode sequence without conflating app-level actions with
/// Window Actions. Registered Window Actions retain `ActionRegistry` availability metadata.
struct SuperModeAdvancedActionResolver: Sendable {
    private let windowActions: ActionRegistry
    private let appActions: SuperModeAppActionCatalog

    init(
        windowActions: ActionRegistry,
        appActions: SuperModeAppActionCatalog = .builtIn
    ) {
        self.windowActions = windowActions
        self.appActions = appActions
    }

    func resolve(_ id: ActionID) -> SuperModeAdvancedActionResolution {
        if let appAction = appActions.action(for: id) {
            return .app(appAction)
        }
        if let descriptor = windowActions.action(for: id) {
            return .window(descriptor)
        }
        return .notRegistered
    }
}

enum SuperModeAdvancedDispatchUnavailability: Equatable, Sendable {
    case notRegistered
    case windowAction(ActionUnavailability)
    case productionAdapterUnavailable(SuperModeAppAction)
}

enum SuperModeAdvancedDispatchResult: Equatable, Sendable {
    case dispatched(WindowActionResult)
    case dispatchedAppAction(SuperModeAppAction)
    case unavailable(SuperModeAdvancedDispatchUnavailability)
}

protocol SuperModeAppActionPerforming: Sendable {
    func perform(_ action: SuperModeAppAction) async -> Bool
}

struct SuperModeAppActionAdapter: SuperModeAppActionPerforming {
    let openSettings: @MainActor @Sendable () -> Void
    let toggleGaps: @Sendable () async -> Bool
    let selectProfile: @MainActor @Sendable () async -> Bool

    init(
        openSettings: @escaping @MainActor @Sendable () -> Void,
        toggleGaps: @escaping @Sendable () async -> Bool = { false },
        selectProfile: @escaping @MainActor @Sendable () async -> Bool = { false }
    ) {
        self.openSettings = openSettings
        self.toggleGaps = toggleGaps
        self.selectProfile = selectProfile
    }

    func perform(_ action: SuperModeAppAction) async -> Bool {
        switch action {
        case .openSettings:
            await openSettings()
            return true
        case .toggleGaps:
            return await toggleGaps()
        case .selectProfile:
            return await selectProfile()
        }
    }
}

/// Routes resolved Window Actions through the existing Super Mode dispatcher exactly once.
/// App-level commands fail closed until an honest production Adapter owns their behavior.
struct SuperModeAdvancedActionDispatcher: Sendable {
    private let resolver: SuperModeAdvancedActionResolver
    private let windowDispatcher: SuperModeActionDispatcher
    private let appActionPerformer: (any SuperModeAppActionPerforming)?

    init(
        actionRegistry: ActionRegistry,
        windowActions: any WindowActionPerforming,
        appActions: SuperModeAppActionCatalog = .builtIn,
        appActionPerformer: (any SuperModeAppActionPerforming)? = nil
    ) {
        resolver = SuperModeAdvancedActionResolver(
            windowActions: actionRegistry,
            appActions: appActions
        )
        windowDispatcher = SuperModeActionDispatcher(
            actionRegistry: actionRegistry,
            windowActions: windowActions
        )
        self.appActionPerformer = appActionPerformer
    }

    func dispatch(_ id: ActionID) async -> SuperModeAdvancedDispatchResult {
        switch resolver.resolve(id) {
        case .notRegistered:
            return .unavailable(.notRegistered)
        case let .app(action):
            guard let appActionPerformer,
                  await appActionPerformer.perform(action) else {
                return .unavailable(.productionAdapterUnavailable(action))
            }
            return .dispatchedAppAction(action)
        case .window:
            switch await windowDispatcher.dispatch(id) {
            case let .dispatched(result):
                return .dispatched(result)
            case .dispatchedAppAction:
                preconditionFailure("Window dispatcher cannot dispatch app actions")
            case .unavailable(.notRegistered):
                return .unavailable(.notRegistered)
            case let .unavailable(.action(reason)):
                return .unavailable(.windowAction(reason))
            }
        }
    }
}
