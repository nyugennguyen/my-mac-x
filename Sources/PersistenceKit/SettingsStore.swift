import Foundation

struct HotkeySettings: Equatable, Sendable {
    let bindings: [HotkeyBinding]

    init(bindings: [HotkeyBinding]) {
        self.bindings = bindings
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
    private static let currentSchemaVersion: UInt16 = 1
    private static let maximumDocumentSize = 256 * 1024
    private static let supportedModifierBits = HotkeyModifiers.command.rawValue
        | HotkeyModifiers.option.rawValue
        | HotkeyModifiers.control.rawValue
        | HotkeyModifiers.shift.rawValue

    private let documents: any SettingsDocumentPersisting
    private let actionRegistry: ActionRegistry
    private var saveIsRecoveryLocked = false

    init(documents: any SettingsDocumentPersisting, actionRegistry: ActionRegistry) {
        self.documents = documents
        self.actionRegistry = actionRegistry
    }

    func load() async -> SettingsLoadResult {
        do {
            guard let data = try await documents.readDocument() else {
                return defaults(.noDocument)
            }
            guard data.count <= Self.maximumDocumentSize else {
                return await recoverFromCorruptDocument()
            }

            switch try decode(data) {
            case let .current(settings):
                return .loaded(settings, origin: .persisted(schemaVersion: Self.currentSchemaVersion))
            case let .legacy(settings):
                do {
                    try await documents.replaceDocumentAtomically(with: try encodeV1(settings))
                    return .loaded(settings, origin: .migrated(fromVersion: 0, toVersion: 1))
                } catch {
                    return await recoverFromCorruptDocument()
                }
            case .future:
                saveIsRecoveryLocked = true
                return defaults(.unsupportedFutureVersion)
            }
        } catch {
            return await recoverFromCorruptDocument()
        }
    }

    func save(_ settings: HotkeySettings) async -> SettingsSaveResult {
        guard !saveIsRecoveryLocked else { return .failed(.recoveryRequired) }
        guard isStructurallyValid(settings.bindings) else { return .failed(.structurallyInvalid) }
        do {
            try await documents.replaceDocumentAtomically(with: try encodeV1(settings))
            return .saved(schemaVersion: Self.currentSchemaVersion)
        } catch SettingsDocumentPersistenceError.documentNotWritable {
            return .failed(.documentNotWritable)
        } catch {
            return .failed(.atomicReplacementFailed)
        }
    }

    private func defaults(_ reason: SettingsDefaultsReason) -> SettingsLoadResult {
        .loaded(HotkeySettings(bindings: []), origin: .defaults(reason: reason))
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

    private enum DecodedDocument {
        case legacy(HotkeySettings)
        case current(HotkeySettings)
        case future
    }

    private func decode(_ data: Data) throws -> DecodedDocument {
        var parser = StrictJSONParser(data: data, maximumDepth: 4)
        let root = try parser.parse()
        guard case let .object(fields) = root else { throw SettingsDecodingError.invalidShape }

        if let schemaValue = fields["schemaVersion"] {
            guard case let .number(version) = schemaValue,
                  version.rounded() == version,
                  version >= 0,
                  version <= Double(UInt16.max) else { throw SettingsDecodingError.invalidShape }
            if UInt16(version) > Self.currentSchemaVersion { return .future }
            guard UInt16(version) == Self.currentSchemaVersion,
                  Set(fields.keys) == ["schemaVersion", "hotkeyBindings"],
                  let bindings = try bindings(from: fields["hotkeyBindings"], v0: false) else {
                throw SettingsDecodingError.invalidShape
            }
            return .current(HotkeySettings(bindings: bindings))
        }

        guard Set(fields.keys) == ["bindings"],
              let bindings = try bindings(from: fields["bindings"], v0: true) else {
            throw SettingsDecodingError.invalidShape
        }
        return .legacy(HotkeySettings(bindings: bindings))
    }

    private func bindings(from value: StrictJSONValue?, v0: Bool) throws -> [HotkeyBinding]? {
        guard case let .array(items)? = value else { return nil }
        var bindings: [HotkeyBinding] = []
        for item in items {
            guard case let .object(fields) = item,
                  Set(fields.keys) == (v0 ? ["id", "keyCode", "modifiers", "actionID"] : ["id", "hardwareKeyCode", "modifiers", "actionID"]),
                  case let .string(idText)? = fields["id"], let id = UUID(uuidString: idText),
                  case let .number(keyCode)? = fields[v0 ? "keyCode" : "hardwareKeyCode"],
                  keyCode.rounded() == keyCode, keyCode >= 0, keyCode <= Double(UInt16.max),
                  case let .number(modifiers)? = fields["modifiers"],
                  modifiers.rounded() == modifiers, modifiers >= 0, modifiers <= Double(UInt32.max),
                  case let .string(actionText)? = fields["actionID"], !actionText.isEmpty else {
                throw SettingsDecodingError.invalidShape
            }
            bindings.append(HotkeyBinding(
                id: id,
                hardwareKeyCode: UInt16(keyCode),
                modifiers: HotkeyModifiers(rawValue: UInt32(modifiers)),
                actionID: ActionID(rawValue: actionText)
            ))
        }
        guard isStructurallyValid(bindings) else { throw SettingsDecodingError.invalidShape }
        return bindings
    }

    private func isStructurallyValid(_ bindings: [HotkeyBinding]) -> Bool {
        Set(bindings.map(\.id)).count == bindings.count
            && bindings.allSatisfy { binding in
                binding.modifiers.rawValue & ~Self.supportedModifierBits == 0
                    && !binding.actionID.rawValue.isEmpty
                    && actionRegistry.action(for: binding.actionID) != nil
            }
    }

    private func encodeV1(_ settings: HotkeySettings) throws -> Data {
        try JSONEncoder().encode(V1Document(
            schemaVersion: Self.currentSchemaVersion,
            hotkeyBindings: settings.bindings.map(V1Binding.init)
        ))
    }
}

private struct V1Document: Encodable {
    let schemaVersion: UInt16
    let hotkeyBindings: [V1Binding]
}

private struct V1Binding: Encodable {
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

enum SettingsDecodingError: Error { case invalidShape }
