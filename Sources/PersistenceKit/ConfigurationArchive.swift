import CoreGraphics
import Foundation

struct GeneralSettings: Equatable, Sendable {
    var launchesAtLogin: Bool

    init(launchesAtLogin: Bool = false) {
        self.launchesAtLogin = launchesAtLogin
    }
}

enum SnappingSettingsTrigger: String, Equatable, Sendable {
    case notch
    case topCenter
}

struct SnappingSettings: Equatable, Sendable {
    var isEnabled: Bool
    var trigger: SnappingSettingsTrigger
    var dwellMilliseconds: UInt32
    var showsPlacementPreview: Bool
    var usesReducedEffects: Bool

    init(
        isEnabled: Bool = true,
        trigger: SnappingSettingsTrigger = .notch,
        dwellMilliseconds: UInt32 = 150,
        showsPlacementPreview: Bool = true,
        usesReducedEffects: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.dwellMilliseconds = dwellMilliseconds
        self.showsPlacementPreview = showsPlacementPreview
        self.usesReducedEffects = usesReducedEffects
    }
}

/// The complete portable configuration understood by the Sprint 6 transfer format.
///
/// System paths, permission state, window identity, diagnostics, and credentials are absent by
/// construction. The persistence Adapter may pass this value to `ConfigurationArchive` without
/// exposing its own document location or atomic-write machinery.
struct ConfigurationSnapshot: Equatable, Sendable {
    let general: GeneralSettings
    let snapping: SnappingSettings
    let hotkeySettings: HotkeySettings
    let layouts: [LayoutDraft]
    let displayProfiles: [DisplayProfile]
    let appRulePolicy: AppRulePolicy

    init(
        general: GeneralSettings = GeneralSettings(),
        snapping: SnappingSettings = SnappingSettings(),
        hotkeySettings: HotkeySettings,
        layouts: [LayoutDraft],
        displayProfiles: [DisplayProfile],
        appRulePolicy: AppRulePolicy = AppRulePolicy()
    ) {
        self.general = general
        self.snapping = snapping
        self.hotkeySettings = hotkeySettings
        self.layouts = layouts
        self.displayProfiles = displayProfiles
        self.appRulePolicy = appRulePolicy
    }
}

enum ConfigurationImportOrigin: Equatable, Sendable {
    case current(schemaVersion: UInt16)
    case migrated(fromVersion: UInt16, toVersion: UInt16)
}

enum ConfigurationImportResult: Equatable, Sendable {
    case imported(ConfigurationSnapshot, origin: ConfigurationImportOrigin)
    case rejected(ConfigurationArchiveFailure)
}

enum ConfigurationArchiveFailure: Error, Equatable, Sendable {
    case documentTooLarge(maximumBytes: Int)
    case malformedOrUnexpectedSchema
    case unsupportedFutureVersion(UInt16)
    case invalidConfiguration(ConfigurationValidationFailure)
}

enum ConfigurationExportFailure: Error, Equatable, Sendable {
    case invalidConfiguration(ConfigurationValidationFailure)
    case documentTooLarge(maximumBytes: Int)
    case encodingFailed
}

enum ConfigurationValidationFailure: Error, Equatable, Sendable {
    case duplicateHotkeyBindingID(UUID)
    case unsupportedHotkeyModifiers(bindingID: UUID)
    case unknownHotkeyAction(ActionID)
    case invalidSuperMode(SuperModeConfigurationFailure)
    case duplicateLayoutID(String)
    case layout(layoutID: String, failure: LayoutLibraryFailure)
    case profile(stableDisplayID: String, failure: DisplayProfileFailure)
    case duplicateDisplayProfile(StableDisplayID)
    case unknownProfileLayout(stableDisplayID: StableDisplayID, layoutID: String)
    case invalidSnappingDwellMilliseconds(UInt32)
    case duplicateAppRule(ApplicationBundleIdentifier)
}

/// Strict, versioned import/export codec for configuration backup and restore.
struct ConfigurationArchive: Sendable {
    static let maximumDocumentSize = 256 * 1024

    static let currentSchemaVersion: UInt16 = 3
    private static let supportedModifierBits = HotkeyModifiers.command.rawValue
        | HotkeyModifiers.option.rawValue
        | HotkeyModifiers.control.rawValue
        | HotkeyModifiers.shift.rawValue

