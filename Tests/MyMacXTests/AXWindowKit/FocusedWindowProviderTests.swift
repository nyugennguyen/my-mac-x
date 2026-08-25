import ApplicationServices
import XCTest
@testable import MyMacX

final class FocusedWindowProviderTests: XCTestCase {
    func testReturnsTheFocusedEligibleWindowWithItsCapturedCapabilities() async {
        let identity = WindowIdentity()
        let capabilities = WindowCapabilities(
            isMovable: true,
            isResizable: false,
            minimized: .inactive,
            nativeFullScreen: .inactive
        )
        let adapter = ScriptedWindowAdapter(
            captures: [
                .candidate(
                    AccessibilityWindowCandidate(
                        identity: identity,
                        capabilities: capabilities
                    )
                ),
            ]
        )
        let provider = FocusedWindowProvider(adapter: adapter)

        let result = await provider.focusedWindow()

        XCTAssertEqual(
            result,
            .found(
                EligibleWindow(
                    identity: identity,
                    kind: .standard,
                    capabilities: capabilities
                )
            )
        )
    }

    func testReturnsAnEligibleDialogWithoutRetargetingItsIdentity() async {
        let identity = WindowIdentity()
        let capabilities = WindowCapabilities(
            isMovable: true,
            isResizable: false,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [
                .candidate(
                    AccessibilityWindowCandidate(
                        identity: identity,
                        kind: .dialog,
                        capabilities: capabilities
                    )
                ),
            ]
        )

        let result = await FocusedWindowProvider(adapter: adapter).focusedWindow()

        XCTAssertEqual(
            result,
            .found(
                EligibleWindow(
                    identity: identity,
                    kind: .dialog,
                    capabilities: capabilities
                )
            )
        )
    }

    func testRejectsAWindowThatCannotParticipateInAnyWindowAction() async {
        let adapter = ScriptedWindowAdapter(
            captures: [
                .candidate(
                    AccessibilityWindowCandidate(
                        identity: WindowIdentity(),
                        capabilities: WindowCapabilities(
                            isMovable: false,
                            isResizable: false,
                            minimized: .inactive,
                            nativeFullScreen: .inactive
                        )
                    )
                ),
            ]
        )
        let provider = FocusedWindowProvider(adapter: adapter)

        let result = await provider.focusedWindow()

        XCTAssertEqual(result, .unavailable(.noEligibleWindow))
    }

    func testMinimizedStateAloneDoesNotMakeAWindowEligible() async {
        let adapter = ScriptedWindowAdapter(
            captures: [
                .candidate(
                    AccessibilityWindowCandidate(
                        identity: WindowIdentity(),
                        capabilities: WindowCapabilities(
                            isMovable: false,
                            isResizable: false,
                            minimized: .active,
                            nativeFullScreen: .inactive
                        )
                    )
                ),
            ]
        )
        let provider = FocusedWindowProvider(adapter: adapter)

        let result = await provider.focusedWindow()

        XCTAssertEqual(result, .unavailable(.noEligibleWindow))
    }

    func testEachSafePlacementCapabilityCanMakeAWindowEligible() async {
        let capabilities = [
            WindowCapabilities(
                isMovable: true,
                isResizable: false,
                minimized: .inactive,
                nativeFullScreen: .inactive
            ),
            WindowCapabilities(
                isMovable: false,
                isResizable: true,
                minimized: .inactive,
                nativeFullScreen: .inactive
            ),
        ]

        for capability in capabilities {
            let identity = WindowIdentity()
            let adapter = ScriptedWindowAdapter(
                captures: [
                    .candidate(
                        AccessibilityWindowCandidate(
                            identity: identity,
                            capabilities: capability
                        )
                    ),
                ]
            )
            let provider = FocusedWindowProvider(adapter: adapter)

            let result = await provider.focusedWindow()

            XCTAssertEqual(
                result,
                .found(EligibleWindow(identity: identity, capabilities: capability))
            )
        }
    }

    func testKnownNativeFullScreenWindowIsNotEligibleForPlacement() async {
        let adapter = ScriptedWindowAdapter(
            captures: [
                .candidate(
                    AccessibilityWindowCandidate(
                        identity: WindowIdentity(),
                        capabilities: WindowCapabilities(
                            isMovable: true,
                            isResizable: true,
                            minimized: .inactive,
                            nativeFullScreen: .active
                        )
                    )
                ),
            ]
        )

        let result = await FocusedWindowProvider(adapter: adapter).focusedWindow()

        XCTAssertEqual(result, .unavailable(.noEligibleWindow))
    }

