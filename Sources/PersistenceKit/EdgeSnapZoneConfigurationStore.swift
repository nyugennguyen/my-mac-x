import CoreGraphics
import Foundation

/// User-configurable seam-gate velocity parameters (S-01, S-02).
public struct SeamGateSettings: Equatable, Sendable {
    public static let defaultCrossingSpeedThreshold: Double = 400.0

    public var isEnabled: Bool
    public var crossingSpeedThreshold: Double

    public init(
        isEnabled: Bool = true,
        crossingSpeedThreshold: Double = Self.defaultCrossingSpeedThreshold
    ) {
        self.isEnabled = isEnabled
        self.crossingSpeedThreshold = crossingSpeedThreshold
    }
}

/// A snapshot of edge snap perimeter zone assignments, sub-partitions, disabled switches, and seam gating.
public struct EdgeSnapZoneConfigurationSnapshot: Equatable, Sendable {
    public var customActions: [EdgeSnapZone: ActionID]
    public var customPartitions: [EdgeSnapZone: [ActionID]]
    public var disabledZones: Set<EdgeSnapZone>
    public var seamGating: SeamGateSettings

    public init(
        customActions: [EdgeSnapZone: ActionID] = [:],
        customPartitions: [EdgeSnapZone: [ActionID]] = [:],
        disabledZones: Set<EdgeSnapZone> = [],
        seamGating: SeamGateSettings = SeamGateSettings()
    ) {
        var actions = customActions
        var partitions = customPartitions

        for (zone, action) in customActions {
            if partitions[zone] == nil || partitions[zone]?.isEmpty == true {
                partitions[zone] = [action]
            }
        }
        for (zone, actionList) in partitions {
            if actions[zone] == nil, let first = actionList.first {
                actions[zone] = first
            }
        }

        self.customActions = actions
        self.customPartitions = partitions
        self.disabledZones = disabledZones
        self.seamGating = seamGating
    }

    public init(
        configuration: EdgeSnapZoneConfiguration,
        seamGating: SeamGateSettings = SeamGateSettings()
    ) {
        self.customActions = configuration.customActions
        self.customPartitions = configuration.customActions.mapValues { [$0] }
        self.disabledZones = configuration.disabledZones
        self.seamGating = seamGating
    }

    /// Adapts snapshot to pure TriggerGeometryKit configuration model.
    public func toZoneConfiguration() -> EdgeSnapZoneConfiguration {
        EdgeSnapZoneConfiguration(
            customActions: customActions,
            disabledZones: disabledZones
        )
    }

    /// Checks if a zone is in its default state (unmodified action and enabled).
    public func isDefault(zone: EdgeSnapZone) -> Bool {
        if disabledZones.contains(zone) { return false }
        if let partitions = customPartitions[zone], !partitions.isEmpty {
            if partitions.count != 1 || partitions.first != zone.defaultAction {
                return false
            }
        }
        if let custom = customActions[zone], custom != zone.defaultAction {
            return false
        }
        return true
    }

    /// Returns true if all zones are in default configuration and seam gating is at defaults.
    public var isAllDefault: Bool {
        guard disabledZones.isEmpty else { return false }
        guard seamGating == SeamGateSettings() else { return false }
        for zone in EdgeSnapZone.allCases {
            if !isDefault(zone: zone) { return false }
        }
        return true
    }
}

/// Compact delta serialization and resilient deserialization codec for Edge Snap zone settings (Z-06, Z-07, Z-08).
public struct EdgeSnapZoneDeltaCodec: Sendable {

    // MARK: - Z-06 Zone Actions Delta Encoding

    /// Encodes only deviations from default actions into a deterministic comma-separated string.
    public static func encodeZoneActions(_ snapshot: EdgeSnapZoneConfigurationSnapshot) -> String {
        var deviations: [(key: String, value: String)] = []

        // Sort zones deterministically by rawValue
        for zone in EdgeSnapZone.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let partitions = snapshot.customPartitions[zone], !partitions.isEmpty {
                // If it's single part matching defaultAction, it is omitted per Z-06
                if partitions.count == 1 && partitions.first == zone.defaultAction {
                    continue
                }
                let joinedActions = partitions.map(\.rawValue).joined(separator: "+")
                deviations.append((key: zone.rawValue, value: "\(zone.rawValue)=\(joinedActions)"))
            } else if let action = snapshot.customActions[zone] {
                if action != zone.defaultAction {
                    deviations.append((key: zone.rawValue, value: "\(zone.rawValue)=\(action.rawValue)"))
                }
            }
        }

