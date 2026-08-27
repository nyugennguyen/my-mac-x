import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import MyMacX

/// Human-operated W2-12 harness for one known Electron application's focused window.
///
/// This support code deliberately stays in the test target. It composes the production
/// `WindowActionEngine` and crosses the Window Action Module only through
/// `WindowActionPerforming.perform(_:)`. Its additional AX reads are an independent,
/// public-API guard around the exact application/window selected by the human tester.
/// They never inspect a title, document name, screenshot, or application content.
public struct OpenChamberWindowActionHarness {
    static let requiredConfirmation = "RUN_OPENCHAMBER_W2_12"
    static let requiredG2Confirmation = "RUN_OPENCHAMBER_G2_MULTI_DISPLAY"

    private static let confirmationEnvironmentKey =
        "MYMACX_W2_12_OPENCHAMBER_CONFIRMATION"
    private static let focusTimeoutEnvironmentKey =
        "MYMACX_W2_12_OPENCHAMBER_FOCUS_TIMEOUT_SECONDS"
    private static let g2ConfirmationEnvironmentKey =
        "MYMACX_G2_MULTI_DISPLAY_CONFIRMATION"
    private static let expectedBundleIdentifier = "dev.openchamber.desktop"
    private static let actionCount = 100
    private static let maximumFocusTimeout: Duration = .seconds(60)
    private static let defaultFocusTimeout: Duration = .seconds(30)
    private static let maximumActionDuration: Duration = .seconds(15)
    private static let maximumTotalDuration: Duration = .seconds(25 * 60)
    private static let maximumResidentGrowthBytes: UInt64 = 64 * 1_024 * 1_024
    private static let frameTolerance: CGFloat = 0.5

    private let windowActions: any WindowActionPerforming
    private let environment: [String: String]

    public init() {
        windowActions = WindowActionEngine()
        environment = ProcessInfo.processInfo.environment
    }

    public init(
        windowActions: any WindowActionPerforming,
        environment: [String: String]
    ) {
        self.windowActions = windowActions
        self.environment = environment
    }

    /// The XCTest is skipped unless this exact value is supplied by a human-run command.
    static var isExplicitlyArmed: Bool {
        ProcessInfo.processInfo.environment[confirmationEnvironmentKey] == requiredConfirmation
    }

    static var isG2ExplicitlyArmed: Bool {
        ProcessInfo.processInfo.environment[g2ConfirmationEnvironmentKey]
            == requiredG2Confirmation
    }

    /// Exercises physical Display selection through the production Window Action Interface.
    public func runG2PhysicalMultiDisplay() async throws -> G2Report {
        guard environment[Self.g2ConfirmationEnvironmentKey] == Self.requiredG2Confirmation else {
            throw HarnessError.notExplicitlyArmed
        }
        let displays = try PhysicalDisplays.capture()
        guard displays.count >= 2 else {
            throw HarnessError.multipleDisplaysRequired(actual: displays.count)
        }

        let target = try await waitForPinnedTarget(within: try configuredFocusTimeout())
        let originalFrame = try target.readFrame()
        let sourceDisplayID = try displays.displayID(containing: originalFrame)
        var didVerifyFinalRecovery = false
        defer {
            if !didVerifyFinalRecovery {
                _ = try? target.restore(originalFrame, tolerance: Self.frameTolerance)
            }
        }

        _ = try await performVerified(.leftHalf, target: target, step: "source Snap")
        guard try displays.displayID(containing: target.readFrame()) == sourceDisplayID else {
            throw HarnessError.unexpectedDisplay(step: "source Snap")
        }

        let moveNext = try await performVerified(
            .moveDisplayNext,
            target: target,
            step: "Move Next Display"
        )
        let nextDisplayID = try displays.displayID(containing: target.readFrame())
        guard nextDisplayID != sourceDisplayID else {
            throw HarnessError.windowDidNotChangeDisplay(step: "Move Next Display")
        }
        guard let moveUndoToken = moveNext.undoToken else {
            throw HarnessError.missingUndoToken
        }

        try target.requireStillFocused()
        let undoResult = await windowActions.perform(
            .undo(token: moveUndoToken, source: .settingsTest)
        )
        guard case .succeeded = undoResult.disposition,
              case .undone = undoResult.effect else {
            throw HarnessError.unverifiedUndoResult
        }
        try target.requireStillFocused()
        let undoDisplayID = try displays.displayID(containing: target.readFrame())
        guard undoDisplayID == sourceDisplayID else {
            throw HarnessError.unexpectedDisplay(step: "Undo Move Next")
        }

        _ = try await performVerified(.moveDisplayNext, target: target, step: "second Move Next")
        guard try displays.displayID(containing: target.readFrame()) == nextDisplayID else {
            throw HarnessError.unexpectedDisplay(step: "second Move Next")
        }

        _ = try await performVerified(
            .moveDisplayPrevious,
            target: target,
            step: "Move Previous Display"
        )
        let returnedDisplayID = try displays.displayID(containing: target.readFrame())
        guard returnedDisplayID == sourceDisplayID else {
            throw HarnessError.unexpectedDisplay(step: "Move Previous Display")
        }

        let restoredFrame = try target.restore(originalFrame, tolerance: Self.frameTolerance)
        didVerifyFinalRecovery = true
        return G2Report(
            displayCount: displays.count,
            sourceDisplayID: sourceDisplayID,
            destinationDisplayID: nextDisplayID,
            undoReturnedToSource: undoDisplayID == sourceDisplayID,
            previousReturnedToSource: returnedDisplayID == sourceDisplayID,
            originalFrameRestored: framesMatch(
                restoredFrame,
                originalFrame,
                tolerance: Self.frameTolerance
            )
        )
    }