    private let actionRegistry: ActionRegistry
    private let superModeValidator: SuperModeConfigurationValidator

    init(actionRegistry: ActionRegistry) {
        self.actionRegistry = actionRegistry
        superModeValidator = SuperModeConfigurationValidator(actionRegistry: actionRegistry)
    }

    func export(_ snapshot: ConfigurationSnapshot) throws -> Data {
        if let failure = validationFailure(in: snapshot) {
            throw ConfigurationExportFailure.invalidConfiguration(failure)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(V3ConfigurationDocument(snapshot))
            guard data.count <= Self.maximumDocumentSize else {
                throw ConfigurationExportFailure.documentTooLarge(
                    maximumBytes: Self.maximumDocumentSize
                )
            }
            return data
        } catch let failure as ConfigurationExportFailure {
            throw failure
        } catch {
            throw ConfigurationExportFailure.encodingFailed
        }
    }

    func `import`(_ data: Data) -> ConfigurationImportResult {
        guard data.count <= Self.maximumDocumentSize else {
            return .rejected(.documentTooLarge(maximumBytes: Self.maximumDocumentSize))
        }

        do {
            var parser = ConfigurationJSONParser(data: data, maximumDepth: 9)
            let value = try parser.parse()
            guard case let .object(fields) = value,
                  let version = unsignedInteger(fields["schemaVersion"], as: UInt16.self)
            else {
                return .rejected(.malformedOrUnexpectedSchema)
            }
            if version > Self.currentSchemaVersion {
                return .rejected(.unsupportedFutureVersion(version))
            }

            let snapshot: ConfigurationSnapshot
            let origin: ConfigurationImportOrigin
            switch version {
            case 1:
                guard Set(fields.keys) == [
                    "schemaVersion",
                    "hotkeyBindings",
                    "layouts",
                    "displayProfiles",
                ] else {
                    return .rejected(.malformedOrUnexpectedSchema)
                }
                snapshot = try decodeSnapshot(fields: fields, superMode: .default)
                origin = .migrated(fromVersion: 1, toVersion: Self.currentSchemaVersion)
            case 2:
                guard Set(fields.keys) == [
                    "schemaVersion",
                    "hotkeyBindings",
                    "superMode",
                    "layouts",
                    "displayProfiles",
                ], let superMode = try decodeSuperMode(fields["superMode"]) else {
                    return .rejected(.malformedOrUnexpectedSchema)
                }
                snapshot = try decodeSnapshot(fields: fields, superMode: superMode)
                origin = .migrated(fromVersion: 2, toVersion: Self.currentSchemaVersion)
            case Self.currentSchemaVersion:
                guard Set(fields.keys) == [
                    "schemaVersion", "general", "snapping", "hotkeyBindings", "superMode",
                    "layouts", "displayProfiles", "appRules",
                ], let superMode = try decodeSuperMode(fields["superMode"]),
                   let general = decodeGeneral(fields["general"]),
                   let snapping = decodeSnapping(fields["snapping"]),
                   let appRules = try decodeAppRules(fields["appRules"]) else {
                    return .rejected(.malformedOrUnexpectedSchema)
                }
                snapshot = try decodeSnapshot(
                    fields: fields,
                    superMode: superMode,
                    general: general,
                    snapping: snapping,
                    appRulePolicy: appRules
                )
                origin = .current(schemaVersion: Self.currentSchemaVersion)
            default:
                return .rejected(.malformedOrUnexpectedSchema)
            }

            if let failure = validationFailure(in: snapshot) {
                return .rejected(.invalidConfiguration(failure))
            }
            return .imported(snapshot, origin: origin)
        } catch let failure as ConfigurationDecodeFailure {
            switch failure {
            case let .invalidConfiguration(validationFailure):
                return .rejected(.invalidConfiguration(validationFailure))
            case .invalidShape:
                return .rejected(.malformedOrUnexpectedSchema)
            }
        } catch {
            return .rejected(.malformedOrUnexpectedSchema)
        }
    }

