import Foundation

/// A validated application identity used by per-app policy.
///
/// The value can contain only a bundle identifier. Window titles, document names, and
/// other content-bearing metadata cannot cross this Interface.
public struct ApplicationBundleIdentifier: Hashable, Codable, Sendable {
    public let value: String

    public init?(_ value: String) {
        guard Self.isValid(value) else { return nil }
        self.value = value.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let identifier = Self(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a valid application bundle identifier."
            )
        }
        self = identifier
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    private static func isValid(_ value: String) -> Bool {
        guard value.utf8.count <= 255 else { return false }
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }

        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.utf8.allSatisfy { character in
                switch character {
                case 45, 48 ... 57, 65 ... 90, 97 ... 122:
                    true
                default:
                    false
                }
            }
        }
    }
}

public enum AppRuleDecision: String, Codable, Equatable, Sendable {
    case included
    case excluded
}

public struct AppRule: Codable, Equatable, Sendable {
    public let bundleIdentifier: ApplicationBundleIdentifier
    public let decision: AppRuleDecision

    public init(
        bundleIdentifier: ApplicationBundleIdentifier,
        decision: AppRuleDecision
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.decision = decision
    }
}

/// Resolves per-app include/exclude rules without observing window content.
///
/// Identified apps are included by default so installing My Mac X does not silently disable
/// its core behavior. Missing or malformed identities and conflicting rules fail closed.
public struct AppRulePolicy: Equatable, Sendable {
    public let unmatched: AppRuleDecision
    public let rules: [AppRule]

    private let decisions: [ApplicationBundleIdentifier: AppRuleDecision]

    public init(
        unmatched: AppRuleDecision = .included,
        rules: [AppRule] = []
    ) {
        self.unmatched = unmatched
        self.rules = rules

        var decisions: [ApplicationBundleIdentifier: AppRuleDecision] = [:]
        for rule in rules {
            if decisions[rule.bundleIdentifier] == .excluded || rule.decision == .excluded {
                decisions[rule.bundleIdentifier] = .excluded
            } else {
                decisions[rule.bundleIdentifier] = .included
            }
        }
        self.decisions = decisions
    }

    public func decision(for bundleIdentifier: String?) -> AppRuleDecision {
        guard let bundleIdentifier,
              let identifier = ApplicationBundleIdentifier(bundleIdentifier)
        else {
            return .excluded
        }
        return decisions[identifier] ?? unmatched
    }
}

/// Atomically replaces the active per-app policy so saved changes take effect without restart.
protocol AppRuleDeciding: Sendable {
    func decision(for bundleIdentifier: String?) async -> AppRuleDecision
}

public actor AppRuleRuntime: AppRuleDeciding {
    private var policy: AppRulePolicy

    public init(policy: AppRulePolicy = AppRulePolicy()) {
        self.policy = policy
    }

    public func replace(with policy: AppRulePolicy) {
        self.policy = policy
    }

    public func decision(for bundleIdentifier: String?) -> AppRuleDecision {
        policy.decision(for: bundleIdentifier)
    }
}