    /// Runs exactly one serial, target-pinned sequence. The caller must focus OpenChamber
    /// while the bounded read-only wait is active; no system permission prompt is requested.
    public func run() async throws -> Report {
        try requireExplicitConfirmation()
        let focusTimeout = try configuredFocusTimeout()
        let target = try await waitForPinnedTarget(within: focusTimeout)
        let originalFrame = try target.readFrame()
        let baselineResidentBytes = ResidentMemory.currentBytes()
        let clock = ContinuousClock()
        let startedAt = clock.now
        var didVerifyFinalRecovery = false

        // This is intentionally synchronous public AX recovery so it can run from `defer`
        // after every normal failure/cancellation path. The final normal recovery below also
        // verifies the frame; a failed final verification leaves this best-effort retry armed.
        defer {
            if !didVerifyFinalRecovery {
                _ = try? target.restore(originalFrame, tolerance: Self.frameTolerance)
            }
        }

        var slowestAction = Duration.zero
        var verifiedReadBacks = 0

        for index in 0..<Self.actionCount {
            try target.requireStillFocused()
            let action = Self.snapActions[index % Self.snapActions.count]
            let actionStartedAt = clock.now
            let result = await windowActions.perform(
                .commit(action: action, source: .settingsTest)
            )
            let actionDuration = actionStartedAt.duration(to: clock.now)
            slowestAction = max(slowestAction, actionDuration)
            guard actionDuration <= Self.maximumActionDuration else {
                throw HarnessError.actionDurationExceeded(index: index, duration: actionDuration)
            }

            try requireVerifiedCommit(result, at: index)
            // `WindowMutationModule` already verifies its own read-back before reporting a
            // committed effect. This independent raw-AX read confirms that the same pinned
            // public AX window remains readable after every one of the 100 calls.
            _ = try target.readFrame()
            try target.requireStillFocused()
            verifiedReadBacks += 1
        }

        let totalDuration = startedAt.duration(to: clock.now)
        guard totalDuration <= Self.maximumTotalDuration else {
            throw HarnessError.totalDurationExceeded(totalDuration)
        }

        let finalFrame = try target.restore(originalFrame, tolerance: Self.frameTolerance)
        didVerifyFinalRecovery = true

        let finalResidentBytes = ResidentMemory.currentBytes()
        let residentGrowthBytes = Self.residentGrowth(
            baseline: baselineResidentBytes,
            final: finalResidentBytes
        )
        if let residentGrowthBytes,
           residentGrowthBytes > Self.maximumResidentGrowthBytes {
            throw HarnessError.residentMemoryGrowthExceeded(residentGrowthBytes)
        }

        return Report(
            bundleIdentifier: Self.expectedBundleIdentifier,
            processIdentifier: target.processIdentifier,
            actionCount: Self.actionCount,
            verifiedReadBackCount: verifiedReadBacks,
            totalDuration: totalDuration,
            slowestActionDuration: slowestAction,
            residentBytesBefore: baselineResidentBytes,
            residentBytesAfter: finalResidentBytes,
            residentGrowthBytes: residentGrowthBytes,
            originalFrameRestored: framesMatch(
                finalFrame,
                originalFrame,
                tolerance: Self.frameTolerance
            )
        )
    }