    private func decodeSnapshot(
        fields: [String: ConfigurationJSONValue],
        superMode: SuperModeConfiguration,
        general: GeneralSettings = GeneralSettings(),
        snapping: SnappingSettings = SnappingSettings(),
        appRulePolicy: AppRulePolicy = AppRulePolicy()
    ) throws -> ConfigurationSnapshot {
        guard let bindings = try decodeHotkeyBindings(fields["hotkeyBindings"]),
              let layouts = try decodeLayouts(fields["layouts"]),
              let profiles = try decodeDisplayProfiles(fields["displayProfiles"])
        else {
            throw ConfigurationDecodeFailure.invalidShape
        }
        return ConfigurationSnapshot(
            general: general,
            snapping: snapping,
            hotkeySettings: HotkeySettings(
                bindings: bindings,
                superModeConfiguration: superMode
            ),
            layouts: layouts,
            displayProfiles: profiles,
            appRulePolicy: appRulePolicy
        )
    }

    private func decodeGeneral(_ value: ConfigurationJSONValue?) -> GeneralSettings? {
        guard case let .object(fields)? = value,
              Set(fields.keys) == ["launchesAtLogin"],
              case let .bool(launchesAtLogin)? = fields["launchesAtLogin"] else { return nil }
        return GeneralSettings(launchesAtLogin: launchesAtLogin)
    }

    private func decodeSnapping(_ value: ConfigurationJSONValue?) -> SnappingSettings? {
        guard case let .object(fields)? = value,
              Set(fields.keys) == ["isEnabled", "trigger", "dwellMilliseconds", "showsPlacementPreview", "usesReducedEffects"],
              case let .bool(isEnabled)? = fields["isEnabled"],
              case let .string(triggerText)? = fields["trigger"],
              let trigger = SnappingSettingsTrigger(rawValue: triggerText),
              let dwell = unsignedInteger(fields["dwellMilliseconds"], as: UInt32.self),
              case let .bool(showsPreview)? = fields["showsPlacementPreview"],
              case let .bool(reducedEffects)? = fields["usesReducedEffects"] else { return nil }
        return SnappingSettings(isEnabled: isEnabled, trigger: trigger, dwellMilliseconds: dwell, showsPlacementPreview: showsPreview, usesReducedEffects: reducedEffects)
    }

    private func decodeAppRules(_ value: ConfigurationJSONValue?) throws -> AppRulePolicy? {
        guard case let .object(fields)? = value,
              Set(fields.keys) == ["unmatched", "rules"],
              case let .string(unmatchedText)? = fields["unmatched"],
              let unmatched = AppRuleDecision(rawValue: unmatchedText),
              case let .array(items)? = fields["rules"] else { return nil }
        let rules = try items.map { item -> AppRule in
            guard case let .object(ruleFields) = item,
                  Set(ruleFields.keys) == ["bundleIdentifier", "decision"],
                  case let .string(identifierText)? = ruleFields["bundleIdentifier"],
                  let identifier = ApplicationBundleIdentifier(identifierText),
                  case let .string(decisionText)? = ruleFields["decision"],
                  let decision = AppRuleDecision(rawValue: decisionText) else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            return AppRule(bundleIdentifier: identifier, decision: decision)
        }
        return AppRulePolicy(unmatched: unmatched, rules: rules)
    }

    private func decodeHotkeyBindings(
        _ value: ConfigurationJSONValue?
    ) throws -> [HotkeyBinding]? {
        guard case let .array(items)? = value else { return nil }
        return try items.map { item in
            guard case let .object(fields) = item,
                  Set(fields.keys) == ["id", "hardwareKeyCode", "modifiers", "actionID"],
                  case let .string(idText)? = fields["id"],
                  let id = UUID(uuidString: idText),
                  let keyCode = unsignedInteger(fields["hardwareKeyCode"], as: UInt16.self),
                  let modifiers = unsignedInteger(fields["modifiers"], as: UInt32.self),
                  case let .string(actionText)? = fields["actionID"],
                  !actionText.isEmpty else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            return HotkeyBinding(
                id: id,
                hardwareKeyCode: keyCode,
                modifiers: HotkeyModifiers(rawValue: modifiers),
                actionID: ActionID(rawValue: actionText)
            )
        }
    }