    func testKnownMinimizedWindowIsNotEligibleForPlacement() async {
        let adapter = ScriptedWindowAdapter(
            captures: [
                .candidate(
                    AccessibilityWindowCandidate(
                        identity: WindowIdentity(),
                        capabilities: WindowCapabilities(
                            isMovable: true,
                            isResizable: true,
                            minimized: .active,
                            nativeFullScreen: .unavailable
                        )
                    )
                ),
            ]
        )

        let result = await FocusedWindowProvider(adapter: adapter).focusedWindow()

        XCTAssertEqual(result, .unavailable(.noEligibleWindow))
    }

    func testMapsAnUnsupportedFocusedElementToNoEligibleWindow() async {
        let adapter = ScriptedWindowAdapter(
            captures: [.unsupported]
        )
        let provider = FocusedWindowProvider(adapter: adapter)

        let result = await provider.focusedWindow()

        XCTAssertEqual(result, .unavailable(.noEligibleWindow))
    }

    func testPreservesEveryNativeFullScreenKnowledgeState() async {
        for state in [
            NativeFullScreenState.inactive,
            .unavailable,
        ] {
            let capabilities = WindowCapabilities(
                isMovable: true,
                isResizable: true,
                minimized: .inactive,
                nativeFullScreen: state
            )
            let adapter = ScriptedWindowAdapter(
                captures: [
                    .candidate(
                        AccessibilityWindowCandidate(
                            identity: WindowIdentity(),
                            capabilities: capabilities
                        )
                    ),
                ]
            )
            let provider = FocusedWindowProvider(adapter: adapter)

            let result = await provider.focusedWindow()

            guard case .found(let window) = result else {
                return XCTFail("Expected an Eligible Window for state \(state)")
            }
            XCTAssertEqual(window.capabilities.nativeFullScreen, state)
        }
    }

    func testPreservesEveryMinimizedKnowledgeState() async {
        for state in [
            WindowMinimizedState.inactive,
            .unavailable,
        ] {
            let capabilities = WindowCapabilities(
                isMovable: true,
                isResizable: true,
                minimized: state,
                nativeFullScreen: .unavailable
            )
            let adapter = ScriptedWindowAdapter(
                captures: [
                    .candidate(
                        AccessibilityWindowCandidate(
                            identity: WindowIdentity(),
                            capabilities: capabilities
                        )
                    ),
                ]
            )
            let provider = FocusedWindowProvider(adapter: adapter)

            let result = await provider.focusedWindow()

            guard case .found(let window) = result else {
                return XCTFail("Expected an Eligible Window for state \(state)")
            }
            XCTAssertEqual(window.capabilities.minimized, state)
        }
    }

    func testReturnsTypedFailureWhenAccessibilityCaptureFails() async {
        let adapter = ScriptedWindowAdapter(
            captures: [.failure(.temporarilyUnavailable)]
        )
        let provider = FocusedWindowProvider(adapter: adapter)

        let result = await provider.focusedWindow()

        XCTAssertEqual(result, .unavailable(.temporarilyUnavailable))
    }

    func testCapturesFocusOnlyOncePerRequest() async {
        let firstIdentity = WindowIdentity()
        let secondIdentity = WindowIdentity()
        let capabilities = WindowCapabilities(
            isMovable: true,
            isResizable: true,
            minimized: .inactive,
            nativeFullScreen: .unavailable
        )
        let adapter = ScriptedWindowAdapter(
            captures: [
                .candidate(
                    AccessibilityWindowCandidate(
                        identity: firstIdentity,
                        capabilities: capabilities
                    )
                ),
                .candidate(
                    AccessibilityWindowCandidate(
                        identity: secondIdentity,
                        capabilities: capabilities
                    )
                ),
            ]
        )
        let provider = FocusedWindowProvider(adapter: adapter)

        let result = await provider.focusedWindow()
        let captureCount = await adapter.captureCount

        XCTAssertEqual(
            result,
            .found(EligibleWindow(identity: firstIdentity, capabilities: capabilities))
        )
        XCTAssertEqual(captureCount, 1)
    }
}