    private func requireExplicitConfirmation() throws {
        guard environment[Self.confirmationEnvironmentKey] == Self.requiredConfirmation else {
            throw HarnessError.notExplicitlyArmed
        }
    }

    private func configuredFocusTimeout() throws -> Duration {
        guard let configured = environment[Self.focusTimeoutEnvironmentKey] else {
            return Self.defaultFocusTimeout
        }
        guard let seconds = Double(configured), seconds > 0, seconds <= 60 else {
            throw HarnessError.invalidFocusTimeout
        }
        return min(.seconds(seconds), Self.maximumFocusTimeout)
    }

    private func waitForPinnedTarget(within timeout: Duration) async throws -> PinnedTarget {
        guard AXIsProcessTrusted() else {
            throw HarnessError.accessibilityNotTrusted
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            if let target = try PinnedTarget.capture(
                expectedBundleIdentifier: Self.expectedBundleIdentifier
            ) {
                return target
            }
            try await Task.sleep(for: .milliseconds(100))
        } while clock.now < deadline

        throw HarnessError.openChamberWasNotFocused
    }

    private func requireVerifiedCommit(
        _ result: WindowActionResult,
        at index: Int
    ) throws {
        guard case .succeeded = result.disposition,
              case .committed = result.effect
        else {
            throw HarnessError.unverifiedActionResult(index: index)
        }
    }

    private func performVerified(
        _ action: ActionID,
        target: PinnedTarget,
        step: String
    ) async throws -> WindowActionResult {
        try target.requireStillFocused()
        let result = await windowActions.perform(.commit(action: action, source: .settingsTest))
        guard case .succeeded = result.disposition,
              case .committed = result.effect else {
            throw HarnessError.unverifiedG2ActionResult(step: step)
        }
        _ = try target.readFrame()
        try target.requireStillFocused()
        return result
    }

    private static func residentGrowth(baseline: UInt64?, final: UInt64?) -> UInt64? {
        guard let baseline, let final else { return nil }
        return final >= baseline ? final - baseline : 0
    }

    private static let snapActions: [ActionID] = [
        .maximize,
        .leftHalf,
        .rightHalf,
        .topHalf,
        .bottomHalf,
        .topLeftQuarter,
        .topRightQuarter,
        .bottomLeftQuarter,
        .bottomRightQuarter,
    ]
}

extension OpenChamberWindowActionHarness {
    public struct G2Report: Sendable {
        public let displayCount: Int
        public let sourceDisplayID: CGDirectDisplayID
        public let destinationDisplayID: CGDirectDisplayID
        public let undoReturnedToSource: Bool
        public let previousReturnedToSource: Bool
        public let originalFrameRestored: Bool
    }

    public struct Report: Sendable {
        public let bundleIdentifier: String
        public let processIdentifier: pid_t
        public let actionCount: Int
        public let verifiedReadBackCount: Int
        public let totalDuration: Duration
        public let slowestActionDuration: Duration
        public let residentBytesBefore: UInt64?
        public let residentBytesAfter: UInt64?
        public let residentGrowthBytes: UInt64?
        public let originalFrameRestored: Bool
    }

    enum HarnessError: Error, LocalizedError {
        case notExplicitlyArmed
        case invalidFocusTimeout
        case accessibilityNotTrusted
        case openChamberWasNotFocused
        case targetChanged
        case focusedWindowUnavailable
        case windowIsNotMovableAndResizable
        case unreadableFrame
        case actionDurationExceeded(index: Int, duration: Duration)
        case totalDurationExceeded(Duration)
        case unverifiedActionResult(index: Int)
        case restoreFailed
        case residentMemoryGrowthExceeded(UInt64)
        case multipleDisplaysRequired(actual: Int)
        case displayCouldNotBeResolved
        case windowDidNotChangeDisplay(step: String)
        case unexpectedDisplay(step: String)
        case missingUndoToken
        case unverifiedUndoResult
        case unverifiedG2ActionResult(step: String)