    private func decodeSuperMode(
        _ value: ConfigurationJSONValue?
    ) throws -> SuperModeConfiguration? {
        guard case let .object(fields)? = value,
              Set(fields.keys) == ["prefix", "timeoutMilliseconds", "commandBindings"],
              case let .object(prefixFields)? = fields["prefix"],
              Set(prefixFields.keys) == ["hardwareKeyCode", "modifiers"],
              let prefixKeyCode = unsignedInteger(
                  prefixFields["hardwareKeyCode"],
                  as: UInt16.self
              ),
              let prefixModifiers = unsignedInteger(
                  prefixFields["modifiers"],
                  as: UInt32.self
              ),
              let timeout = unsignedInteger(fields["timeoutMilliseconds"], as: UInt32.self),
              case let .array(commandItems)? = fields["commandBindings"] else {
            return nil
        }

        let commands = try commandItems.map { item -> SuperModeCommandBinding in
            guard case let .object(commandFields) = item,
                  Set(commandFields.keys) == ["hardwareKeyCodes", "actionID"],
                  case let .array(keyCodeValues)? = commandFields["hardwareKeyCodes"],
                  case let .string(actionText)? = commandFields["actionID"],
                  !actionText.isEmpty else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            let keyCodes = try keyCodeValues.map { value -> UInt16 in
                guard let keyCode = unsignedInteger(value, as: UInt16.self) else {
                    throw ConfigurationDecodeFailure.invalidShape
                }
                return keyCode
            }
            return SuperModeCommandBinding(
                hardwareKeyCodes: keyCodes,
                actionID: ActionID(rawValue: actionText)
            )
        }
        return SuperModeConfiguration(
            prefix: HotkeyChord(
                hardwareKeyCode: prefixKeyCode,
                modifiers: HotkeyModifiers(rawValue: prefixModifiers)
            ),
            timeoutMilliseconds: timeout,
            commandBindings: commands
        )
    }

    private func decodeLayouts(
        _ value: ConfigurationJSONValue?
    ) throws -> [LayoutDraft]? {
        guard case let .array(items)? = value else { return nil }
        return try items.map { item in
            guard case let .object(fields) = item,
                  Set(fields.keys) == ["id", "name", "regions"],
                  case let .string(id)? = fields["id"],
                  case let .string(name)? = fields["name"],
                  case let .array(regionItems)? = fields["regions"] else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            let regions = try regionItems.map { regionItem -> LayoutRegionDraft in
                guard case let .object(regionFields) = regionItem,
                      Set(regionFields.keys) == ["id", "x", "y", "width", "height"],
                      case let .string(regionID)? = regionFields["id"],
                      let x = number(regionFields["x"]),
                      let y = number(regionFields["y"]),
                      let width = number(regionFields["width"]),
                      let height = number(regionFields["height"]) else {
                    throw ConfigurationDecodeFailure.invalidShape
                }
                return LayoutRegionDraft(
                    id: LayoutRegionID(rawValue: regionID),
                    normalizedFrame: CGRect(x: x, y: y, width: width, height: height)
                )
            }
            return LayoutDraft(id: id, name: name, regions: regions)
        }
    }

    private func decodeDisplayProfiles(
        _ value: ConfigurationJSONValue?
    ) throws -> [DisplayProfile]? {
        guard case let .array(items)? = value else { return nil }
        return try items.map { item in
            guard case let .object(fields) = item,
                  Set(fields.keys) == ["stableDisplayID", "gap", "layoutIDs"],
                  case let .string(stableIDText)? = fields["stableDisplayID"],
                  let gap = number(fields["gap"]),
                  case let .array(layoutIDValues)? = fields["layoutIDs"] else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            let layoutIDs = try layoutIDValues.map { value -> String in
                guard case let .string(layoutID) = value else {
                    throw ConfigurationDecodeFailure.invalidShape
                }
                return layoutID
            }

            do {
                let stableID = try StableDisplayID(rawValue: stableIDText)
                return try DisplayProfile(
                    stableDisplayID: stableID,
                    gap: gap,
                    layoutIDs: layoutIDs
                )
            } catch let failure as DisplayProfileFailure {
                throw ConfigurationDecodeFailure.invalidConfiguration(
                    .profile(stableDisplayID: stableIDText, failure: failure)
                )
            }
        }
    }