final class WindowIdentityCacheTests: XCTestCase {
    func testReusesIdentityForTheSameElement() {
        var cache = WindowIdentityCache<Int>(capacity: 2, areEquivalent: ==)

        let first = cache.identity(for: 7)
        let second = cache.identity(for: 7)

        XCTAssertEqual(first, second)
    }

    func testAssignsDistinctIdentitiesToDistinctElements() {
        var cache = WindowIdentityCache<Int>(capacity: 2, areEquivalent: ==)

        let first = cache.identity(for: 7)
        let second = cache.identity(for: 8)

        XCTAssertNotEqual(first, second)
    }

    func testEvictsTheLeastRecentlyUsedElementAtCapacity() {
        var cache = WindowIdentityCache<Int>(capacity: 2, areEquivalent: ==)
        let firstIdentity = cache.identity(for: 7)
        let secondIdentity = cache.identity(for: 8)
        _ = cache.identity(for: 7)

        _ = cache.identity(for: 9)

        XCTAssertEqual(cache.identity(for: 7), firstIdentity)
        XCTAssertNotEqual(cache.identity(for: 8), secondIdentity)
    }

    func testResolvesTheElementForAnOpaqueIdentityWithoutRetargeting() {
        var cache = WindowIdentityCache<Int>(capacity: 2, areEquivalent: ==)
        let firstIdentity = cache.identity(for: 7)
        _ = cache.identity(for: 8)

        let resolved = cache.element(for: firstIdentity)

        XCTAssertEqual(resolved, 7)
    }
}

final class AXWindowEligibilityTests: XCTestCase {
    func testClassifiesOnlyDocumentedWindowRolesAndSubroles() {
        XCTAssertEqual(
            AXWindowEligibility.kind(
                role: kAXWindowRole as String,
                subrole: kAXStandardWindowSubrole as String
            ),
            .standard
        )
        XCTAssertEqual(
            AXWindowEligibility.kind(
                role: kAXWindowRole as String,
                subrole: kAXDialogSubrole as String
            ),
            .dialog
        )
        XCTAssertEqual(
            AXWindowEligibility.kind(
                role: kAXWindowRole as String,
                subrole: kAXSystemDialogSubrole as String
            ),
            .dialog
        )
        XCTAssertEqual(
            AXWindowEligibility.kind(
                role: kAXSheetRole as String,
                subrole: nil
            ),
            .sheet
        )
        XCTAssertNil(
            AXWindowEligibility.kind(
                role: kAXWindowRole as String,
                subrole: kAXFloatingWindowSubrole as String
            )
        )
    }
}

final class SystemWindowAdapterPolicyTests: XCTestCase {
    func testSynchronousAccessibilityMessagesUseAFinitePositiveTimeout() {
        let timeout = SystemWindowAdapter.messagingTimeoutSeconds

        XCTAssertTrue(timeout.isFinite)
        XCTAssertGreaterThan(timeout, 0)
    }

    func testTargetAndRollbackUseTheSafePublicAXWriteOrders() {
        XCTAssertEqual(AXFrameWriteOrdering.attributes(for: .target), [.size, .position])
        XCTAssertEqual(AXFrameWriteOrdering.attributes(for: .rollback), [.position, .size])
        XCTAssertEqual(
            AXFrameWriteOrdering.attributes(for: .target, axes: .position),
            [.position]
        )
        XCTAssertEqual(
            AXFrameWriteOrdering.attributes(for: .rollback, axes: .size),
            [.size]
        )
    }
}

final class AXFocusedApplicationFallbackPolicyTests: XCTestCase {
    func testCannotCompleteUsesTheBoundedFrontmostApplicationFallback() {
        XCTAssertTrue(
            AXFocusedApplicationFallbackPolicy.shouldFallback(after: .cannotComplete)
        )
    }

    func testMissingSystemWideFocusUsesTheFallback() {
        XCTAssertTrue(
            AXFocusedApplicationFallbackPolicy.shouldFallback(after: .noValue)
        )
    }

    func testPermissionFailureDoesNotUseTheFallback() {
        XCTAssertFalse(
            AXFocusedApplicationFallbackPolicy.shouldFallback(after: .apiDisabled)
        )
    }
}
