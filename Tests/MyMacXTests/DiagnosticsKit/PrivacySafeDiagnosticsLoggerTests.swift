// MyMacX
// Copyright (C) 2026 NyugenNguyen
//
// This program is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the LICENSE file for details.

import ApplicationServices
import Foundation
import XCTest
@testable import MyMacX

final class PrivacySafeDiagnosticsLoggerTests: XCTestCase {
    func testRecordsStableCodeForEveryDiagnosticsFailure() {
        let cases: [(name: String, failure: DiagnosticsFailure, code: DiagnosticsCode)] = [
            ("accessibility permission required", .accessibility(.permissionRequired), .accessibilityPermissionRequired),
            ("accessibility invalid target", .accessibility(.invalidTarget), .accessibilityInvalidTarget),
            ("accessibility operation unsupported", .accessibility(.operationUnsupported), .accessibilityOperationUnsupported),
            ("accessibility invalid request", .accessibility(.invalidRequest), .accessibilityInvalidRequest),
            ("accessibility temporarily unavailable", .accessibility(.temporarilyUnavailable), .accessibilityTemporarilyUnavailable),
            ("accessibility value unavailable", .accessibility(.valueUnavailable), .accessibilityValueUnavailable),
            ("accessibility system failure", .accessibility(.systemFailure), .accessibilitySystemFailure),
            ("input monitoring permission required", .input(.monitoringPermissionRequired), .inputMonitoringPermissionRequired),
            ("input event tap disabled by user", .input(.eventTapDisabledByUser), .inputEventTapDisabledByUser),
            ("input event tap disabled by timeout", .input(.eventTapDisabledByTimeout), .inputEventTapDisabledByTimeout),
            ("input event tap unavailable", .input(.eventTapUnavailable), .inputEventTapUnavailable),
            ("input binding unsupported", .input(.bindingUnsupported), .inputBindingUnsupported),
            ("window accessibility permission required", .window(.accessibilityPermissionRequired), .accessibilityPermissionRequired),
            ("window no focused window", .window(.noFocusedWindow), .windowNoFocusedWindow),
            ("window unknown action", .window(.unknownAction(ActionID(rawValue: "not-emitted"))), .windowUnknownAction),
            ("window action disabled", .window(.actionDisabled(ActionID(rawValue: "not-emitted"))), .windowActionDisabled),
            ("window application excluded", .window(.applicationExcluded), .windowApplicationExcluded),
            ("window not movable", .window(.windowNotMovable), .windowNotMovable),
            ("window not resizable", .window(.windowNotResizable), .windowNotResizable),
            ("window disappeared", .window(.windowDisappeared), .windowDisappeared),
            ("window display unavailable", .window(.displayUnavailable), .windowDisplayUnavailable),
            ("window constraints unsatisfiable", .window(.constraintsUnsatisfiable), .windowConstraintsUnsatisfiable),
            ("window mutation rejected", .window(.mutationRejected), .windowMutationRejected),
            ("window verification timed out", .window(.verificationTimedOut), .windowVerificationTimedOut),
            ("window preview missing or expired", .window(.previewMissingOrExpired), .windowPreviewMissingOrExpired),
            ("window rollback incomplete", .window(.rollbackIncomplete), .windowRollbackIncomplete),
            ("persistence decode anomaly", .persistence(.decodeAnomaly), .persistenceDecodeAnomaly),
            ("persistence corrupt document", .persistence(.corruptDocument), .persistenceCorruptDocument),
            ("persistence unsupported future version", .persistence(.unsupportedFutureVersion), .persistenceUnsupportedFutureVersion),
        ]

        for testCase in cases {
            let writer = RecordingDiagnosticsWriter()
            let logger = PrivacySafeDiagnosticsLogger(writer: writer)

            logger.record(testCase.failure)

            XCTAssertEqual(writer.entries, [DiagnosticsLogEntry(code: testCase.code, severity: .error)], testCase.name)
        }
    }