    private func validationFailure(
        in snapshot: ConfigurationSnapshot
    ) -> ConfigurationValidationFailure? {
        guard (50...1_000).contains(snapshot.snapping.dwellMilliseconds) else {
            return .invalidSnappingDwellMilliseconds(snapshot.snapping.dwellMilliseconds)
        }
        var bindingIDs = Set<UUID>()
        for binding in snapshot.hotkeySettings.bindings {
            guard bindingIDs.insert(binding.id).inserted else {
                return .duplicateHotkeyBindingID(binding.id)
            }
            guard binding.modifiers.rawValue & ~Self.supportedModifierBits == 0 else {
                return .unsupportedHotkeyModifiers(bindingID: binding.id)
            }
            guard actionRegistry.action(for: binding.actionID) != nil else {
                return .unknownHotkeyAction(binding.actionID)
            }
        }
        switch superModeValidator.validate(
            snapshot.hotkeySettings.superModeConfiguration,
            hotkeyBindings: snapshot.hotkeySettings.bindings
        ) {
        case .valid:
            break
        case let .invalid(failure):
            return .invalidSuperMode(failure)
        }

        var library = LayoutLibrary()
        var layoutIDs = Set<String>()
        for draft in snapshot.layouts {
            guard layoutIDs.insert(draft.id).inserted else {
                return .duplicateLayoutID(draft.id)
            }
            if case let .failure(failure) = library.save(draft) {
                return .layout(layoutID: draft.id, failure: failure)
            }
        }

        do {
            _ = try DisplayProfileLibrary(profiles: snapshot.displayProfiles)
        } catch let failure as DisplayProfileFailure {
            if case let .duplicateStableDisplayID(stableID) = failure {
                return .duplicateDisplayProfile(stableID)
            }
            preconditionFailure("DisplayProfileLibrary returned an unexpected failure")
        } catch {
            preconditionFailure("DisplayProfileLibrary returned a non-domain failure")
        }

        let availableLayoutIDs = layoutIDs.union([Layout.builtIn.id])
        for profile in snapshot.displayProfiles {
            for layoutID in profile.layoutIDs where !availableLayoutIDs.contains(layoutID) {
                return .unknownProfileLayout(
                    stableDisplayID: profile.stableDisplayID,
                    layoutID: layoutID
                )
            }
        }
        var appIdentifiers = Set<ApplicationBundleIdentifier>()
        for rule in snapshot.appRulePolicy.rules where !appIdentifiers.insert(rule.bundleIdentifier).inserted {
            return .duplicateAppRule(rule.bundleIdentifier)
        }
        return nil
    }

    private func unsignedInteger<T: FixedWidthInteger & UnsignedInteger>(
        _ value: ConfigurationJSONValue?,
        as type: T.Type
    ) -> T? {
        guard let number = number(value),
              number.rounded() == number,
              number >= 0,
              number <= Double(T.max) else {
            return nil
        }
        return T(number)
    }

    private func number(_ value: ConfigurationJSONValue?) -> Double? {
        guard case let .number(number)? = value, number.isFinite else { return nil }
        return number
    }
}

private enum ConfigurationDecodeFailure: Error {
    case invalidShape
    case invalidConfiguration(ConfigurationValidationFailure)
}

private struct V3ConfigurationDocument: Encodable {
    let schemaVersion: UInt16 = 3
    let general: EncodedGeneralSettings
    let snapping: EncodedSnappingSettings
    let hotkeyBindings: [EncodedHotkeyBinding]
    let superMode: EncodedSuperMode
    let layouts: [EncodedLayout]
    let displayProfiles: [EncodedDisplayProfile]
    let appRules: EncodedAppRules

    init(_ snapshot: ConfigurationSnapshot) {
        general = EncodedGeneralSettings(snapshot.general)
        snapping = EncodedSnappingSettings(snapshot.snapping)
        hotkeyBindings = snapshot.hotkeySettings.bindings.map(EncodedHotkeyBinding.init)
        superMode = EncodedSuperMode(snapshot.hotkeySettings.superModeConfiguration)
        layouts = snapshot.layouts.map(EncodedLayout.init)
        displayProfiles = snapshot.displayProfiles.map(EncodedDisplayProfile.init)
        appRules = EncodedAppRules(snapshot.appRulePolicy)
    }
}