        var errorDescription: String? {
            switch self {
            case .notExplicitlyArmed:
                "Harness is read-only unless the explicit confirmation environment value is set."
            case .invalidFocusTimeout:
                "The focus timeout must be a finite value from 0 to 60 seconds."
            case .accessibilityNotTrusted:
                "Accessibility is not trusted; no Window Action was attempted."
            case .openChamberWasNotFocused:
                "OpenChamber was not the focused application before the bounded preflight expired."
            case .targetChanged:
                "The pinned OpenChamber PID or focused AX window changed; recovery was attempted."
            case .focusedWindowUnavailable:
                "The focused OpenChamber window could not be captured through public Accessibility."
            case .windowIsNotMovableAndResizable:
                "The focused OpenChamber window is not both movable and resizable."
            case .unreadableFrame:
                "The focused OpenChamber window frame could not be read through public Accessibility."
            case .actionDurationExceeded(let index, _):
                "Snap action \(index + 1) exceeded the per-action bound; recovery was attempted."
            case .totalDurationExceeded:
                "The 100-action sequence exceeded the total bound; recovery was attempted."
            case .unverifiedActionResult(let index):
                "Snap action \(index + 1) was not a verified commit; recovery was attempted."
            case .restoreFailed:
                "The final frame did not match the captured original frame after recovery."
            case .residentMemoryGrowthExceeded:
                "Resident memory grew beyond the harness's obvious-leak threshold."
            case .multipleDisplaysRequired(let actual):
                "Gate G2 requires at least two active physical Displays; found \(actual)."
            case .displayCouldNotBeResolved:
                "The pinned window could not be associated with an active physical Display."
            case .windowDidNotChangeDisplay(let step):
                "\(step) committed but the raw AX frame remained on the source Display."
            case .unexpectedDisplay(let step):
                "\(step) placed the raw AX frame on an unexpected physical Display."
            case .missingUndoToken:
                "Move Next committed without the explicit Undo token required by Gate G2."
            case .unverifiedUndoResult:
                "Undo did not report a verified undone effect."
            case .unverifiedG2ActionResult(let step):
                "\(step) did not report a verified committed effect."
            }
        }
    }
}

private struct PhysicalDisplays {
    private let boundsByID: [(id: CGDirectDisplayID, bounds: CGRect)]

    var count: Int { boundsByID.count }

    static func capture() throws -> Self {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else {
            throw OpenChamberWindowActionHarness.HarnessError.displayCouldNotBeResolved
        }
        var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            throw OpenChamberWindowActionHarness.HarnessError.displayCouldNotBeResolved
        }
        return Self(boundsByID: ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) })
    }

    func displayID(containing frame: CGRect) throws -> CGDirectDisplayID {
        guard let match = boundsByID.max(by: {
            intersectionArea(frame, $0.bounds) < intersectionArea(frame, $1.bounds)
        }), intersectionArea(frame, match.bounds) > 0 else {
            throw OpenChamberWindowActionHarness.HarnessError.displayCouldNotBeResolved
        }
        return match.id
    }
}

/// AXUIElement has no Sendable conformance. This wrapper is used only by this serial harness;
/// it keeps one immutable element alive across the `perform(_:)` await and never exposes it.
private final class PinnedTarget: @unchecked Sendable {
    let processIdentifier: pid_t
    private let bundleURL: URL
    private let window: AXUIElement
    private let expectedBundleIdentifier: String

    private init(
        processIdentifier: pid_t,
        bundleURL: URL,
        window: AXUIElement,
        expectedBundleIdentifier: String
    ) {
        self.processIdentifier = processIdentifier
        self.bundleURL = bundleURL
        self.window = window
        self.expectedBundleIdentifier = expectedBundleIdentifier
    }

    static func capture(expectedBundleIdentifier: String) throws -> Self? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        guard application.bundleIdentifier == expectedBundleIdentifier,
              let bundleURL = application.bundleURL,
              Bundle(url: bundleURL)?.bundleIdentifier == expectedBundleIdentifier
        else {
            return nil
        }

