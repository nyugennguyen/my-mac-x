import Foundation

struct HotkeySettings: Equatable, Sendable {
    let bindings: [HotkeyBinding]
    let superModeConfiguration: SuperModeConfiguration

    init(
        bindings: [HotkeyBinding],
        superModeConfiguration: SuperModeConfiguration = .default
    ) {
        self.bindings = bindings
        self.superModeConfiguration = superModeConfiguration
    }
}

enum SettingsLoadResult: Equatable, Sendable {
    case loaded(HotkeySettings, origin: SettingsLoadOrigin)
}

enum SettingsLoadOrigin: Equatable, Sendable {
    case persisted(schemaVersion: UInt16)
    case migrated(fromVersion: UInt16, toVersion: UInt16)
    case defaults(reason: SettingsDefaultsReason)
}

enum SettingsDefaultsReason: Equatable, Sendable {
    case noDocument
    case corruptDocumentQuarantined
    case corruptDocumentCouldNotBeQuarantined
    case unsupportedFutureVersion
}

enum SettingsSaveResult: Equatable, Sendable {
    case saved(schemaVersion: UInt16)
    case failed(SettingsSaveFailure)
}

enum ConfigurationLoadResult: Equatable, Sendable {
    case loaded(ConfigurationSnapshot, origin: SettingsLoadOrigin)
}

enum SettingsSaveFailure: Equatable, Sendable {
    case structurallyInvalid
    case documentNotWritable
    case atomicReplacementFailed
    case recoveryRequired
}

protocol SettingsStoring: Actor {
    func load() async -> SettingsLoadResult
    func save(_ settings: HotkeySettings) async -> SettingsSaveResult
}

protocol SettingsDocumentPersisting: Sendable {
    func readDocument() async throws -> Data?
    func replaceDocumentAtomically(with data: Data) async throws
    func quarantineCorruptDocument() async throws
}

enum SettingsDocumentPersistenceError: Error, Sendable {
    case documentNotWritable
    case atomicReplacementFailed
    case quarantineFailed
    case readFailed
}

