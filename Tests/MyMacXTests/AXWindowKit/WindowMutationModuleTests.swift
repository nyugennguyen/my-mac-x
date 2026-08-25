import CoreGraphics
import XCTest
@testable import MyMacX

private let defaultAllowedAXFrame = AXGlobalTopLeftFrame(
    CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)
)

private func ax(_ frame: CGRect) -> AXGlobalTopLeftFrame {
    AXGlobalTopLeftFrame(frame)
}

private extension WindowMutationModule {
    func mutate(
        window: WindowIdentity,
        to targetFrame: CGRect
    ) async -> WindowMutationResult {
        await mutate(
            window: window,
            to: AXGlobalTopLeftFrame(targetFrame),
            within: defaultAllowedAXFrame
        )
    }
}

final class WindowMutationModuleTests: XCTestCase {
    func testReturnsVerifiedSuccessOnlyAfterReadingBackTheRequestedFrame() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 80, y: 90, width: 900, height: 700)
        let target = CGRect(x: 20, y: 30, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: target, capabilities: .movableAndResizable),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let remainingStepCount = await adapter.remainingMutationStepCount

        XCTAssertEqual(result, .applied(actualFrame: ax(target), constrained: false))
        XCTAssertEqual(remainingStepCount, 0)
    }

    func testRetriesAfterAMismatchedReadBackAndReturnsTheVerifiedFrame() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 80, y: 90, width: 900, height: 700)
        let target = CGRect(x: 20, y: 30, width: 640, height: 480)
        let firstReadBack = CGRect(x: 22, y: 30, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: firstReadBack, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: target, capabilities: .movableAndResizable),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let writeCount = await adapter.targetWriteCount
        let inspectionCount = await adapter.inspectionCount

        XCTAssertEqual(result, .applied(actualFrame: ax(target), constrained: false))
        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(inspectionCount, 3)
    }

    func testReportsAStableFiniteApplicationClampWhenItLiesBetweenPriorAndRequestedFrames() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 320, height: 240)
        let applicationClamp = CGRect(x: 30, y: 30, width: 500, height: 360)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: applicationClamp, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: applicationClamp, capabilities: .movableAndResizable),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let writeCount = await adapter.targetWriteCount

        XCTAssertEqual(
            result,
            .applied(actualFrame: ax(applicationClamp), constrained: true)
        )
        XCTAssertEqual(writeCount, 2)
    }

    func testRepositionsAStableMinimumSizeClampInsideTheAllowedFrame() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 1_920, y: 33, width: 800, height: 923)
        let target = CGRect(x: 2_655, y: 32, width: 735, height: 924)
        let allowed = CGRect(x: 1_920, y: 32, width: 1_470, height: 924)
        let applicationClamp = CGRect(x: 2_655, y: 33, width: 800, height: 923)
        let reconciled = CGRect(x: 2_590, y: 33, width: 800, height: 923)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: applicationClamp, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: applicationClamp, capabilities: .movableAndResizable),
                .writeTargetAxes(
                    identity,
                    frame: reconciled,
                    axes: .position,
                    result: .accepted
                ),
                .inspect(identity, frame: reconciled, capabilities: .movableAndResizable),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: ax(target),
            within: ax(allowed)
        )
        let remainingStepCount = await adapter.remainingMutationStepCount
        let targetWriteCount = await adapter.targetWriteCount

        XCTAssertEqual(
            result,
            .applied(actualFrame: ax(reconciled), constrained: true)
        )
        XCTAssertEqual(targetWriteCount, 3)
        XCTAssertEqual(remainingStepCount, 0)
    }

    func testReportsWindowDisappearedWithoutRetargetingAfterAWrite() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspectFailure(identity, .windowDisappeared),
                .writeRollback(
                    identity,
                    frame: original,
                    result: .failure(.windowDisappeared)
                ),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let remainingStepCount = await adapter.remainingMutationStepCount
        let rollbackCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.windowDisappeared))
        XCTAssertEqual(remainingStepCount, 0)
        XCTAssertEqual(rollbackCount, 1)
    }

    func testStaleCapturedWindowRejectsOnFreshInspectionWithoutWritingOrRetargeting() async {
        let identity = WindowIdentity()
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspectFailure(identity, .windowDisappeared),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: CGRect(x: 20, y: 20, width: 640, height: 480)
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.windowDisappeared))
        XCTAssertEqual(targetWriteCount, 0)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testRejectedFullPlacementRollsBackBeforeReportingFailure() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .failure(.rejected)),
                .writeRollback(identity, frame: original, result: .accepted),
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.mutationRejected))
        XCTAssertEqual(rollbackWriteCount, 1)
    }

    func testRetryRevalidatesCapabilitiesAndDoesNotWriteAnAxisThatBecameUnsupported() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let firstReadBack = CGRect(x: 22, y: 20, width: 640, height: 480)
        let moveOnly = WindowCapabilities(
            isMovable: true,
            isResizable: false,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: firstReadBack, capabilities: moveOnly),
                .writeTargetAxes(
                    identity,
                    frame: target,
                    axes: .position,
                    result: .accepted
                ),
                .inspect(identity, frame: target, capabilities: moveOnly),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )

        XCTAssertEqual(result, .applied(actualFrame: ax(target), constrained: false))
    }

    func testRetryRevalidatesNewMinimizedStateAndRollsBackWithoutAnotherTargetWrite() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let firstReadBack = CGRect(x: 22, y: 20, width: 640, height: 480)
        let minimized = WindowCapabilities(
            isMovable: true,
            isResizable: true,
            minimized: .active,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: firstReadBack, capabilities: minimized),
                .writeRollback(identity, frame: original, result: .accepted),
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.mutationRejected))
        XCTAssertEqual(targetWriteCount, 1)
        XCTAssertEqual(rollbackWriteCount, 1)
    }

    func testVerificationTimesOutAfterBoundedAttemptsAndVerifiesRollback() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(
                    identity,
                    frame: CGRect(x: 22, y: 20, width: 640, height: 480),
                    capabilities: .movableAndResizable
                ),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(
                    identity,
                    frame: CGRect(x: 24, y: 20, width: 640, height: 480),
                    capabilities: .movableAndResizable
                ),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(
                    identity,
                    frame: CGRect(x: 26, y: 20, width: 640, height: 480),
                    capabilities: .movableAndResizable
                ),
                .writeRollback(identity, frame: original, result: .accepted),
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount
        let inspectionCount = await adapter.inspectionCount

        XCTAssertEqual(result, .failed(.verificationTimedOut))
        XCTAssertEqual(
            targetWriteCount,
            WindowMutationPolicy.standard.maximumAttemptCount
        )
        XCTAssertEqual(rollbackWriteCount, 1)
        XCTAssertEqual(inspectionCount, 5)
    }

    func testReportsRollbackIncompleteWhenRecoveryReadBackDoesNotMatchPriorFrame() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let mismatches = [
            CGRect(x: 22, y: 20, width: 640, height: 480),
            CGRect(x: 24, y: 20, width: 640, height: 480),
            CGRect(x: 26, y: 20, width: 640, height: 480),
        ]
        let incompleteRollback = CGRect(x: 100, y: 100, width: 850, height: 700)
        var steps: [ScriptedWindowAdapter.MutationStep] = [
            .inspect(identity, frame: original, capabilities: .movableAndResizable),
        ]
        for mismatch in mismatches {
            steps.append(.writeTarget(identity, frame: target, result: .accepted))
            steps.append(
                .inspect(identity, frame: mismatch, capabilities: .movableAndResizable)
            )
        }
        steps.append(.writeRollback(identity, frame: original, result: .accepted))
        steps.append(
            .inspect(
                identity,
                frame: incompleteRollback,
                capabilities: .movableAndResizable
            )
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: steps
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let remainingStepCount = await adapter.remainingMutationStepCount

        XCTAssertEqual(result, .failed(.rollbackIncomplete))
        XCTAssertEqual(remainingStepCount, 0)
    }

    func testAcceptsReadBackWithinOneLogicalPointAndReturnsTheActualFrame() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let actual = CGRect(x: 21, y: 19, width: 639, height: 481)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: actual, capabilities: .movableAndResizable),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )

        XCTAssertEqual(result, .applied(actualFrame: ax(actual), constrained: false))
    }

    func testDoesNotTreatAStableMismatchOutsideThePriorToTargetDeltaAsAClamp() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let unexplainedMismatch = CGRect(x: -400, y: 20, width: 640, height: 480)
        var steps: [ScriptedWindowAdapter.MutationStep] = [
            .inspect(identity, frame: original, capabilities: .movableAndResizable),
        ]
        for _ in 0..<WindowMutationPolicy.standard.maximumAttemptCount {
            steps.append(.writeTarget(identity, frame: target, result: .accepted))
            steps.append(
                .inspect(
                    identity,
                    frame: unexplainedMismatch,
                    capabilities: .movableAndResizable
                )
            )
        }
        steps.append(.writeRollback(identity, frame: original, result: .accepted))
        steps.append(.inspect(identity, frame: original, capabilities: .movableAndResizable))
        let adapter = ScriptedWindowAdapter(captures: [.unsupported], mutationSteps: steps)

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )

        XCTAssertEqual(result, .failed(.verificationTimedOut))
    }

    func testRejectsMissingMoveCapabilityBeforeWriting() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 640, height: 480)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(
                    identity,
                    frame: original,
                    capabilities: WindowCapabilities(
                        isMovable: false,
                        isResizable: true,
                        minimized: .inactive,
                        nativeFullScreen: .unavailable
                    )
                ),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let writeCount = await adapter.targetWriteCount

        XCTAssertEqual(result, .failed(.windowNotMovable))
        XCTAssertEqual(writeCount, 0)
    }

    func testRejectsAnInvalidTypedTargetBeforeInspectingOrWriting() async {
        let identity = WindowIdentity()
        let adapter = ScriptedWindowAdapter(captures: [.unsupported])
        let invalidTarget = AXGlobalTopLeftFrame(
            CGRect(x: 20, y: 20, width: CGFloat.infinity, height: 480)
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: invalidTarget,
            within: AXGlobalTopLeftFrame(
                CGRect(x: 0, y: 0, width: 1_440, height: 900)
            )
        )
        let inspectionCount = await adapter.inspectionCount
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.mutationRejected))
        XCTAssertEqual(inspectionCount, 0)
        XCTAssertEqual(targetWriteCount, 0)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testRejectsAnInvalidOriginalFrameWithoutWritingOrRollingBack() async {
        let identity = WindowIdentity()
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(
                    identity,
                    frame: CGRect(x: 100, y: 100, width: CGFloat.nan, height: 700),
                    capabilities: .movableAndResizable
                ),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.mutationRejected))
        XCTAssertEqual(targetWriteCount, 0)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testMoveOnlyWindowWritesAndVerifiesOnlyTheChangedPositionAxis() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 640, height: 480)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let moveOnly = WindowCapabilities(
            isMovable: true,
            isResizable: false,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: moveOnly),
                .writeTargetAxes(
                    identity,
                    frame: target,
                    axes: .position,
                    result: .accepted
                ),
                .inspect(identity, frame: target, capabilities: moveOnly),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )

        XCTAssertEqual(result, .applied(actualFrame: ax(target), constrained: false))
    }

    func testMoveOnlySheetPreservesSizeAndClampsPositionWithoutAResizeWrite() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 640, height: 480)
        let requested = CGRect(x: 800, y: 600, width: 100, height: 100)
        let fallback = CGRect(x: 360, y: 320, width: 640, height: 480)
        let moveOnly = WindowCapabilities(
            isMovable: true,
            isResizable: false,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(
                    identity,
                    frame: original,
                    kind: .sheet,
                    capabilities: moveOnly
                ),
                .writeTargetAxes(
                    identity,
                    frame: fallback,
                    axes: .position,
                    result: .accepted
                ),
                .inspect(
                    identity,
                    frame: fallback,
                    kind: .sheet,
                    capabilities: moveOnly
                ),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: ax(requested),
            within: ax(CGRect(x: 0, y: 0, width: 1_000, height: 800))
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .applied(actualFrame: ax(fallback), constrained: true))
        XCTAssertEqual(targetWriteCount, 1)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testResizeOnlyWindowWritesAndVerifiesOnlyTheChangedSizeAxis() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 640, height: 480)
        let target = CGRect(x: 100, y: 100, width: 900, height: 700)
        let resizeOnly = WindowCapabilities(
            isMovable: false,
            isResizable: true,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: resizeOnly),
                .writeTargetAxes(
                    identity,
                    frame: target,
                    axes: .size,
                    result: .accepted
                ),
                .inspect(identity, frame: target, capabilities: resizeOnly),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: target
        )

        XCTAssertEqual(result, .applied(actualFrame: ax(target), constrained: false))
    }

    func testResizeOnlyDialogPreservesAValidOriginWithoutAMoveWrite() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 640, height: 480)
        let requested = CGRect(x: 20, y: 20, width: 700, height: 600)
        let fallback = CGRect(x: 100, y: 100, width: 700, height: 600)
        let resizeOnly = WindowCapabilities(
            isMovable: false,
            isResizable: true,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(
                    identity,
                    frame: original,
                    kind: .dialog,
                    capabilities: resizeOnly
                ),
                .writeTargetAxes(
                    identity,
                    frame: fallback,
                    axes: .size,
                    result: .accepted
                ),
                .inspect(
                    identity,
                    frame: fallback,
                    kind: .dialog,
                    capabilities: resizeOnly
                ),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: ax(requested),
            within: ax(CGRect(x: 0, y: 0, width: 1_000, height: 800))
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .applied(actualFrame: ax(fallback), constrained: true))
        XCTAssertEqual(targetWriteCount, 1)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testResizeOnlyWindowRejectsBeforeWritingWhenPreservedOriginWouldBeInvalid() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 800, y: 100, width: 100, height: 100)
        let requested = CGRect(x: 0, y: 0, width: 400, height: 400)
        let resizeOnly = WindowCapabilities(
            isMovable: false,
            isResizable: true,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: resizeOnly),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: ax(requested),
            within: ax(CGRect(x: 0, y: 0, width: 1_000, height: 800))
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.mutationRejected))
        XCTAssertEqual(targetWriteCount, 0)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testWindowWithNeitherPlacementCapabilityRejectsBeforeAnyMutation() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 640, height: 480)
        let capabilities = WindowCapabilities(
            isMovable: false,
            isResizable: false,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, kind: .dialog, capabilities: capabilities),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: CGRect(x: 20, y: 20, width: 700, height: 600)
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.mutationRejected))
        XCTAssertEqual(targetWriteCount, 0)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testNewlyMinimizedCapturedWindowIsRejectedByFreshInspectionWithoutWriting() async {
        let identity = WindowIdentity()
        let capabilities = WindowCapabilities(
            isMovable: true,
            isResizable: true,
            minimized: .active,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(
                    identity,
                    frame: CGRect(x: 100, y: 100, width: 640, height: 480),
                    capabilities: capabilities
                ),
            ]
        )

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: CGRect(x: 20, y: 20, width: 700, height: 600)
        )
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.mutationRejected))
        XCTAssertEqual(targetWriteCount, 0)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testStableCoupledClampIsRepositionedInsideAllowedEdges() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 0, y: 0, width: 800, height: 600)
        let target = CGRect(x: 500, y: 0, width: 500, height: 600)
        let offscreenClamp = CGRect(x: 500, y: 0, width: 800, height: 600)
        let reconciled = CGRect(x: 200, y: 0, width: 800, height: 600)
        let steps: [ScriptedWindowAdapter.MutationStep] = [
            .inspect(identity, frame: original, capabilities: .movableAndResizable),
            .writeTarget(identity, frame: target, result: .accepted),
            .inspect(
                identity,
                frame: offscreenClamp,
                capabilities: .movableAndResizable
            ),
            .writeTarget(identity, frame: target, result: .accepted),
            .inspect(
                identity,
                frame: offscreenClamp,
                capabilities: .movableAndResizable
            ),
            .writeTargetAxes(
                identity,
                frame: reconciled,
                axes: .position,
                result: .accepted
            ),
            .inspect(identity, frame: reconciled, capabilities: .movableAndResizable),
        ]
        let adapter = ScriptedWindowAdapter(captures: [.unsupported], mutationSteps: steps)

        let result = await WindowMutationModule(adapter: adapter).mutate(
            window: identity,
            to: AXGlobalTopLeftFrame(target),
            within: AXGlobalTopLeftFrame(
                CGRect(x: 0, y: 0, width: 1_000, height: 800)
            )
        )

        XCTAssertEqual(
            result,
            .applied(actualFrame: ax(reconciled), constrained: true)
        )
    }

    func testExpiredDeadlinePreventsTheFirstTargetWriteAndDoesNotRollback() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
            ]
        )
        let clock = ScriptedWindowMutationClock(
            instants: [.zero, .zero, .seconds(6)]
        )
        let mutations = WindowMutationModule(
            adapter: adapter,
            clock: clock,
            policy: WindowMutationPolicy(maximumAttemptCount: 3, deadline: .seconds(5))
        )

        let result = await mutations.mutate(window: identity, to: target)
        let targetWriteCount = await adapter.targetWriteCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.verificationTimedOut))
        XCTAssertEqual(targetWriteCount, 0)
        XCTAssertEqual(rollbackWriteCount, 0)
    }

    func testExpiredDeadlineAfterReadBackCannotReportLateSuccessAndRollsBack() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: target, capabilities: .movableAndResizable),
                .writeRollback(identity, frame: original, result: .accepted),
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
            ]
        )
        let clock = ScriptedWindowMutationClock(
            instants: [.zero, .zero, .zero, .zero, .seconds(6)]
        )
        let mutations = WindowMutationModule(
            adapter: adapter,
            clock: clock,
            policy: WindowMutationPolicy(maximumAttemptCount: 3, deadline: .seconds(5))
        )

        let result = await mutations.mutate(window: identity, to: target)
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.verificationTimedOut))
        XCTAssertEqual(rollbackWriteCount, 1)
    }

    func testWriteCrossingDeadlineDoesNotStartReadBackAndStillRollsBack() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .writeRollback(identity, frame: original, result: .accepted),
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
            ]
        )
        let clock = ScriptedWindowMutationClock(
            instants: [.zero, .zero, .zero, .seconds(6)]
        )
        let mutations = WindowMutationModule(
            adapter: adapter,
            clock: clock,
            policy: WindowMutationPolicy(maximumAttemptCount: 3, deadline: .seconds(5))
        )

        let result = await mutations.mutate(window: identity, to: target)
        let inspectionCount = await adapter.inspectionCount
        let rollbackWriteCount = await adapter.rollbackWriteCount

        XCTAssertEqual(result, .failed(.verificationTimedOut))
        XCTAssertEqual(inspectionCount, 2)
        XCTAssertEqual(rollbackWriteCount, 1)
    }

    func testDeadlineAfterTransientReadBackRollsBackThePriorAcceptedWrite() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspectFailure(identity, .temporarilyUnavailable),
                .writeRollback(identity, frame: original, result: .accepted),
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
            ]
        )
        let clock = ScriptedWindowMutationClock(
            instants: [.zero, .zero, .zero, .zero, .zero, .seconds(6)]
        )
        let mutations = WindowMutationModule(
            adapter: adapter,
            clock: clock,
            policy: WindowMutationPolicy(maximumAttemptCount: 3, deadline: .seconds(5))
        )

        let result = await mutations.mutate(window: identity, to: target)
        let rollbackWriteCount = await adapter.rollbackWriteCount
        let remainingStepCount = await adapter.remainingMutationStepCount

        XCTAssertEqual(result, .failed(.verificationTimedOut))
        XCTAssertEqual(rollbackWriteCount, 1)
        XCTAssertEqual(remainingStepCount, 0)
    }

    func testDeadlineAfterTransientWriteRollsBackPossiblePartialMutation() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(
                    identity,
                    frame: target,
                    result: .failure(.temporarilyUnavailable)
                ),
                .writeRollback(identity, frame: original, result: .accepted),
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
            ]
        )
        let clock = ScriptedWindowMutationClock(
            instants: [.zero, .zero, .zero, .zero, .seconds(6)]
        )
        let mutations = WindowMutationModule(
            adapter: adapter,
            clock: clock,
            policy: WindowMutationPolicy(maximumAttemptCount: 3, deadline: .seconds(5))
        )

        let result = await mutations.mutate(window: identity, to: target)
        let rollbackWriteCount = await adapter.rollbackWriteCount
        let remainingStepCount = await adapter.remainingMutationStepCount

        XCTAssertEqual(result, .failed(.verificationTimedOut))
        XCTAssertEqual(rollbackWriteCount, 1)
        XCTAssertEqual(remainingStepCount, 0)
    }

    func testRetriesTransientWriteUnavailabilityWithinTheDeadline() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(
                    identity,
                    frame: target,
                    result: .failure(.temporarilyUnavailable)
                ),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: target, capabilities: .movableAndResizable),
            ]
        )
        let clock = ScriptedWindowMutationClock(instants: [.zero])
        let mutations = WindowMutationModule(adapter: adapter, clock: clock)

        let result = await mutations.mutate(window: identity, to: target)
        let targetWriteCount = await adapter.targetWriteCount

        XCTAssertEqual(result, .applied(actualFrame: ax(target), constrained: false))
        XCTAssertEqual(targetWriteCount, 2)
    }

    func testRetriesTransientInitialInspectionWithinTheDeadline() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspectFailure(identity, .temporarilyUnavailable),
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: target, capabilities: .movableAndResizable),
            ]
        )
        let clock = ScriptedWindowMutationClock(instants: [.zero])

        let result = await WindowMutationModule(adapter: adapter, clock: clock).mutate(
            window: identity,
            to: target
        )
        let inspectionCount = await adapter.inspectionCount

        XCTAssertEqual(result, .applied(actualFrame: ax(target), constrained: false))
        XCTAssertEqual(inspectionCount, 3)
    }

    func testRetriesTransientReadBackUnavailabilityWithinTheDeadline() async {
        let identity = WindowIdentity()
        let original = CGRect(x: 100, y: 100, width: 900, height: 700)
        let target = CGRect(x: 20, y: 20, width: 640, height: 480)
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported],
            mutationSteps: [
                .inspect(identity, frame: original, capabilities: .movableAndResizable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspectFailure(identity, .temporarilyUnavailable),
                .writeTarget(identity, frame: target, result: .accepted),
                .inspect(identity, frame: target, capabilities: .movableAndResizable),
            ]
        )
        let clock = ScriptedWindowMutationClock(instants: [.zero])

        let result = await WindowMutationModule(adapter: adapter, clock: clock).mutate(
            window: identity,
            to: target
        )
        let targetWriteCount = await adapter.targetWriteCount

        XCTAssertEqual(result, .applied(actualFrame: ax(target), constrained: false))
        XCTAssertEqual(targetWriteCount, 2)
    }

}
