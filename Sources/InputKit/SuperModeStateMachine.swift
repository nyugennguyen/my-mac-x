import Foundation

/// Prefix-independent one- or two-level hardware key-code paths for Super Mode.
/// S5-03 owns persistence, conflict validation, and construction from user settings.
struct SuperModeCommandTree: Equatable, Sendable {
    private let oneLevel: [UInt16: ActionID]
    private let twoLevel: [UInt16: [UInt16: ActionID]]

    init(
        oneLevel: [UInt16: ActionID] = [:],
        twoLevel: [UInt16: [UInt16: ActionID]] = [:]
    ) {
        precondition(
            Set(oneLevel.keys).isDisjoint(with: Set(twoLevel.keys)),
            "A Super Mode root key cannot both execute and enter a submenu"
        )
        precondition(
            twoLevel.values.allSatisfy { !$0.isEmpty },
            "A Super Mode submenu must contain at least one action"
        )
        self.oneLevel = oneLevel
        self.twoLevel = twoLevel
    }

    fileprivate func action(for hardwareKeyCode: UInt16) -> ActionID? {
        oneLevel[hardwareKeyCode]
    }

    fileprivate func submenu(for hardwareKeyCode: UInt16) -> [UInt16: ActionID]? {
        twoLevel[hardwareKeyCode]
    }
}

struct SuperModeSessionID: RawRepresentable, Equatable, Hashable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

enum SuperModePresentationState: Equatable, Sendable {
    case idle
    case armed(session: SuperModeSessionID)
    case submenu(session: SuperModeSessionID, hardwareKeyCode: UInt16)
}

enum SuperModeInput: Equatable, Sendable {
    case prefix
    case keyDown(hardwareKeyCode: UInt16)
    case escape
    case timeout(session: SuperModeSessionID)
    case tapDisabled
    case stop
}

enum SuperModeEventDisposition: Equatable, Sendable {
    case consume
    case passThrough
}

enum SuperModeCancellationReason: Equatable, Sendable {
    case invalidKey(hardwareKeyCode: UInt16)
    case escape
    case timeout
    case repeatedPrefix
    case tapDisabled
    case stopped
}

enum SuperModeOutcome: Equatable, Sendable {
    case none
    case armed
    case submenuEntered
    case execute(ActionID)
    case cancelled(SuperModeCancellationReason)
}

struct SuperModeTransition: Equatable, Sendable {
    let previous: SuperModePresentationState
    let current: SuperModePresentationState
    let disposition: SuperModeEventDisposition
    let outcome: SuperModeOutcome
}

/// Synchronous deterministic Interface used by the future S5-06 Event Tap integration.
/// It accepts only classified non-text inputs and returns the same-callback suppression decision.
struct SuperModeReducer: Sendable {
    private let commandTree: SuperModeCommandTree
    private var lastIssuedSession: UInt64 = 0

    private(set) var presentation: SuperModePresentationState = .idle

    init(commandTree: SuperModeCommandTree) {
        self.commandTree = commandTree
    }

    mutating func reduce(_ input: SuperModeInput) -> SuperModeTransition {
        switch presentation {
        case .idle:
            return reduceIdle(input)
        case let .armed(session):
            if let transition = reduceActiveControl(input, session: session) {
                return transition
            }
            return reduceArmedKey(input)
        case let .submenu(session, firstKeyCode):
            if let transition = reduceActiveControl(input, session: session) {
                return transition
            }
            return reduceSubmenuKey(input, firstKeyCode: firstKeyCode)
        }
    }

    private mutating func reduceIdle(_ input: SuperModeInput) -> SuperModeTransition {
        guard input == .prefix else {
            return unchanged()
        }

        precondition(
            lastIssuedSession < UInt64.max,
            "Super Mode exhausted its monotonically unique session ID space"
        )
        lastIssuedSession += 1
        let previous = presentation
        presentation = .armed(session: SuperModeSessionID(rawValue: lastIssuedSession))
        return transition(
            from: previous,
            disposition: .consume,
            outcome: .armed
        )
    }

    private mutating func reduceActiveControl(
        _ input: SuperModeInput,
        session: SuperModeSessionID
    ) -> SuperModeTransition? {
        switch input {
        case .prefix:
            return cancel(.repeatedPrefix, disposition: .consume)
        case .escape:
            return cancel(.escape, disposition: .consume)
        case let .timeout(timeoutSession):
            guard timeoutSession == session else {
                return unchanged()
            }
            return cancel(.timeout, disposition: .passThrough)
        case .tapDisabled:
            return cancel(.tapDisabled, disposition: .passThrough)
        case .stop:
            return cancel(.stopped, disposition: .passThrough)
        case .keyDown:
            return nil
        }
    }

    private mutating func reduceArmedKey(_ input: SuperModeInput) -> SuperModeTransition {
        guard case let .keyDown(hardwareKeyCode) = input else {
            return unchanged()
        }

        if let action = commandTree.action(for: hardwareKeyCode) {
            return execute(action)
        }

        if commandTree.submenu(for: hardwareKeyCode) != nil,
           case let .armed(session) = presentation {
            let previous = presentation
            presentation = .submenu(
                session: session,
                hardwareKeyCode: hardwareKeyCode
            )
            return transition(
                from: previous,
                disposition: .consume,
                outcome: .submenuEntered
            )
        }

        return cancel(
            .invalidKey(hardwareKeyCode: hardwareKeyCode),
            disposition: .passThrough
        )
    }

    private mutating func reduceSubmenuKey(
        _ input: SuperModeInput,
        firstKeyCode: UInt16
    ) -> SuperModeTransition {
        guard case let .keyDown(hardwareKeyCode) = input else {
            return unchanged()
        }

        if let action = commandTree.submenu(for: firstKeyCode)?[hardwareKeyCode] {
            return execute(action)
        }

        return cancel(
            .invalidKey(hardwareKeyCode: hardwareKeyCode),
            disposition: .passThrough
        )
    }

    private func unchanged() -> SuperModeTransition {
        transition(
            from: presentation,
            disposition: .passThrough,
            outcome: .none
        )
    }

    private mutating func execute(_ action: ActionID) -> SuperModeTransition {
        let previous = presentation
        presentation = .idle
        return transition(
            from: previous,
            disposition: .consume,
            outcome: .execute(action)
        )
    }

    private mutating func cancel(
        _ reason: SuperModeCancellationReason,
        disposition: SuperModeEventDisposition
    ) -> SuperModeTransition {
        let previous = presentation
        presentation = .idle
        return transition(
            from: previous,
            disposition: disposition,
            outcome: .cancelled(reason)
        )
    }

    private func transition(
        from previous: SuperModePresentationState,
        disposition: SuperModeEventDisposition,
        outcome: SuperModeOutcome
    ) -> SuperModeTransition {
        SuperModeTransition(
            previous: previous,
            current: presentation,
            disposition: disposition,
            outcome: outcome
        )
    }
}
