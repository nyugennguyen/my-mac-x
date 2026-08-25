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

    private static let confirmationEnvironmentKey =
        "MYMACX_W2_12_OPENCHAMBER_CONFIRMATION"
    private static let focusTimeoutEnvironmentKey =
        "MYMACX_W2_12_OPENCHAMBER_FOCUS_TIMEOUT_SECONDS"
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
            }
        }
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
