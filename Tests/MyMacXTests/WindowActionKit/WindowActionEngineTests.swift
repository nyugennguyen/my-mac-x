import CoreGraphics
import Foundation
import XCTest

@testable import MyMacX

final class WindowActionEngineTests: XCTestCase {
    func testExcludedFocusedApplicationRejectsDirectCommitBeforeMutation() async {
        let window = WindowIdentity()
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 100, y: 100, width: 400, height: 300)]
        )
        let identities = ScriptedCapturedWindowApplications([
            window: "com.example.excluded",
        ])
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: mutation,
            applicationIdentities: identities,
            appRules: AppRuleRuntime(policy: policy(excluding: "com.example.excluded"))
        )

        let result = await engine.perform(.commit(action: .leftHalf, source: .menuBar))
        let mutations = await mutation.mutationCalls
        let requestedWindows = await identities.requestedWindows

        XCTAssertEqual(result.disposition, .rejected(.applicationExcluded))
        XCTAssertTrue(mutations.isEmpty)
        XCTAssertEqual(requestedWindows, [window])
    }

    func testExplicitPreviewEvaluatesRulesForExactCapturedIdentityWithoutRefocusingOrMutation() async {
        let pointerCaptured = WindowIdentity()
        let laterFocused = WindowIdentity()
        let focus = ScriptedFocusedWindows([.found(eligible(laterFocused))])
        let mutation = RecordingWindowMutation(
            frames: [
                pointerCaptured: axFrame(x: 100, y: 100, width: 400, height: 300),
                laterFocused: axFrame(x: 700, y: 100, width: 300, height: 250),
            ]
        )
        let identities = ScriptedCapturedWindowApplications([
            pointerCaptured: "com.example.excluded",
            laterFocused: "com.example.included",
        ])
        let engine = makeEngine(
            focus: focus,
            mutation: mutation,
            applicationIdentities: identities,
            appRules: AppRuleRuntime(policy: policy(excluding: "com.example.excluded"))
        )

        let result = await engine.perform(
            .preview(
                action: .leftHalf,
                interaction: InteractionID(),
                capturedWindow: pointerCaptured
            )
        )
        let captureCount = await focus.captureCount
        let requestedWindows = await identities.requestedWindows
        let mutations = await mutation.mutationCalls

        XCTAssertEqual(result.disposition, .rejected(.applicationExcluded))
        XCTAssertEqual(captureCount, 0)
        XCTAssertEqual(requestedWindows, [pointerCaptured])
        XCTAssertTrue(mutations.isEmpty)
    }

    func testCommitPreviewRechecksRuntimeRulesForBoundIdentityBeforeMutation() async {
        let captured = WindowIdentity()
        let mutation = RecordingWindowMutation(
            frames: [captured: axFrame(x: 100, y: 100, width: 400, height: 300)]
        )
        let runtime = AppRuleRuntime()
        let identities = ScriptedCapturedWindowApplications([
            captured: "com.example.editor",
        ])
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(captured))]),
            mutation: mutation,
            applicationIdentities: identities,
            appRules: runtime
        )
        let interaction = InteractionID()

        let preview = await engine.perform(.preview(action: .leftHalf, interaction: interaction))
        await runtime.replace(with: policy(excluding: "com.example.editor"))
        let committed = await engine.perform(.commitPreview(interaction: interaction))
        let requestedWindows = await identities.requestedWindows
        let mutations = await mutation.mutationCalls

        XCTAssertEqual(preview.disposition, .succeeded)
        XCTAssertEqual(committed.disposition, .rejected(.applicationExcluded))
        XCTAssertEqual(requestedWindows, [captured, captured])
        XCTAssertTrue(mutations.isEmpty)
    }

    func testMissingApplicationIdentityFailsClosed() async {
        let window = WindowIdentity()
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 100, y: 100, width: 400, height: 300)]
        )
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: mutation,
            applicationIdentities: ScriptedCapturedWindowApplications([:])
        )

        let result = await engine.perform(.commit(action: .leftHalf, source: .menuBar))
        let mutations = await mutation.mutationCalls

        XCTAssertEqual(result.disposition, .rejected(.applicationExcluded))
        XCTAssertTrue(mutations.isEmpty)
    }

    func testDirectCommitCapturesFocusOnceAndReturnsVerifiedHistoryToken() async {
        let window = WindowIdentity()
        let focus = ScriptedFocusedWindows([.found(eligible(window))])
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 100, y: 100, width: 400, height: 300)],
            outcomes: [.applied(actualFrame: axFrame(x: 0, y: 25, width: 600, height: 775), constrained: false)]
        )
        let engine = makeEngine(focus: focus, mutation: mutation)

        let result = await engine.perform(.commit(action: .leftHalf, source: .menuBar))
        let captureCount = await focus.captureCount

        XCTAssertEqual(captureCount, 1)
        guard case let .committed(actualFrame, constrained) = result.effect else {
            return XCTFail("Expected a verified commit")
        }
        XCTAssertEqual(actualFrame, CGRect(x: 0, y: 0, width: 600, height: 775))
        XCTAssertFalse(constrained)
        XCTAssertEqual(result.disposition, .succeeded)
        XCTAssertNotNil(result.undoToken)
    }

    func testAllNineBuiltInPlacementActionsPlanThroughPerform() async {
        let expected: [(ActionID, CGRect)] = [
            (.maximize, CGRect(x: 0, y: 0, width: 1200, height: 775)),
            (.leftHalf, CGRect(x: 0, y: 0, width: 600, height: 775)),
            (.rightHalf, CGRect(x: 600, y: 0, width: 600, height: 775)),
            (.topHalf, CGRect(x: 0, y: 388, width: 1200, height: 387)),
            (.bottomHalf, CGRect(x: 0, y: 0, width: 1200, height: 388)),
            (.topLeftQuarter, CGRect(x: 0, y: 388, width: 600, height: 387)),
            (.topRightQuarter, CGRect(x: 600, y: 388, width: 600, height: 387)),
            (.bottomLeftQuarter, CGRect(x: 0, y: 0, width: 600, height: 388)),
            (.bottomRightQuarter, CGRect(x: 600, y: 0, width: 600, height: 388)),
        ]

        for (index, example) in expected.enumerated() {
            let window = WindowIdentity()
            let engine = makeEngine(
                focus: ScriptedFocusedWindows([.found(eligible(window))]),
                mutation: RecordingWindowMutation(frames: [window: axFrame(x: 10, y: 10, width: 400, height: 300)])
            )
            let interaction = InteractionID(UUID(uuidString: "00000000-0000-0000-0000-0000000000\(10 + index)")!)

            let result = await engine.perform(.preview(action: example.0, interaction: interaction))

            XCTAssertEqual(
                result,
                WindowActionResult(
                    disposition: .succeeded,
                    effect: .preview(frame: example.1, displayID: 1, constrained: false),
                    undoToken: nil,
                    warnings: []
                )
            )
        }
    }

    func testPreviewIsPureAndCommitPreviewUsesBoundIdentityWithoutRetargeting() async {
        let captured = WindowIdentity()
        let laterFocused = WindowIdentity()
        let focus = ScriptedFocusedWindows([
            .found(eligible(captured)),
            .found(eligible(laterFocused)),
        ])
        let mutation = RecordingWindowMutation(
            frames: [
                captured: axFrame(x: 100, y: 100, width: 400, height: 300),
                laterFocused: axFrame(x: 200, y: 200, width: 500, height: 400),
            ],
            outcomes: [.applied(actualFrame: axFrame(x: 0, y: 25, width: 600, height: 775), constrained: false)]
        )
        let engine = makeEngine(focus: focus, mutation: mutation)
        let interaction = InteractionID()

        let preview = await engine.perform(.preview(action: .leftHalf, interaction: interaction))
        let previewMutationCount = await mutation.mutationCalls.count
        XCTAssertEqual(preview.disposition, .succeeded)
        XCTAssertEqual(previewMutationCount, 0)

        let committed = await engine.perform(.commitPreview(interaction: interaction))
        let captureCount = await focus.captureCount
        let mutatedWindows = await mutation.mutationCalls.map(\.window)
        let consumed = await engine.perform(.commitPreview(interaction: interaction))

        XCTAssertEqual(committed.disposition, .succeeded)
        XCTAssertEqual(captureCount, 1)
        XCTAssertEqual(mutatedWindows, [captured])
        XCTAssertNotNil(committed.undoToken)
        XCTAssertEqual(consumed.disposition, .rejected(.previewMissingOrExpired))
    }

    func testIdentityBoundPreviewNeverRecapturesFocusAndCommitsThePointerCapturedWindow() async {
        let pointerCaptured = WindowIdentity()
        let laterFocused = WindowIdentity()
        let focus = ScriptedFocusedWindows([.found(eligible(laterFocused))])
        let mutation = RecordingWindowMutation(
            frames: [
                pointerCaptured: axFrame(x: 100, y: 100, width: 400, height: 300),
                laterFocused: axFrame(x: 700, y: 100, width: 300, height: 250),
            ],
            outcomes: [
                .applied(
                    actualFrame: axFrame(x: 0, y: 25, width: 600, height: 775),
                    constrained: false
                ),
            ]
        )
        let engine = makeEngine(focus: focus, mutation: mutation)
        let interaction = InteractionID()

        let preview = await engine.perform(
            .preview(
                action: .leftHalf,
                interaction: interaction,
                capturedWindow: pointerCaptured
            )
        )
        let committed = await engine.perform(.commitPreview(interaction: interaction))
        let captureCount = await focus.captureCount
        let mutatedWindows = await mutation.mutationCalls.map(\.window)

        XCTAssertEqual(preview.disposition, .succeeded)
        XCTAssertEqual(committed.disposition, .succeeded)
        XCTAssertEqual(captureCount, 0)
        XCTAssertEqual(mutatedWindows, [pointerCaptured])
    }

    func testLatestHoverSupersedesOlderCalculation() async {
        let window = WindowIdentity()
        let topology = GatedWindowActionTopology(snapshot: topologySnapshot(generation: 7))
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 50, y: 50, width: 300, height: 200)]
        )
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: mutation,
            topology: topology
        )
        let interaction = InteractionID()

        let first = Task { await engine.perform(.preview(action: .leftHalf, interaction: interaction)) }
        while await topology.captureCount == 0 { await Task.yield() }
        let second = Task { await engine.perform(.preview(action: .rightHalf, interaction: interaction)) }
        for _ in 0..<20 { await Task.yield() }
        await topology.release()

        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertEqual(firstResult.disposition, .superseded)
        guard case let .preview(frame, _, _) = secondResult.effect else {
            return XCTFail("Expected latest preview")
        }
        XCTAssertEqual(frame, CGRect(x: 600, y: 0, width: 600, height: 775))

        let committed = await engine.perform(.commitPreview(interaction: interaction))
        let committedTarget = await mutation.mutationCalls.first?.target.cgRect
        XCTAssertEqual(committed.disposition, .succeeded)
        XCTAssertEqual(committedTarget, CGRect(x: 600, y: 25, width: 600, height: 775))
    }

    func testCommitPreviewExpiresWhenBoundTopologyGenerationChanges() async {
        let window = WindowIdentity()
        let topology = ScriptedWindowActionTopology([
            .available(topologySnapshot(generation: 1)),
            .available(topologySnapshot(generation: 2)),
        ])
        let mutation = RecordingWindowMutation(frames: [window: axFrame(x: 50, y: 50, width: 300, height: 200)])
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: mutation,
            topology: topology
        )
        let interaction = InteractionID()

        _ = await engine.perform(.preview(action: .leftHalf, interaction: interaction))
        let committed = await engine.perform(.commitPreview(interaction: interaction))
        let mutationCalls = await mutation.mutationCalls

        XCTAssertEqual(committed.disposition, .rejected(.previewMissingOrExpired))
        XCTAssertTrue(mutationCalls.isEmpty)
    }

    func testCancelConsumesPreviewWithoutMutation() async {
        let window = WindowIdentity()
        let mutation = RecordingWindowMutation(frames: [window: axFrame(x: 50, y: 50, width: 300, height: 200)])
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: mutation
        )
        let interaction = InteractionID()
        _ = await engine.perform(.preview(action: .leftHalf, interaction: interaction))
        let cancelled = await engine.perform(.cancelPreview(interaction: interaction))
        let consumed = await engine.perform(.commitPreview(interaction: interaction))
        let mutationCalls = await mutation.mutationCalls

        XCTAssertEqual(cancelled.disposition, .cancelled)
        XCTAssertEqual(consumed.disposition, .rejected(.previewMissingOrExpired))
        XCTAssertTrue(mutationCalls.isEmpty)
    }

    func testFailedCommitDiscardsHistoryAndMapsRollbackFailure() async {
        let window = WindowIdentity()
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 100, y: 100, width: 400, height: 300)],
            outcomes: [.failed(.rollbackIncomplete)]
        )
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window)), .found(eligible(window))]),
            mutation: mutation
        )

        let failed = await engine.perform(.commit(action: .leftHalf, source: .menuBar))
        let undo = await engine.perform(.undo(token: nil, source: .menuBar))

        XCTAssertEqual(failed.disposition, .rejected(.rollbackIncomplete))
        XCTAssertEqual(failed.warnings, [.rollbackIncomplete])
        XCTAssertNil(failed.undoToken)
        XCTAssertEqual(undo.disposition, .rejected(.previewMissingOrExpired))
    }

    func testUndoTokenIsRestrictedToItsExactCapturedWindowAndNilUsesLatest() async {
        let firstWindow = WindowIdentity()
        let secondWindow = WindowIdentity()
        let focus = ScriptedFocusedWindows([
            .found(eligible(firstWindow)),
            .found(eligible(secondWindow)),
            .found(eligible(firstWindow)),
            .found(eligible(firstWindow)),
        ])
        let mutation = RecordingWindowMutation(
            frames: [
                firstWindow: axFrame(x: 100, y: 100, width: 400, height: 300),
                secondWindow: axFrame(x: 200, y: 100, width: 400, height: 300),
            ],
            outcomes: [
                .applied(actualFrame: axFrame(x: 0, y: 25, width: 600, height: 775), constrained: false),
                .applied(actualFrame: axFrame(x: 600, y: 25, width: 600, height: 775), constrained: false),
                .applied(actualFrame: axFrame(x: 100, y: 100, width: 400, height: 300), constrained: false),
            ]
        )
        let engine = makeEngine(focus: focus, mutation: mutation)
        let committed = await engine.perform(.commit(action: .leftHalf, source: .menuBar))
        let token = try! XCTUnwrap(committed.undoToken)

        let wrongWindow = await engine.perform(.undo(token: token, source: .menuBar))
        XCTAssertEqual(wrongWindow.disposition, .rejected(.previewMissingOrExpired))

        let exact = await engine.perform(.undo(token: token, source: .menuBar))
        XCTAssertEqual(exact.disposition, .succeeded)

        _ = await engine.perform(.commit(action: .rightHalf, source: .menuBar))
        let latest = await engine.perform(.undo(token: nil, source: .menuBar))
        XCTAssertEqual(latest.disposition, .succeeded)
    }

    func testUndoReconcilesExactWindowSnapshotAgainstFreshTopology() async {
        let window = WindowIdentity()
        let topology = ScriptedWindowActionTopology([
            .available(twoDisplayTopology(generation: 1)),
            .available(topologySnapshot(generation: 2)),
        ])
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 1600, y: 200, width: 400, height: 300)]
        )
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([
                .found(eligible(window)),
                .found(eligible(window)),
            ]),
            mutation: mutation,
            topology: topology
        )

        let committed = await engine.perform(.commit(action: .leftHalf, source: .menuBar))
        let undone = await engine.perform(.undo(token: committed.undoToken, source: .menuBar))
        let targets = await mutation.mutationCalls.map { $0.target.cgRect }

        XCTAssertEqual(committed.disposition, .succeeded)
        XCTAssertEqual(undone.disposition, .succeeded)
        XCTAssertEqual(undone.effect, .undone(actualFrame: CGRect(x: 800, y: 400, width: 400, height: 300)))
        XCTAssertEqual(undone.warnings, [.targetDisplayChanged])
        XCTAssertEqual(targets.last, CGRect(x: 800, y: 100, width: 400, height: 300))
    }

    func testCycleAdvancesOnlyAfterVerifiedSuccess() async {
        let window = WindowIdentity()
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 100, y: 100, width: 400, height: 300)],
            outcomes: [
                .failed(.mutationRejected),
                .applied(actualFrame: axFrame(x: 0, y: 25, width: 600, height: 775), constrained: false),
                .applied(actualFrame: axFrame(x: 0, y: 25, width: 800, height: 775), constrained: false),
            ]
        )
        let engine = makeEngine(
            focus: ScriptedFocusedWindows(Array(repeating: .found(eligible(window)), count: 3)),
            mutation: mutation
        )

        _ = await engine.perform(.commit(action: .cycleLeftEdge, source: .menuBar))
        _ = await engine.perform(.commit(action: .cycleLeftEdge, source: .menuBar))
        _ = await engine.perform(.commit(action: .cycleLeftEdge, source: .menuBar))

        let targets = await mutation.mutationCalls.map { $0.target.cgRect }
        XCTAssertEqual(targets[0], CGRect(x: 0, y: 25, width: 600, height: 775))
        XCTAssertEqual(targets[1], CGRect(x: 0, y: 25, width: 600, height: 775))
        XCTAssertEqual(targets[2], CGRect(x: 0, y: 25, width: 800, height: 775))
    }

    func testMoveDisplayPlansAndMutatesOnDestinationDisplay() async {
        let window = WindowIdentity()
        let topology = ScriptedWindowActionTopology([
            .available(twoDisplayTopology(generation: 1)),
        ])
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 300, y: 240, width: 600, height: 420)],
            outcomes: [.applied(actualFrame: axFrame(x: 1650, y: 290, width: 900, height: 500), constrained: false)]
        )
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: mutation,
            topology: topology
        )

        let result = await engine.perform(.commit(action: .moveDisplayNext, source: .menuBar))
        let target = await mutation.mutationCalls.first?.target.cgRect

        XCTAssertEqual(result.disposition, .succeeded)
        XCTAssertEqual(target, CGRect(x: 1650, y: 290, width: 900, height: 500))
    }

    func testNativeFullScreenAcceptedButUnverifiedIsNotSuccessOrHistory() async {
        let window = WindowIdentity()
        let native = ScriptedNativeFullScreen([.acceptedButUnverified])
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window)), .found(eligible(window))]),
            mutation: RecordingWindowMutation(frames: [window: axFrame(x: 100, y: 100, width: 400, height: 300)]),
            nativeFullScreen: native
        )

        let result = await engine.perform(.commit(action: .nativeFullScreen, source: .menuBar))
        let undo = await engine.perform(.undo(token: nil, source: .menuBar))
        let nativeWindows = await native.windows

        XCTAssertEqual(result.disposition, .rejected(.mutationRejected))
        XCTAssertNil(result.undoToken)
        XCTAssertEqual(undo.disposition, .rejected(.previewMissingOrExpired))
        XCTAssertEqual(nativeWindows, [window])
    }

    func testTypedFailuresCrossOnlyPerformInterface() async {
        let unknown = ActionID(rawValue: "window.not-installed")
        let window = WindowIdentity()
        let permissionEngine = makeEngine(
            focus: ScriptedFocusedWindows([.unavailable(.permissionRequired)]),
            mutation: RecordingWindowMutation(frames: [:])
        )
        let permissionResult = await permissionEngine.perform(
            .commit(action: .leftHalf, source: .menuBar)
        )
        XCTAssertEqual(permissionResult.disposition, .rejected(.accessibilityPermissionRequired))

        let noWindowEngine = makeEngine(
            focus: ScriptedFocusedWindows([.unavailable(.noEligibleWindow)]),
            mutation: RecordingWindowMutation(frames: [:])
        )
        let noWindowResult = await noWindowEngine.perform(
            .commit(action: .leftHalf, source: .menuBar)
        )
        XCTAssertEqual(noWindowResult.disposition, .rejected(.noFocusedWindow))

        let unknownFocus = ScriptedFocusedWindows([.found(eligible(window))])
        let unknownEngine = makeEngine(
            focus: unknownFocus,
            mutation: RecordingWindowMutation(frames: [window: axFrame(x: 0, y: 0, width: 100, height: 100)])
        )
        let unknownResult = await unknownEngine.perform(.commit(action: unknown, source: .menuBar))
        let unknownCaptureCount = await unknownFocus.captureCount
        XCTAssertEqual(unknownResult.disposition, .rejected(.unknownAction(unknown)))
        XCTAssertEqual(unknownCaptureCount, 0)

        let displayEngine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: RecordingWindowMutation(frames: [window: axFrame(x: 0, y: 0, width: 100, height: 100)]),
            topology: ScriptedWindowActionTopology([.unavailable])
        )
        let displayResult = await displayEngine.perform(.commit(action: .leftHalf, source: .menuBar))
        XCTAssertEqual(displayResult.disposition, .rejected(.displayUnavailable))

        let disabledFocus = ScriptedFocusedWindows([.found(eligible(window))])
        let disabledRegion = try! LayoutRegion(
            id: .leftHalf,
            normalizedFrame: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        )
        let disabledCatalog = WindowActionCatalog(definitions: [
            .init(
                id: .leftHalf,
                operation: .layout(layoutID: "built-in", region: disabledRegion),
                isEnabled: false
            ),
        ])
        let disabledEngine = makeEngine(
            focus: disabledFocus,
            mutation: RecordingWindowMutation(
                frames: [window: axFrame(x: 0, y: 0, width: 100, height: 100)]
            ),
            catalog: disabledCatalog
        )
        let disabledResult = await disabledEngine.perform(
            .commit(action: .leftHalf, source: .menuBar)
        )
        let disabledCaptureCount = await disabledFocus.captureCount
        XCTAssertEqual(disabledResult.disposition, .rejected(.actionDisabled(.leftHalf)))
        XCTAssertEqual(disabledCaptureCount, 0)
    }

    func testDisplayProfileGapIsAppliedByStableDisplayIdentity() async throws {
        let window = WindowIdentity()
        let stableID = try StableDisplayID(rawValue: "uuid:main")
        let profiles = try DisplayProfileLayoutRuntime(
            stableDisplays: FixedStableDisplays([DisplayID(rawValue: 1): stableID]),
            profiles: [
                try DisplayProfile(
                    stableDisplayID: stableID,
                    gap: 20,
                    layoutIDs: ["built-in"]
                ),
            ]
        )
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 100, y: 100, width: 400, height: 300)]
        )
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: mutation,
            profileLayouts: profiles
        )

        let result = await engine.perform(.commit(action: .leftHalf, source: .superMode))
        let calls = await mutation.mutationCalls

        XCTAssertEqual(result.disposition, .succeeded)
        XCTAssertEqual(calls.map(\.target), [axFrame(x: 0, y: 25, width: 590, height: 775)])
    }

    func testDisplayProfileRejectsLayoutOutsideItsStableDisplayLayoutSet() async throws {
        let window = WindowIdentity()
        let stableID = try StableDisplayID(rawValue: "uuid:main")
        let profiles = try DisplayProfileLayoutRuntime(
            stableDisplays: FixedStableDisplays([DisplayID(rawValue: 1): stableID]),
            profiles: [
                try DisplayProfile(stableDisplayID: stableID, gap: 20, layoutIDs: ["writing"]),
            ]
        )
        let mutation = RecordingWindowMutation(
            frames: [window: axFrame(x: 100, y: 100, width: 400, height: 300)]
        )
        let engine = makeEngine(
            focus: ScriptedFocusedWindows([.found(eligible(window))]),
            mutation: mutation,
            profileLayouts: profiles
        )

        let result = await engine.perform(.commit(action: .leftHalf, source: .superMode))
        let calls = await mutation.mutationCalls

        XCTAssertEqual(result.disposition, .rejected(.actionDisabled(.leftHalf)))
        XCTAssertTrue(calls.isEmpty)
    }
}