actor SettingsStore: SettingsStoring {
    private static let currentSchemaVersion = ConfigurationArchive.currentSchemaVersion
    private static let maximumDocumentSize = 256 * 1024
    private static let supportedModifierBits = HotkeyModifiers.command.rawValue
        | HotkeyModifiers.option.rawValue
        | HotkeyModifiers.control.rawValue
        | HotkeyModifiers.shift.rawValue

    private let documents: any SettingsDocumentPersisting
    private let actionRegistry: ActionRegistry
    private let superModeValidator: SuperModeConfigurationValidator
    private var saveIsRecoveryLocked = false

    init(documents: any SettingsDocumentPersisting, actionRegistry: ActionRegistry) {
        self.documents = documents
        self.actionRegistry = actionRegistry
        superModeValidator = SuperModeConfigurationValidator(actionRegistry: actionRegistry)
    }

    func load() async -> SettingsLoadResult {
        switch await loadConfiguration() {
        case let .loaded(snapshot, origin):
            return .loaded(snapshot.hotkeySettings, origin: origin)
        }
    }

    func loadConfiguration() async -> ConfigurationLoadResult {
        do {
            guard let data = try await documents.readDocument() else {
                return configurationDefaults(.noDocument)
            }
            guard data.count <= Self.maximumDocumentSize else {
                return await recoverConfigurationFromCorruptDocument()
            }

            let archive = ConfigurationArchive(actionRegistry: actionRegistry)
            switch archive.import(data) {
            case let .imported(snapshot, origin):
                switch origin {
                case let .current(version):
                    return .loaded(snapshot, origin: .persisted(schemaVersion: version))
                case let .migrated(fromVersion, toVersion):
                    do {
                        try await documents.replaceDocumentAtomically(with: archive.export(snapshot))
                    } catch {
                        // Isolate write-back errors: write failure must not quarantine valid source document
                    }
                    return .loaded(snapshot, origin: .migrated(fromVersion: fromVersion, toVersion: toVersion))
                }
            case .rejected(.unsupportedFutureVersion):
                saveIsRecoveryLocked = true
                return configurationDefaults(.unsupportedFutureVersion)
            case .rejected:
                break
            }

            switch try decode(data) {
            case let .current(settings):
                let snapshot = ConfigurationSnapshot(hotkeySettings: settings, layouts: [], displayProfiles: [])
                do {
                    try await documents.replaceDocumentAtomically(with: archive.export(snapshot))
                } catch {
                    // Isolate write-back errors
                }
                return .loaded(snapshot, origin: .migrated(fromVersion: 2, toVersion: Self.currentSchemaVersion))
            case let .migration(settings, fromVersion):
                let snapshot = ConfigurationSnapshot(hotkeySettings: settings, layouts: [], displayProfiles: [])
                do {
                    try await documents.replaceDocumentAtomically(with: archive.export(snapshot))
                } catch {
                    // Isolate write-back errors
                }
                return .loaded(
                    snapshot,
                    origin: .migrated(
                        fromVersion: fromVersion,
                        toVersion: Self.currentSchemaVersion
                    )
                )
            case .future:
                saveIsRecoveryLocked = true
                return configurationDefaults(.unsupportedFutureVersion)
            }
        } catch {
            return await recoverConfigurationFromCorruptDocument()
        }
    }

    func save(_ settings: HotkeySettings) async -> SettingsSaveResult {
        let snapshot: ConfigurationSnapshot
        switch await loadConfiguration() {
        case let .loaded(current, origin):
            if case .defaults(reason: .unsupportedFutureVersion) = origin {
                return .failed(.recoveryRequired)
            }
            snapshot = ConfigurationSnapshot(
                general: current.general,
                snapping: current.snapping,
                hotkeySettings: settings,
                layouts: current.layouts,
                displayProfiles: current.displayProfiles,
                appRulePolicy: current.appRulePolicy,
                edgeSnap: current.edgeSnap
            )
        }
        return await saveConfiguration(snapshot)
    }

    func saveConfiguration(_ snapshot: ConfigurationSnapshot) async -> SettingsSaveResult {
        guard !saveIsRecoveryLocked else { return .failed(.recoveryRequired) }
        do {
            let data = try ConfigurationArchive(actionRegistry: actionRegistry).export(snapshot)
            try await documents.replaceDocumentAtomically(with: data)
            return .saved(schemaVersion: Self.currentSchemaVersion)
        } catch ConfigurationExportFailure.invalidConfiguration {
            return .failed(.structurallyInvalid)
        } catch SettingsDocumentPersistenceError.documentNotWritable {
            return .failed(.documentNotWritable)
        } catch {
            return .failed(.atomicReplacementFailed)
        }
    }

    private func defaults(_ reason: SettingsDefaultsReason) -> SettingsLoadResult {
        .loaded(HotkeySettings(bindings: []), origin: .defaults(reason: reason))
    }

    private func configurationDefaults(_ reason: SettingsDefaultsReason) -> ConfigurationLoadResult {
        .loaded(
            ConfigurationSnapshot(hotkeySettings: HotkeySettings(bindings: []), layouts: [], displayProfiles: []),
            origin: .defaults(reason: reason)
        )
    }

    private func recoverFromCorruptDocument() async -> SettingsLoadResult {
        do {
            try await documents.quarantineCorruptDocument()
            saveIsRecoveryLocked = false
            return defaults(.corruptDocumentQuarantined)
        } catch {
            saveIsRecoveryLocked = true
            return defaults(.corruptDocumentCouldNotBeQuarantined)
        }
    }

    private func recoverConfigurationFromCorruptDocument() async -> ConfigurationLoadResult {
        do {
            try await documents.quarantineCorruptDocument()
            saveIsRecoveryLocked = false
            return configurationDefaults(.corruptDocumentQuarantined)
        } catch {
            saveIsRecoveryLocked = true
            return configurationDefaults(.corruptDocumentCouldNotBeQuarantined)
        }
    }

    private enum DecodedDocument {
        case migration(HotkeySettings, fromVersion: UInt16)
        case current(HotkeySettings)
        case future
    }

    private func decode(_ data: Data) throws -> DecodedDocument {
        var parser = StrictJSONParser(data: data, maximumDepth: 6)
        let root = try parser.parse()
        guard case let .object(fields) = root else {
            throw SettingsDecodingError.invalidShape
        }

        if let schemaValue = fields["schemaVersion"] {
            guard let version = unsignedInteger(schemaValue, as: UInt16.self) else {
                throw SettingsDecodingError.invalidShape
            }
            if version > Self.currentSchemaVersion { return .future }

            switch version {
            case 1:
                guard Set(fields.keys) == ["schemaVersion", "hotkeyBindings"],
                      let bindings = try bindings(
                          from: fields["hotkeyBindings"],
                          keyCodeField: "hardwareKeyCode"
                      ) else {
                    throw SettingsDecodingError.invalidShape
                }
                let settings = HotkeySettings(bindings: bindings)
                guard isStructurallyValid(settings) else {
                    throw SettingsDecodingError.invalidShape
                }
                return .migration(settings, fromVersion: 1)
            case 2:
                guard Set(fields.keys) == [
                    "schemaVersion",
                    "hotkeyBindings",
                    "superMode",
                ],
                let bindings = try bindings(
                    from: fields["hotkeyBindings"],
                    keyCodeField: "hardwareKeyCode"
                ),
                let configuration = try superModeConfiguration(from: fields["superMode"])
                else {
                    throw SettingsDecodingError.invalidShape
                }
                let settings = HotkeySettings(
                    bindings: bindings,
                    superModeConfiguration: configuration
                )
                guard isStructurallyValid(settings) else {
                    throw SettingsDecodingError.invalidShape
                }
                return .current(settings)
            default:
                throw SettingsDecodingError.invalidShape
            }
        }

        guard Set(fields.keys) == ["bindings"],
              let bindings = try bindings(from: fields["bindings"], keyCodeField: "keyCode")
        else {
            throw SettingsDecodingError.invalidShape
        }
        let settings = HotkeySettings(bindings: bindings)
        guard isStructurallyValid(settings) else {
            throw SettingsDecodingError.invalidShape
        }
        return .migration(settings, fromVersion: 0)
    }

    private func bindings(
        from value: StrictJSONValue?,
        keyCodeField: String
    ) throws -> [HotkeyBinding]? {
        guard case let .array(items)? = value else { return nil }
        var bindings: [HotkeyBinding] = []
        for item in items {
            guard case let .object(fields) = item,
                  Set(fields.keys) == ["id", keyCodeField, "modifiers", "actionID"],
                  case let .string(idText)? = fields["id"],
                  let id = UUID(uuidString: idText),
                  let keyCode = unsignedInteger(fields[keyCodeField], as: UInt16.self),
                  let modifiers = unsignedInteger(fields["modifiers"], as: UInt32.self),
                  case let .string(actionText)? = fields["actionID"],
                  !actionText.isEmpty else {
                throw SettingsDecodingError.invalidShape
            }
            bindings.append(
                HotkeyBinding(
                    id: id,
                    hardwareKeyCode: keyCode,
                    modifiers: HotkeyModifiers(rawValue: modifiers),
                    actionID: ActionID(rawValue: actionText)
                )
            )
        }
        return bindings
    }

    private func superModeConfiguration(
        from value: StrictJSONValue?
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
              let timeoutMilliseconds = unsignedInteger(
                  fields["timeoutMilliseconds"],
                  as: UInt32.self
              ),
              case let .array(commandItems)? = fields["commandBindings"] else {
            return nil
        }

        var commandBindings: [SuperModeCommandBinding] = []
        for item in commandItems {
            guard case let .object(commandFields) = item,
                  Set(commandFields.keys) == ["hardwareKeyCodes", "actionID"],
                  case let .array(keyCodeValues)? = commandFields["hardwareKeyCodes"],
                  case let .string(actionText)? = commandFields["actionID"],
                  !actionText.isEmpty else {
                throw SettingsDecodingError.invalidShape
            }
            var hardwareKeyCodes: [UInt16] = []
            for keyCodeValue in keyCodeValues {
                guard let hardwareKeyCode = unsignedInteger(
                    keyCodeValue,
                    as: UInt16.self
                ) else {
                    throw SettingsDecodingError.invalidShape
                }
                hardwareKeyCodes.append(hardwareKeyCode)
            }
            commandBindings.append(
                SuperModeCommandBinding(
                    hardwareKeyCodes: hardwareKeyCodes,
                    actionID: ActionID(rawValue: actionText)
                )
            )
        }

        return SuperModeConfiguration(
            prefix: HotkeyChord(
                hardwareKeyCode: prefixKeyCode,
                modifiers: HotkeyModifiers(rawValue: prefixModifiers)
            ),
            timeoutMilliseconds: timeoutMilliseconds,
            commandBindings: commandBindings
        )
    }

    private func unsignedInteger<T: FixedWidthInteger & UnsignedInteger>(
        _ value: StrictJSONValue?,
        as type: T.Type
    ) -> T? {
        guard case let .number(number)? = value,
              number.rounded() == number,
              number >= 0,
              number <= Double(T.max) else {
            return nil
        }
        return T(number)
    }

    private func isStructurallyValid(_ settings: HotkeySettings) -> Bool {
        let bindings = settings.bindings
        guard Set(bindings.map(\.id)).count == bindings.count,
              bindings.allSatisfy({ binding in
                  binding.modifiers.rawValue & ~Self.supportedModifierBits == 0
                      && !binding.actionID.rawValue.isEmpty
                      && actionRegistry.action(for: binding.actionID) != nil
              }) else {
            return false
        }
        guard case .valid = superModeValidator.validate(
            settings.superModeConfiguration,
            hotkeyBindings: bindings
        ) else {
            return false
        }
        return true
    }

}