        return deviations.map(\.value).joined(separator: ",")
    }

    // MARK: - Z-07 Resilient Fallback Deserialization

    /// Decodes a delta string into custom actions and partitions, discarding malformed or unpermitted entries.
    public static func decodeZoneActions(
        _ string: String,
        diagnostics: PrivacySafeDiagnosticsLogger? = nil
    ) -> (customActions: [EdgeSnapZone: ActionID], customPartitions: [EdgeSnapZone: [ActionID]]) {
        var actions: [EdgeSnapZone: ActionID] = [:]
        var partitions: [EdgeSnapZone: [ActionID]] = [:]

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (actions, partitions)
        }

        let entries = trimmed.components(separatedBy: ",")
        for rawEntry in entries {
            let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.isEmpty { continue }

            // 1. Must contain "="
            guard let equalsIndex = entry.firstIndex(of: "=") else {
                diagnostics?.record(.persistence(.decodeAnomaly))
                continue
            }

            let zoneName = String(entry[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let actionString = String(entry[entry.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            // 2. Zone name must match EdgeSnapZone enum
            guard let zone = EdgeSnapZone(rawValue: zoneName) else {
                diagnostics?.record(.persistence(.decodeAnomaly))
                continue
            }

            // 3. Sub-actions split by "+"
            let actionTokens = actionString.components(separatedBy: "+").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }

            guard !actionTokens.isEmpty else {
                diagnostics?.record(.persistence(.decodeAnomaly))
                continue
            }

            // 4. Validate partition counts: corners max 1, edges max 4 (Z-03)
            let maxParts = zone.isCorner ? 1 : 4
            guard actionTokens.count <= maxParts else {
                diagnostics?.record(.persistence(.decodeAnomaly))
                continue
            }

            // 5. Validate permitted actions (Z-05)
            var zoneActions: [ActionID] = []
            var allValid = true
            for token in actionTokens {
                let actionID = ActionID(rawValue: token)
                if EdgeSnapZone.isPermittedAction(actionID) {
                    zoneActions.append(actionID)
                } else {
                    allValid = false
                    break
                }
            }

            // Z-07: If any sub-part fails validation, discard entire zone entry
            guard allValid, !zoneActions.isEmpty else {
                diagnostics?.record(.persistence(.decodeAnomaly))
                continue
            }

            partitions[zone] = zoneActions
            if let firstAction = zoneActions.first {
                actions[zone] = firstAction
            }
        }

        return (actions, partitions)
    }

    // MARK: - Z-08 Disabled Zones Delta Encoding & Decoding

    /// Encodes disabled zones as a sorted array of zone names.
    public static func encodeDisabledZones(_ snapshot: EdgeSnapZoneConfigurationSnapshot) -> [String] {
        snapshot.disabledZones.map(\.rawValue).sorted()
    }

    /// Decodes an array of zone strings, discarding unknown zone names.
    public static func decodeDisabledZones(
        _ array: [String],
        diagnostics: PrivacySafeDiagnosticsLogger? = nil
    ) -> Set<EdgeSnapZone> {
        var disabled: Set<EdgeSnapZone> = []
        for name in array {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let zone = EdgeSnapZone(rawValue: trimmed) {
                disabled.insert(zone)
            } else {
                diagnostics?.record(.persistence(.decodeAnomaly))
            }
        }
        return disabled
    }

    // MARK: - Seam Gate Validation

    /// Validates crossing speed threshold, falling back to 400.0 if not strictly positive and finite.
    public static func validateCrossingSpeedThreshold(
        _ threshold: Double,
        diagnostics: PrivacySafeDiagnosticsLogger? = nil
    ) -> Double {
        if threshold.isFinite && threshold > 0 {
            return threshold
        }
        diagnostics?.record(.persistence(.decodeAnomaly))
        return SeamGateSettings.defaultCrossingSpeedThreshold
    }
}

/// Interface exposed to the Zone-Map Picker UI and Settings Shell.
@MainActor
public protocol EdgeSnapZoneConfigurationStoring: AnyObject, Sendable {
    var snapshot: EdgeSnapZoneConfigurationSnapshot { get }
    var configuration: EdgeSnapZoneConfiguration { get }

    func action(for zone: EdgeSnapZone) -> ActionID
    func actions(for zone: EdgeSnapZone) -> [ActionID]
    func isEnabled(_ zone: EdgeSnapZone) -> Bool
    func isDefault(zone: EdgeSnapZone) -> Bool
    var isAllDefault: Bool { get }

    func setAction(_ action: ActionID, for zone: EdgeSnapZone)
    func setActions(_ actions: [ActionID], for zone: EdgeSnapZone)
    func setEnabled(_ isEnabled: Bool, for zone: EdgeSnapZone)
    func toggleEnabled(for zone: EdgeSnapZone)
    func seamGateSettings() -> SeamGateSettings
    func setSeamGating(_ settings: SeamGateSettings)
    func setCrossingSpeedThreshold(_ threshold: Double)
    func setSeamGatingEnabled(_ isEnabled: Bool)
    func reset(zone: EdgeSnapZone)
    func resetAllToDefaults()
    func load(from snapshot: EdgeSnapZoneConfigurationSnapshot)
}

/// Concrete observable store providing binding and persistence hooks for Edge Snap zone editing.
@MainActor
public final class EdgeSnapZoneConfigurationStore: ObservableObject, EdgeSnapZoneConfigurationStoring {
    @Published public private(set) var snapshot: EdgeSnapZoneConfigurationSnapshot

    /// Callback invoked whenever the store is mutated, allowing the runtime to persist changes.
    public var onConfigurationChanged: (@MainActor (EdgeSnapZoneConfigurationSnapshot) -> Void)?

    public init(snapshot: EdgeSnapZoneConfigurationSnapshot = EdgeSnapZoneConfigurationSnapshot()) {
        self.snapshot = snapshot
    }

    public var configuration: EdgeSnapZoneConfiguration {
        snapshot.toZoneConfiguration()
    }

    public func action(for zone: EdgeSnapZone) -> ActionID {
        if let partitions = snapshot.customPartitions[zone], let first = partitions.first, EdgeSnapZone.isPermittedAction(first) {
            return first
        }
        if let custom = snapshot.customActions[zone], EdgeSnapZone.isPermittedAction(custom) {
            return custom
        }
        return zone.defaultAction
    }

    public func actions(for zone: EdgeSnapZone) -> [ActionID] {
        if let partitions = snapshot.customPartitions[zone], !partitions.isEmpty {
            return partitions
        }
        if let custom = snapshot.customActions[zone] {
            return [custom]
        }
        return [zone.defaultAction]
    }

    public func isEnabled(_ zone: EdgeSnapZone) -> Bool {
        !snapshot.disabledZones.contains(zone)
    }

    public func isDefault(zone: EdgeSnapZone) -> Bool {
        snapshot.isDefault(zone: zone)
    }

    public var isAllDefault: Bool {
        snapshot.isAllDefault
    }

    public func setAction(_ action: ActionID, for zone: EdgeSnapZone) {
        guard EdgeSnapZone.isPermittedAction(action) else { return }
        snapshot.customActions[zone] = action
        snapshot.customPartitions[zone] = [action]
        notifyChange()
    }

    public func setActions(_ actions: [ActionID], for zone: EdgeSnapZone) {
        let maxParts = zone.isCorner ? 1 : 4
        guard actions.count <= maxParts, actions.allSatisfy(EdgeSnapZone.isPermittedAction) else { return }
        snapshot.customPartitions[zone] = actions
        if let first = actions.first {
            snapshot.customActions[zone] = first
        }
        notifyChange()
    }

    public func setEnabled(_ isEnabled: Bool, for zone: EdgeSnapZone) {
        if isEnabled {
            snapshot.disabledZones.remove(zone)
        } else {
            snapshot.disabledZones.insert(zone)
        }
        notifyChange()
    }

    public func toggleEnabled(for zone: EdgeSnapZone) {
        setEnabled(!isEnabled(zone), for: zone)
    }

    public func seamGateSettings() -> SeamGateSettings {
        snapshot.seamGating
    }

    public func setSeamGating(_ settings: SeamGateSettings) {
        snapshot.seamGating = settings
        notifyChange()
    }

    public func setCrossingSpeedThreshold(_ threshold: Double) {
        snapshot.seamGating.crossingSpeedThreshold = EdgeSnapZoneDeltaCodec.validateCrossingSpeedThreshold(threshold)
        notifyChange()
    }

    public func setSeamGatingEnabled(_ isEnabled: Bool) {
        snapshot.seamGating.isEnabled = isEnabled
        notifyChange()
    }

    public func reset(zone: EdgeSnapZone) {
        snapshot.customActions.removeValue(forKey: zone)
        snapshot.customPartitions.removeValue(forKey: zone)
        snapshot.disabledZones.remove(zone)
        notifyChange()
    }

    public func resetAllToDefaults() {
        snapshot = EdgeSnapZoneConfigurationSnapshot()
        notifyChange()
    }

    public func load(from snapshot: EdgeSnapZoneConfigurationSnapshot) {
        self.snapshot = snapshot
        notifyChange()
    }

    private func notifyChange() {
        onConfigurationChanged?(snapshot)
    }
}