private extension WindowActionEngineTests {
    func makeEngine(
        focus: any FocusedWindowProviding,
        mutation: any WindowMutationPerforming & CapturedWindowFrameProviding,
        topology: (any WindowActionTopologyProviding)? = nil,
        nativeFullScreen: any NativeFullScreenActionPerforming = ScriptedNativeFullScreen([.rejected]),
        catalog: WindowActionCatalog = .builtIn,
        applicationIdentities: any CapturedWindowApplicationIdentifying = IncludedCapturedWindowApplications(),
        appRules: AppRuleRuntime = AppRuleRuntime(),
        profileLayouts: any DisplayProfileLayoutResolving = DefaultDisplayProfileLayoutResolver()
    ) -> WindowActionEngine {
        let topology = topology ?? ScriptedWindowActionTopology([
            .available(topologySnapshot(generation: 1)),
            .available(topologySnapshot(generation: 1)),
        ])
        return WindowActionEngine(
            focusedWindows: focus,
            topology: topology,
            frames: mutation,
            mutation: mutation,
            history: BoundedSessionWindowHistory(),
            cycles: BoundedSessionCycleGroups(),
            nativeFullScreen: nativeFullScreen,
            catalog: catalog,
            applicationIdentities: applicationIdentities,
            appRules: appRules,
            profileLayouts: profileLayouts
        )
    }