private struct EncodedGeneralSettings: Encodable {
    let launchesAtLogin: Bool
    init(_ settings: GeneralSettings) { launchesAtLogin = settings.launchesAtLogin }
}

private struct EncodedSnappingSettings: Encodable {
    let isEnabled: Bool
    let trigger: String
    let dwellMilliseconds: UInt32
    let showsPlacementPreview: Bool
    let usesReducedEffects: Bool
    init(_ settings: SnappingSettings) {
        isEnabled = settings.isEnabled
        trigger = settings.trigger.rawValue
        dwellMilliseconds = settings.dwellMilliseconds
        showsPlacementPreview = settings.showsPlacementPreview
        usesReducedEffects = settings.usesReducedEffects
    }
}

private struct EncodedAppRules: Encodable {
    let unmatched: String
    let rules: [EncodedAppRule]
    init(_ policy: AppRulePolicy) {
        unmatched = policy.unmatched.rawValue
        rules = policy.rules.map(EncodedAppRule.init)
    }
}

private struct EncodedAppRule: Encodable {
    let bundleIdentifier: String
    let decision: String
    init(_ rule: AppRule) {
        bundleIdentifier = rule.bundleIdentifier.value
        decision = rule.decision.rawValue
    }
}

private struct EncodedHotkeyBinding: Encodable {
    let id: UUID
    let hardwareKeyCode: UInt16
    let modifiers: UInt32
    let actionID: String

    init(_ binding: HotkeyBinding) {
        id = binding.id
        hardwareKeyCode = binding.hardwareKeyCode
        modifiers = binding.modifiers.rawValue
        actionID = binding.actionID.rawValue
    }
}

private struct EncodedSuperMode: Encodable {
    let prefix: EncodedPrefix
    let timeoutMilliseconds: UInt32
    let commandBindings: [EncodedSuperModeCommand]

    init(_ configuration: SuperModeConfiguration) {
        prefix = EncodedPrefix(configuration.prefix)
        timeoutMilliseconds = configuration.timeoutMilliseconds
        commandBindings = configuration.commandBindings.map(EncodedSuperModeCommand.init)
    }
}

private struct EncodedPrefix: Encodable {
    let hardwareKeyCode: UInt16
    let modifiers: UInt32

    init(_ prefix: HotkeyChord) {
        hardwareKeyCode = prefix.hardwareKeyCode
        modifiers = prefix.modifiers.rawValue
    }
}

private struct EncodedSuperModeCommand: Encodable {
    let hardwareKeyCodes: [UInt16]
    let actionID: String

    init(_ binding: SuperModeCommandBinding) {
        hardwareKeyCodes = binding.hardwareKeyCodes
        actionID = binding.actionID.rawValue
    }
}

private struct EncodedLayout: Encodable {
    let id: String
    let name: String
    let regions: [EncodedLayoutRegion]

    init(_ draft: LayoutDraft) {
        id = draft.id
        name = draft.name
        regions = draft.regions.map(EncodedLayoutRegion.init)
    }
}

private struct EncodedLayoutRegion: Encodable {
    let id: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ region: LayoutRegionDraft) {
        id = region.id.rawValue
        x = Double(region.normalizedFrame.minX)
        y = Double(region.normalizedFrame.minY)
        width = Double(region.normalizedFrame.width)
        height = Double(region.normalizedFrame.height)
    }
}

private struct EncodedDisplayProfile: Encodable {
    let stableDisplayID: String
    let gap: Double
    let layoutIDs: [String]

    init(_ profile: DisplayProfile) {
        stableDisplayID = profile.stableDisplayID.rawValue
        gap = profile.gap
        layoutIDs = profile.layoutIDs
    }
}

