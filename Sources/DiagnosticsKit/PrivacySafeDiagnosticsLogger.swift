import ApplicationServices
import Foundation
import OSLog

/// The fixed, non-content-bearing diagnostic events allowed to leave feature modules.
///
/// This type deliberately has no free-form text, window metadata, input data, or image
/// payloads. Callers can record only one of the declared failure categories.
public enum DiagnosticsFailure: Error, Equatable, Sendable {
    case accessibility(AccessibilityFailure)
    case input(InputFailure)
    case window(WindowActionFailure)
}

/// Stable Accessibility failures that may be shown to callers or recorded in diagnostics.
public enum AccessibilityFailure: Error, Equatable, Sendable {
    case permissionRequired
    case invalidTarget
    case operationUnsupported
    case invalidRequest
    case temporarilyUnavailable
    case valueUnavailable
    case systemFailure

    /// Converts a public Accessibility API error into the application taxonomy.
    /// No OS-provided text is retained or emitted.
    public init(axError: AXError) {
        switch axError {
        case .apiDisabled:
            self = .permissionRequired
        case .invalidUIElement, .invalidUIElementObserver:
            self = .invalidTarget
        case .attributeUnsupported, .actionUnsupported, .notificationUnsupported,
                .parameterizedAttributeUnsupported, .notImplemented:
            self = .operationUnsupported
        case .illegalArgument:
            self = .invalidRequest
        case .cannotComplete:
            self = .temporarilyUnavailable
        case .noValue:
            self = .valueUnavailable
        case .success, .failure, .notificationAlreadyRegistered, .notificationNotRegistered,
                .notEnoughPrecision:
            self = .systemFailure
        @unknown default:
            self = .systemFailure
        }
    }
}

/// Stable failures from the global-input path. They intentionally contain no key data.
public enum InputFailure: Error, Equatable, Sendable {
    case monitoringPermissionRequired
    case eventTapDisabledByUser
    case eventTapDisabledByTimeout
    case eventTapUnavailable
    case bindingUnsupported
}

/// Domain failures that Window Action callers can render without receiving AX objects.
public enum WindowActionFailure: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case noFocusedWindow
    case unknownAction(ActionID)
    case actionDisabled(ActionID)
    case windowNotMovable
    case windowNotResizable
    case windowDisappeared
    case displayUnavailable
    case constraintsUnsatisfiable
    case mutationRejected
    case verificationTimedOut
    case previewMissingOrExpired
    case rollbackIncomplete
}

/// The complete allowlist of codes that may be emitted by `PrivacySafeDiagnosticsLogger`.
public enum DiagnosticsCode: String, Equatable, Sendable {
    case accessibilityPermissionRequired = "accessibility.permission-required"
    case accessibilityInvalidTarget = "accessibility.invalid-target"
    case accessibilityOperationUnsupported = "accessibility.operation-unsupported"
    case accessibilityInvalidRequest = "accessibility.invalid-request"
    case accessibilityTemporarilyUnavailable = "accessibility.temporarily-unavailable"
    case accessibilityValueUnavailable = "accessibility.value-unavailable"
    case accessibilitySystemFailure = "accessibility.system-failure"

    case inputMonitoringPermissionRequired = "input.monitoring-permission-required"
    case inputEventTapDisabledByUser = "input.event-tap-disabled-by-user"
    case inputEventTapDisabledByTimeout = "input.event-tap-disabled-by-timeout"
    case inputEventTapUnavailable = "input.event-tap-unavailable"
    case inputBindingUnsupported = "input.binding-unsupported"

    case windowNoFocusedWindow = "window.no-focused-window"
    case windowUnknownAction = "window.unknown-action"
    case windowActionDisabled = "window.action-disabled"
    case windowNotMovable = "window.not-movable"
    case windowNotResizable = "window.not-resizable"
    case windowDisappeared = "window.disappeared"
    case windowDisplayUnavailable = "window.display-unavailable"
    case windowConstraintsUnsatisfiable = "window.constraints-unsatisfiable"
    case windowMutationRejected = "window.mutation-rejected"
    case windowVerificationTimedOut = "window.verification-timed-out"
    case windowPreviewMissingOrExpired = "window.preview-missing-or-expired"
    case windowRollbackIncomplete = "window.rollback-incomplete"
}

public enum DiagnosticsSeverity: Equatable, Sendable {
    case error
}

/// A privacy-safe log record. It can carry only an allowlisted code and severity.
public struct DiagnosticsLogEntry: Equatable, Sendable {
    public let code: DiagnosticsCode
    public let severity: DiagnosticsSeverity

    public init(code: DiagnosticsCode, severity: DiagnosticsSeverity) {
        self.code = code
        self.severity = severity
    }
}

/// Adapter seam for writing an already-redacted diagnostics entry.
public protocol DiagnosticsLogWriting: Sendable {
    func write(_ entry: DiagnosticsLogEntry)
}

/// Maps app failures to allowlisted, content-free diagnostics records.
public struct PrivacySafeDiagnosticsLogger: Sendable {
    private let writer: any DiagnosticsLogWriting

    public init() {
        self.writer = SystemDiagnosticsLogWriter()
    }

    public init(writer: any DiagnosticsLogWriting) {
        self.writer = writer
    }

    public func record(_ failure: DiagnosticsFailure) {
        writer.write(DiagnosticsLogEntry(code: failure.diagnosticsCode, severity: .error))
    }
}

private extension DiagnosticsFailure {
    var diagnosticsCode: DiagnosticsCode {
        switch self {
        case .accessibility(let failure):
            switch failure {
            case .permissionRequired: .accessibilityPermissionRequired
            case .invalidTarget: .accessibilityInvalidTarget
            case .operationUnsupported: .accessibilityOperationUnsupported
            case .invalidRequest: .accessibilityInvalidRequest
            case .temporarilyUnavailable: .accessibilityTemporarilyUnavailable
            case .valueUnavailable: .accessibilityValueUnavailable
            case .systemFailure: .accessibilitySystemFailure
            }
        case .input(let failure):
            switch failure {
            case .monitoringPermissionRequired: .inputMonitoringPermissionRequired
            case .eventTapDisabledByUser: .inputEventTapDisabledByUser
            case .eventTapDisabledByTimeout: .inputEventTapDisabledByTimeout
            case .eventTapUnavailable: .inputEventTapUnavailable
            case .bindingUnsupported: .inputBindingUnsupported
            }
        case .window(let failure):
            switch failure {
            case .accessibilityPermissionRequired: .accessibilityPermissionRequired
            case .noFocusedWindow: .windowNoFocusedWindow
            case .unknownAction: .windowUnknownAction
            case .actionDisabled: .windowActionDisabled
            case .windowNotMovable: .windowNotMovable
            case .windowNotResizable: .windowNotResizable
            case .windowDisappeared: .windowDisappeared
            case .displayUnavailable: .windowDisplayUnavailable
            case .constraintsUnsatisfiable: .windowConstraintsUnsatisfiable
            case .mutationRejected: .windowMutationRejected
            case .verificationTimedOut: .windowVerificationTimedOut
            case .previewMissingOrExpired: .windowPreviewMissingOrExpired
            case .rollbackIncomplete: .windowRollbackIncomplete
            }
        }
    }
}

private struct SystemDiagnosticsLogWriter: DiagnosticsLogWriting {
    private let logger = Logger(subsystem: "dev.mymacx.app", category: "diagnostics")

    func write(_ entry: DiagnosticsLogEntry) {
        logger.error("diagnostic_code=\(entry.code.rawValue, privacy: .public)")
    }
}