    func policy(excluding bundleIdentifier: String) -> AppRulePolicy {
        AppRulePolicy(rules: [
            AppRule(
                bundleIdentifier: ApplicationBundleIdentifier(bundleIdentifier)!,
                decision: .excluded
            ),
        ])
    }

    func eligible(_ identity: WindowIdentity) -> EligibleWindow {
        EligibleWindow(
            identity: identity,
            capabilities: WindowCapabilities(
                isMovable: true,
                isResizable: true,
                minimized: .inactive,
                nativeFullScreen: .unavailable
            )
        )
    }

    func axFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> AXGlobalTopLeftFrame {
        AXGlobalTopLeftFrame(CGRect(x: x, y: y, width: width, height: height))
    }

    func topologySnapshot(generation: UInt64) -> WindowActionTopologySnapshot {
        WindowActionTopologySnapshot(
            generation: DisplayTopologyGeneration(rawValue: generation),
            topology: DisplayTopologySnapshot(
                displays: [display(id: 1, frame: CGRect(x: 0, y: 0, width: 1200, height: 800), visible: CGRect(x: 0, y: 0, width: 1200, height: 775))],
                primaryDisplayID: DisplayID(rawValue: 1)
            )
        )
    }

    func twoDisplayTopology(generation: UInt64) -> WindowActionTopologySnapshot {
        WindowActionTopologySnapshot(
            generation: DisplayTopologyGeneration(rawValue: generation),
            topology: DisplayTopologySnapshot(
                displays: [
                    display(id: 1, frame: CGRect(x: 0, y: 0, width: 1200, height: 900), visible: CGRect(x: 0, y: 30, width: 1200, height: 840)),
                    display(id: 2, frame: CGRect(x: 1200, y: -200, width: 1800, height: 1100), visible: CGRect(x: 1200, y: -140, width: 1800, height: 1000)),
                ],
                primaryDisplayID: DisplayID(rawValue: 1)
            )
        )
    }