private struct V2Document: Encodable {
    let schemaVersion: UInt16
    let hotkeyBindings: [V2HotkeyBinding]
    let superMode: V2SuperModeConfiguration
}

private struct V2HotkeyBinding: Encodable {
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

private struct V2SuperModeConfiguration: Encodable {
    let prefix: V2Prefix
    let timeoutMilliseconds: UInt32
    let commandBindings: [V2SuperModeCommandBinding]

    init(_ configuration: SuperModeConfiguration) {
        prefix = V2Prefix(configuration.prefix)
        timeoutMilliseconds = configuration.timeoutMilliseconds
        commandBindings = configuration.commandBindings.map(V2SuperModeCommandBinding.init)
    }
}

private struct V2Prefix: Encodable {
    let hardwareKeyCode: UInt16
    let modifiers: UInt32

    init(_ prefix: HotkeyChord) {
        hardwareKeyCode = prefix.hardwareKeyCode
        modifiers = prefix.modifiers.rawValue
    }
}

private struct V2SuperModeCommandBinding: Encodable {
    let hardwareKeyCodes: [UInt16]
    let actionID: String

    init(_ binding: SuperModeCommandBinding) {
        hardwareKeyCodes = binding.hardwareKeyCodes
        actionID = binding.actionID.rawValue
    }
}

enum SettingsDecodingError: Error { case invalidShape }