    func testDiagnosticsCodesHaveStableRawValues() {
        let cases: [(DiagnosticsCode, String)] = [
            (.accessibilityPermissionRequired, "accessibility.permission-required"),
            (.accessibilityInvalidTarget, "accessibility.invalid-target"),
            (.accessibilityOperationUnsupported, "accessibility.operation-unsupported"),
            (.accessibilityInvalidRequest, "accessibility.invalid-request"),
            (.accessibilityTemporarilyUnavailable, "accessibility.temporarily-unavailable"),
            (.accessibilityValueUnavailable, "accessibility.value-unavailable"),
            (.accessibilitySystemFailure, "accessibility.system-failure"),
            (.inputMonitoringPermissionRequired, "input.monitoring-permission-required"),
            (.inputEventTapDisabledByUser, "input.event-tap-disabled-by-user"),
            (.inputEventTapDisabledByTimeout, "input.event-tap-disabled-by-timeout"),
            (.inputEventTapUnavailable, "input.event-tap-unavailable"),
            (.inputBindingUnsupported, "input.binding-unsupported"),
            (.windowNoFocusedWindow, "window.no-focused-window"),
            (.windowUnknownAction, "window.unknown-action"),
            (.windowActionDisabled, "window.action-disabled"),
            (.windowApplicationExcluded, "window.application-excluded"),
            (.windowNotMovable, "window.not-movable"),
            (.windowNotResizable, "window.not-resizable"),
            (.windowDisappeared, "window.disappeared"),
            (.windowDisplayUnavailable, "window.display-unavailable"),
            (.windowConstraintsUnsatisfiable, "window.constraints-unsatisfiable"),
            (.windowMutationRejected, "window.mutation-rejected"),
            (.windowVerificationTimedOut, "window.verification-timed-out"),
            (.windowPreviewMissingOrExpired, "window.preview-missing-or-expired"),
            (.windowRollbackIncomplete, "window.rollback-incomplete"),
            (.persistenceDecodeAnomaly, "persistence.decode-anomaly"),
            (.persistenceCorruptDocument, "persistence.corrupt-document"),
            (.persistenceUnsupportedFutureVersion, "persistence.unsupported-future-version"),
        ]

        for (code, rawValue) in cases {
            XCTAssertEqual(code.rawValue, rawValue)
        }
    }

    func testMapsEveryPublicAccessibilityErrorFamily() {
        let cases: [(AXError, AccessibilityFailure)] = [
            (.apiDisabled, .permissionRequired),
            (.invalidUIElement, .invalidTarget),
            (.invalidUIElementObserver, .invalidTarget),
            (.attributeUnsupported, .operationUnsupported),
            (.actionUnsupported, .operationUnsupported),
            (.notificationUnsupported, .operationUnsupported),
            (.parameterizedAttributeUnsupported, .operationUnsupported),
            (.notImplemented, .operationUnsupported),
            (.illegalArgument, .invalidRequest),
            (.cannotComplete, .temporarilyUnavailable),
            (.noValue, .valueUnavailable),
            (.success, .systemFailure),
            (.failure, .systemFailure),
            (.notificationAlreadyRegistered, .systemFailure),
            (.notificationNotRegistered, .systemFailure),
            (.notEnoughPrecision, .systemFailure),
        ]

        for (error, expectedFailure) in cases {
            XCTAssertEqual(AccessibilityFailure(axError: error), expectedFailure)
        }
    }

    func testRecordingWriterSerializesConcurrentWrites() {
        let writer = RecordingDiagnosticsWriter()
        let entry = DiagnosticsLogEntry(code: .accessibilitySystemFailure, severity: .error)
        let writeCount = 100

        DispatchQueue.concurrentPerform(iterations: writeCount) { _ in
            writer.write(entry)
        }

        XCTAssertEqual(writer.entries, Array(repeating: entry, count: writeCount))
    }
}

private final class RecordingDiagnosticsWriter: DiagnosticsLogWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEntries: [DiagnosticsLogEntry] = []

    var entries: [DiagnosticsLogEntry] {
        lock.withLock { storedEntries }
    }

    func write(_ entry: DiagnosticsLogEntry) {
        lock.withLock {
            storedEntries.append(entry)
        }
    }
}