    func display(id: UInt32, frame: CGRect, visible: CGRect) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: visible,
            backingScaleFactor: 1,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            ),
            notchTrigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: frame.midX - 50, y: frame.maxY - 10, width: 100, height: 10)
            )
        )
    }
}

private actor ScriptedCapturedWindowApplications: CapturedWindowApplicationIdentifying {
    private let bundleIdentifiers: [WindowIdentity: String]
    private(set) var requestedWindows: [WindowIdentity] = []

    init(_ bundleIdentifiers: [WindowIdentity: String]) {
        self.bundleIdentifiers = bundleIdentifiers
    }

    func bundleIdentifier(for window: WindowIdentity) -> String? {
        requestedWindows.append(window)
        return bundleIdentifiers[window]
    }
}

private struct IncludedCapturedWindowApplications: CapturedWindowApplicationIdentifying {
    func bundleIdentifier(for window: WindowIdentity) -> String? {
        "com.example.included"
    }
}

private actor ScriptedFocusedWindows: FocusedWindowProviding {
    private var results: [FocusedWindowResult]
    private(set) var captureCount = 0

    init(_ results: [FocusedWindowResult]) {
        precondition(!results.isEmpty)
        self.results = results
    }

    func focusedWindow() -> FocusedWindowResult {
        captureCount += 1
        if results.count == 1 { return results[0] }
        return results.removeFirst()
    }
}