private enum ConfigurationJSONValue {
    case object([String: ConfigurationJSONValue])
    case array([ConfigurationJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

/// Small duplicate-key-rejecting JSON parser used before the schema decoder.
private struct ConfigurationJSONParser {
    private let data: Data
    private let bytes: [UInt8]
    private let maximumDepth: Int
    private var index = 0

    init(data: Data, maximumDepth: Int) {
        self.data = data
        bytes = Array(data)
        self.maximumDepth = maximumDepth
    }

    mutating func parse() throws -> ConfigurationJSONValue {
        skipWhitespace()
        let value = try parseValue(depth: 1)
        skipWhitespace()
        guard index == bytes.count else { throw ConfigurationDecodeFailure.invalidShape }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> ConfigurationJSONValue {
        guard depth <= maximumDepth, let byte = bytes[safe: index] else {
            throw ConfigurationDecodeFailure.invalidShape
        }
        switch byte {
        case 123:
            return try parseObject(depth: depth)
        case 91:
            return try parseArray(depth: depth)
        case 34:
            return .string(try parseString())
        case 45, 48...57:
            return .number(try parseNumber())
        case 116:
            try consume("true")
            return .bool(true)
        case 102:
            try consume("false")
            return .bool(false)
        case 110:
            try consume("null")
            return .null
        default:
            throw ConfigurationDecodeFailure.invalidShape
        }
    }

    private mutating func parseObject(depth: Int) throws -> ConfigurationJSONValue {
        index += 1
        skipWhitespace()
        var fields: [String: ConfigurationJSONValue] = [:]
        if consumeIf(125) { return .object(fields) }
        while true {
            guard bytes[safe: index] == 34 else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            let key = try parseString()
            guard fields[key] == nil else { throw ConfigurationDecodeFailure.invalidShape }
            skipWhitespace()
            try expect(58)
            skipWhitespace()
            fields[key] = try parseValue(depth: depth + 1)
            skipWhitespace()
            if consumeIf(125) { return .object(fields) }
            try expect(44)
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws -> ConfigurationJSONValue {
        index += 1
        skipWhitespace()
        var values: [ConfigurationJSONValue] = []
        if consumeIf(93) { return .array(values) }
        while true {
            values.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            if consumeIf(93) { return .array(values) }
            try expect(44)
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        try expect(34)
        while let byte = bytes[safe: index] {
            if byte == 34 {
                index += 1
                let token = data.subdata(in: start..<index)
                guard let decoded = try? JSONDecoder().decode(String.self, from: token) else {
                    throw ConfigurationDecodeFailure.invalidShape
                }
                return decoded
            }
            if byte == 92 {
                index += 1
                guard bytes[safe: index] != nil else {
                    throw ConfigurationDecodeFailure.invalidShape
                }
                index += 1
            } else {
                guard byte >= 32 else { throw ConfigurationDecodeFailure.invalidShape }
                index += 1
            }
        }
        throw ConfigurationDecodeFailure.invalidShape
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        _ = consumeIf(45)
        if consumeIf(48) {
            guard !(bytes[safe: index].map { (48...57).contains($0) } ?? false) else {
                throw ConfigurationDecodeFailure.invalidShape
            }
        } else {
            guard consumeDigit(from: 49...57) else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            while consumeDigit(from: 48...57) {}
        }
        if consumeIf(46) {
            guard consumeDigit(from: 48...57) else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            while consumeDigit(from: 48...57) {}
        }
        if bytes[safe: index] == 101 || bytes[safe: index] == 69 {
            index += 1
            _ = consumeIf(43) || consumeIf(45)
            guard consumeDigit(from: 48...57) else {
                throw ConfigurationDecodeFailure.invalidShape
            }
            while consumeDigit(from: 48...57) {}
        }
        guard let result = Double(String(decoding: bytes[start..<index], as: UTF8.self)),
              result.isFinite else {
            throw ConfigurationDecodeFailure.invalidShape
        }
        return result
    }

    private mutating func skipWhitespace() {
        while let byte = bytes[safe: index], [9, 10, 13, 32].contains(byte) {
            index += 1
        }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard consumeIf(byte) else { throw ConfigurationDecodeFailure.invalidShape }
    }

    private mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard bytes[safe: index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func consumeDigit(from range: ClosedRange<UInt8>) -> Bool {
        guard let byte = bytes[safe: index], range.contains(byte) else { return false }
        index += 1
        return true
    }

    private mutating func consume(_ literal: String) throws {
        for byte in literal.utf8 {
            try expect(byte)
        }
    }
}

private extension Array where Element == UInt8 {
    subscript(safe index: Int) -> UInt8? {
        indices.contains(index) ? self[index] : nil
    }
}