        let axApplication = AXUIElementCreateApplication(application.processIdentifier)
        guard let window = copyElement(
            axApplication,
            attribute: kAXFocusedWindowAttribute as String
        ) else {
            throw OpenChamberWindowActionHarness.HarnessError.focusedWindowUnavailable
        }
        guard isSettable(window, attribute: kAXPositionAttribute as String),
              isSettable(window, attribute: kAXSizeAttribute as String)
        else {
            throw OpenChamberWindowActionHarness.HarnessError.windowIsNotMovableAndResizable
        }
        _ = try readFrame(of: window)

        return Self(
            processIdentifier: application.processIdentifier,
            bundleURL: bundleURL.standardizedFileURL,
            window: window,
            expectedBundleIdentifier: expectedBundleIdentifier
        )
    }

    func requireStillFocused() throws {
        guard AXIsProcessTrusted() else {
            throw OpenChamberWindowActionHarness.HarnessError.accessibilityNotTrusted
        }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier == processIdentifier,
              application.bundleIdentifier == expectedBundleIdentifier,
              let currentBundleURL = application.bundleURL,
              currentBundleURL.standardizedFileURL == bundleURL,
              Bundle(url: currentBundleURL)?.bundleIdentifier == expectedBundleIdentifier
        else {
            throw OpenChamberWindowActionHarness.HarnessError.targetChanged
        }

        let axApplication = AXUIElementCreateApplication(processIdentifier)
        guard let focused = copyElement(
            axApplication,
            attribute: kAXFocusedWindowAttribute as String
        ), CFEqual(focused, window) else {
            throw OpenChamberWindowActionHarness.HarnessError.targetChanged
        }
    }

    func readFrame() throws -> CGRect {
        try Self.readFrame(of: window)
    }

    func restore(
        _ original: CGRect,
        tolerance: CGFloat
    ) throws -> CGRect {
        // Position before size avoids the known macOS clamp when the temporary frame is
        // offset from a screen edge. Attempt both writes even if the first one fails.
        var writeFailed = false
        if !setPoint(original.origin, on: window, attribute: kAXPositionAttribute as String) {
            writeFailed = true
        }
        if !setSize(original.size, on: window, attribute: kAXSizeAttribute as String) {
            writeFailed = true
        }
        let restored = try readFrame()
        guard !writeFailed, framesMatch(restored, original, tolerance: tolerance) else {
            throw OpenChamberWindowActionHarness.HarnessError.restoreFailed
        }
        return restored
    }

    private static func readFrame(of window: AXUIElement) throws -> CGRect {
        guard let position = copyPoint(
            window,
            attribute: kAXPositionAttribute as String
        ), let size = copySize(
            window,
            attribute: kAXSizeAttribute as String
        ) else {
            throw OpenChamberWindowActionHarness.HarnessError.unreadableFrame
        }
        let frame = CGRect(origin: position, size: size)
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            throw OpenChamberWindowActionHarness.HarnessError.unreadableFrame
        }
        return frame
    }
}

private struct ResidentMemory {
    static func currentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }
}

private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else { return nil }
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

private func copyPoint(_ element: AXUIElement, attribute: String) -> CGPoint? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    var point = CGPoint.zero
    guard AXValueGetType(axValue) == .cgPoint,
          AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
}

private func copySize(_ element: AXUIElement, attribute: String) -> CGSize? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    var size = CGSize.zero
    guard AXValueGetType(axValue) == .cgSize,
          AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
}

private func isSettable(_ element: AXUIElement, attribute: String) -> Bool {
    var settable = DarwinBoolean(false)
    let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
    return error == .success && settable.boolValue
}

private func setPoint(_ point: CGPoint, on element: AXUIElement, attribute: String) -> Bool {
    var point = point
    guard let value = AXValueCreate(.cgPoint, &point) else { return false }
    return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
}

private func setSize(_ size: CGSize, on element: AXUIElement, attribute: String) -> Bool {
    var size = size
    guard let value = AXValueCreate(.cgSize, &size) else { return false }
    return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
}

private func framesMatch(_ first: CGRect, _ second: CGRect, tolerance: CGFloat) -> Bool {
    abs(first.minX - second.minX) <= tolerance
        && abs(first.minY - second.minY) <= tolerance
        && abs(first.width - second.width) <= tolerance
        && abs(first.height - second.height) <= tolerance
}

private func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
    let intersection = first.intersection(second)
    guard !intersection.isNull, !intersection.isInfinite else { return 0 }
    return intersection.width * intersection.height
}