private actor RecordingWindowMutation: WindowMutationPerforming, CapturedWindowFrameProviding {
    struct Call: Sendable {
        let window: WindowIdentity
        let target: AXGlobalTopLeftFrame
        let allowed: AXGlobalTopLeftFrame
    }

    private let frames: [WindowIdentity: AXGlobalTopLeftFrame]
    private var outcomes: [WindowMutationResult]
    private(set) var mutationCalls: [Call] = []

    init(frames: [WindowIdentity: AXGlobalTopLeftFrame], outcomes: [WindowMutationResult] = []) {
        self.frames = frames
        self.outcomes = outcomes
    }

    func currentFrame(window: WindowIdentity) -> CapturedWindowFrameResult {
        guard let frame = frames[window] else { return .failed(.windowDisappeared) }
        return .available(frame)
    }

    func mutate(
        window: WindowIdentity,
        to targetFrame: AXGlobalTopLeftFrame,
        within allowedFrame: AXGlobalTopLeftFrame
    ) -> WindowMutationResult {
        mutationCalls.append(Call(window: window, target: targetFrame, allowed: allowedFrame))
        guard !outcomes.isEmpty else {
            return .applied(actualFrame: targetFrame, constrained: false)
        }
        return outcomes.removeFirst()
    }
}

private actor ScriptedWindowActionTopology: WindowActionTopologyProviding {
    private var results: [WindowActionTopologyResult]

    init(_ results: [WindowActionTopologyResult]) {
        precondition(!results.isEmpty)
        self.results = results
    }

    func captureTopology() -> WindowActionTopologyResult {
        if results.count == 1 { return results[0] }
        return results.removeFirst()
    }
}

private actor GatedWindowActionTopology: WindowActionTopologyProviding {
    private let snapshot: WindowActionTopologySnapshot
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var captureCount = 0

    init(snapshot: WindowActionTopologySnapshot) {
        self.snapshot = snapshot
    }

    func captureTopology() async -> WindowActionTopologyResult {
        captureCount += 1
        if captureCount == 1 {
            await withCheckedContinuation { continuation = $0 }
        }
        return .available(snapshot)
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ScriptedNativeFullScreen: NativeFullScreenActionPerforming {
    private var results: [NativeFullScreenActionResult]
    private(set) var windows: [WindowIdentity] = []

    init(_ results: [NativeFullScreenActionResult]) {
        precondition(!results.isEmpty)
        self.results = results
    }

    func perform(on window: WindowIdentity) -> NativeFullScreenActionResult {
        windows.append(window)
        if results.count == 1 { return results[0] }
        return results.removeFirst()
    }
}

private struct FixedStableDisplays: StableDisplayIdentifying {
    let values: [DisplayID: StableDisplayID]

    init(_ values: [DisplayID: StableDisplayID]) {
        self.values = values
    }

    func stableDisplayID(for displayID: DisplayID) -> StableDisplayID? {
        values[displayID]
    }
}
