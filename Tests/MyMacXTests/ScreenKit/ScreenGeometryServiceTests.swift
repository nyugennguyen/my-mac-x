import CoreGraphics
import XCTest
@testable import MyMacX

final class ScreenGeometryServiceTests: XCTestCase {
    func testReturnsEveryDisplayInDeterministicGeometryOrder() async {
        let adapter = InMemoryScreenGeometryAdapter(
            capture: .displays([
                GeometryFixtures.hkcExternal,
                GeometryFixtures.builtInRetina,
            ])
        )
        let service = ScreenGeometryService(adapter: adapter)

        let result = await service.displays()

        guard case .available(let topology) = result else {
            return XCTFail("Expected available Displays, got \(result)")
        }
        XCTAssertEqual(topology.displays.map(\.id.rawValue), [2, 1])
        XCTAssertEqual(topology.primaryDisplayID, DisplayID(rawValue: 1))
    }

    func testPreservesNegativeOriginGeometryScaleAndSafeAreaWithTopCenterFallback() async {
        let adapter = InMemoryScreenGeometryAdapter(
            capture: .displays([GeometryFixtures.negativeX])
        )
        let service = ScreenGeometryService(adapter: adapter)

        let result = await service.displays()

        XCTAssertEqual(
            result,
            .available(DisplayTopologySnapshot(
                displays: [
                    DisplaySnapshot(
                        id: DisplayID(rawValue: 41),
                        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                        visibleFrame: CGRect(x: -1920, y: 25, width: 1920, height: 1055),
                        backingScaleFactor: 1.5,
                        safeArea: GeometryFixtures.noAuxiliarySafeArea,
                        notchTrigger: NotchTrigger(
                            classification: .topCenterFallback,
                            inferredNotchRegion: nil,
                            region: CGRect(x: -1050, y: 1064, width: 180, height: 16)
                        )
                    ),
                ],
                primaryDisplayID: DisplayID(rawValue: 41)
            ))
        )
    }

    func testRejectsInvalidDisplayGeometryWithTypedFailures() async {
        let displayID = DisplayID(rawValue: 52)
        let cases: [(DisplayGeometryCandidate, ScreenGeometryFailure)] = [
            (
                GeometryFixtures.invalidFrame,
                .invalidFrame(displayID)
            ),
            (
                GeometryFixtures.candidate(
                    id: displayID.rawValue,
                    frame: CGRect(x: CGFloat.infinity, y: 0, width: 1440, height: 900)
                ),
                .invalidFrame(displayID)
            ),
            (
                GeometryFixtures.candidate(
                    id: displayID.rawValue,
                    frame: CGRect(
                        x: CGFloat.greatestFiniteMagnitude,
                        y: 0,
                        width: CGFloat.greatestFiniteMagnitude,
                        height: 900
                    )
                ),
                .invalidFrame(displayID)
            ),
            (
                GeometryFixtures.candidate(
                    id: displayID.rawValue,
                    visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 0)
                ),
                .invalidVisibleFrame(displayID)
            ),
            (
                GeometryFixtures.invalidVisibleFrame,
                .invalidVisibleFrame(displayID)
            ),
            (
                GeometryFixtures.invalidScale,
                .invalidBackingScale(displayID)
            ),
            (
                GeometryFixtures.candidate(id: displayID.rawValue, backingScaleFactor: .nan),
                .invalidBackingScale(displayID)
            ),
        ]

        for (candidate, expectedFailure) in cases {
            let service = ScreenGeometryService(
                adapter: InMemoryScreenGeometryAdapter(capture: .displays([candidate]))
            )

            let result = await service.displays()

            XCTAssertEqual(result, .unavailable(expectedFailure))
        }
    }

    func testInfersNotchTriggerFromValidatedPublicAuxiliaryGap() async {
        let service = ScreenGeometryService(
            adapter: InMemoryScreenGeometryAdapter(
                capture: .displays([
                    GeometryFixtures.builtInRetina,
                ])
            )
        )

        let result = await service.displays()

        guard case .available(let topology) = result,
              let display = topology.displays.first
        else {
            return XCTFail("Expected one available Display, got \(result)")
        }
        XCTAssertEqual(
            display.notchTrigger,
            NotchTrigger(
                classification: .notch,
                inferredNotchRegion: CGRect(x: 2566, y: 1048, width: 179, height: 32),
                region: CGRect(x: 2534, y: 1028, width: 243, height: 52)
            )
        )
    }

    func testRejectsDuplicateDisplayIdentity() async {
        let duplicateID = DisplayID(rawValue: 91)
        let service = ScreenGeometryService(
            adapter: InMemoryScreenGeometryAdapter(
                capture: .displays([
                    GeometryFixtures.candidate(id: duplicateID.rawValue),
                    GeometryFixtures.candidate(
                        id: duplicateID.rawValue,
                        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                        visibleFrame: CGRect(x: 1440, y: 25, width: 1920, height: 1055),
                        isPrimary: false
                    ),
                ])
            )
        )

        let result = await service.displays()

        XCTAssertEqual(result, .unavailable(.duplicateDisplayIdentity(duplicateID)))
    }

    func testRejectsMissingOrMultiplePrimaryMarkers() async {
        let captures: [(ScreenGeometryCapture, ScreenGeometryFailure)] = [
            (
                .displays([
                    GeometryFixtures.candidate(id: 92, isPrimary: false),
                ]),
                .primaryDisplayUnavailable
            ),
            (
                .displays([
                    GeometryFixtures.candidate(id: 93, isPrimary: true),
                    GeometryFixtures.candidate(
                        id: 94,
                        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                        visibleFrame: CGRect(x: 1440, y: 25, width: 1920, height: 1055),
                        isPrimary: true
                    ),
                ]),
                .multiplePrimaryDisplays
            ),
        ]

        for (capture, expectedFailure) in captures {
            let service = ScreenGeometryService(
                adapter: InMemoryScreenGeometryAdapter(capture: capture)
            )

            let result = await service.displays()

            XCTAssertEqual(result, .unavailable(expectedFailure))
        }
    }

    func testReturnsTypedUnavailableStates() async {
        let missingIdentity = DisplayGeometryCandidate(
            displayID: nil,
            isPrimary: true,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875),
            backingScaleFactor: 2,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            )
        )
        let cases: [(ScreenGeometryCapture, ScreenGeometryFailure)] = [
            (.displays([]), .noDisplays),
            (.displays([missingIdentity]), .displayIdentityUnavailable),
            (.failure, .systemUnavailable),
        ]

        for (capture, expectedFailure) in cases {
            let service = ScreenGeometryService(
                adapter: InMemoryScreenGeometryAdapter(capture: capture)
            )

            let result = await service.displays()

            XCTAssertEqual(result, .unavailable(expectedFailure))
        }
    }

    func testFallsBackWhenAuxiliaryAreasDoNotFormAValidatedTopCenterGap() async {
        let service = ScreenGeometryService(
            adapter: InMemoryScreenGeometryAdapter(
                capture: .displays([GeometryFixtures.negativeYWithUnsafeAuxiliaryAreas])
            )
        )

        let result = await service.displays()

        guard case .available(let topology) = result,
              let display = topology.displays.first
        else {
            return XCTFail("Expected one available Display, got \(result)")
        }
        XCTAssertEqual(
            display.notchTrigger,
            NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: 1170, y: -16, width: 180, height: 16)
            )
        )
    }

    func testAcceptsAndClampsHarmlessSubpointVisibleFrameOvershoot() async {
        let service = ScreenGeometryService(
            adapter: InMemoryScreenGeometryAdapter(
                capture: .displays([
                    GeometryFixtures.candidate(
                        id: 121,
                        visibleFrame: CGRect(
                            x: -0.25,
                            y: 24.75,
                            width: 1440.5,
                            height: 875.5
                        )
                    ),
                ])
            )
        )

        let result = await service.displays()

        guard case .available(let topology) = result,
              let display = topology.displays.first
        else {
            return XCTFail("Expected one available Display, got \(result)")
        }
        XCTAssertEqual(
            display.visibleFrame,
            CGRect(x: 0, y: 24.75, width: 1440, height: 875.25)
        )
    }

    func testRejectsVisibleFrameOvershootBeyondLogicalPointTolerance() async {
        let displayID = DisplayID(rawValue: 122)
        let service = ScreenGeometryService(
            adapter: InMemoryScreenGeometryAdapter(
                capture: .displays([
                    GeometryFixtures.candidate(
                        id: displayID.rawValue,
                        visibleFrame: CGRect(x: -0.75, y: 25, width: 1440.75, height: 875)
                    ),
                ])
            )
        )

        let result = await service.displays()

        XCTAssertEqual(result, .unavailable(.invalidVisibleFrame(displayID)))
    }

    func testAcceptsSubpointAuxiliaryAlignmentDriftAndClampsDerivedRegions() async {
        let safeArea = DisplaySafeArea(
            insets: DisplayEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(
                x: -0.25,
                y: 923.75,
                width: 735.5,
                height: 32.5
            ),
            auxiliaryTopRightArea: CGRect(
                x: 825,
                y: 923.75,
                width: 645.25,
                height: 32.5
            )
        )
        let service = ScreenGeometryService(
            adapter: InMemoryScreenGeometryAdapter(
                capture: .displays([
                    GeometryFixtures.candidate(
                        id: 123,
                        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                        visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 923),
                        safeArea: safeArea
                    ),
                ])
            )
        )

        let result = await service.displays()

        guard case .available(let topology) = result,
              let display = topology.displays.first
        else {
            return XCTFail("Expected one available Display, got \(result)")
        }
        XCTAssertEqual(
            display.notchTrigger,
            NotchTrigger(
                classification: .notch,
                inferredNotchRegion: CGRect(x: 735.25, y: 924, width: 89.75, height: 32),
                region: CGRect(x: 703.25, y: 904, width: 153.75, height: 52)
            )
        )
    }

    func testFallsBackWhenAuxiliaryAlignmentDriftExceedsTolerance() async {
        let safeArea = DisplaySafeArea(
            insets: DisplayEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 923.25, width: 646, height: 32),
            auxiliaryTopRightArea: CGRect(x: 825, y: 923.25, width: 645, height: 32)
        )
        let service = ScreenGeometryService(
            adapter: InMemoryScreenGeometryAdapter(
                capture: .displays([
                    GeometryFixtures.candidate(
                        id: 124,
                        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                        visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 923),
                        safeArea: safeArea
                    ),
                ])
            )
        )

        let result = await service.displays()

        guard case .available(let topology) = result,
              let display = topology.displays.first
        else {
            return XCTFail("Expected one available Display, got \(result)")
        }
        XCTAssertEqual(display.notchTrigger.classification, .topCenterFallback)
    }

    func testRejectsNullDirectDisplayIdentityAtThePublicSeam() async {
        let service = ScreenGeometryService(
            adapter: InMemoryScreenGeometryAdapter(
                capture: .displays([
                    GeometryFixtures.candidate(id: 0),
                ])
            )
        )

        let result = await service.displays()

        XCTAssertEqual(result, .unavailable(.displayIdentityUnavailable))
    }
}

final class DisplayTopologyObserverTests: XCTestCase {
    func testEmitsFreshAttachedDisplayTopologyWithIncreasingGeneration() async throws {
        let initial = topology([
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 800)),
        ], primary: 1)
        let attached = topology([
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 800)),
            display(id: 2, frame: CGRect(x: 1_000, y: 0, width: 1_200, height: 900)),
        ], primary: 1)
        let geometry = ScriptedScreenGeometryProvider(results: [
            .available(initial),
            .available(attached),
        ])
        let changes = InMemoryScreenParameterChangeAdapter()
        let observer = DisplayTopologyObserver(geometry: geometry, changes: changes)
        let stream = await observer.updates()
        var iterator = stream.makeAsyncIterator()

        let firstValue = await iterator.next()
        let first = try XCTUnwrap(firstValue)
        await changes.send()
        let secondValue = await iterator.next()
        let second = try XCTUnwrap(secondValue)

        XCTAssertEqual(first, .available(VersionedDisplayTopology(
            generation: DisplayTopologyGeneration(rawValue: 1),
            topology: initial
        )))
        XCTAssertEqual(second, .available(VersionedDisplayTopology(
            generation: DisplayTopologyGeneration(rawValue: 2),
            topology: attached
        )))
    }

    func testTracksDetachSpatialReorderAndPrimaryChangeWithoutCorrelatingReconnectIdentity() async throws {
        let left = display(
            id: 10,
            frame: CGRect(x: -1_200, y: 0, width: 1_200, height: 900)
        )
        let right = display(
            id: 20,
            frame: CGRect(x: 0, y: -100, width: 1_600, height: 1_000)
        )
        let reorderedLeft = display(
            id: 10,
            frame: CGRect(x: 1_600, y: 0, width: 1_200, height: 900)
        )
        let detached = topology([right], primary: 20)
        let reconnectedWithReusedTopologyID = display(
            id: 10,
            frame: CGRect(x: -1_400, y: 50, width: 1_400, height: 1_050)
        )
        let expected = [
            topology([left, right], primary: 10),
            topology([left, right], primary: 20),
            detached,
            topology([right, reorderedLeft], primary: 20),
            topology([reconnectedWithReusedTopologyID, right], primary: 20),
        ]
        let geometry = ScriptedScreenGeometryProvider(
            results: expected.map(ScreenGeometryResult.available)
        )
        let changes = InMemoryScreenParameterChangeAdapter()
        let observer = DisplayTopologyObserver(geometry: geometry, changes: changes)
        let stream = await observer.updates()
        var iterator = stream.makeAsyncIterator()

        var actual: [DisplayTopologyState] = []
        let first = await awaitNext(&iterator)
        actual.append(try XCTUnwrap(first))
        for _ in expected.indices.dropFirst() {
            await changes.send()
            let next = await awaitNext(&iterator)
            actual.append(try XCTUnwrap(next))
        }

        XCTAssertEqual(actual.map(\.generation.rawValue), [1, 2, 3, 4, 5])
        XCTAssertEqual(actual.compactMap(\.availableTopology), expected)
    }

    func testDeduplicatesEquivalentNotificationBurstButStillCapturesFreshGeometry() async throws {
        let initial = topology([
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 800)),
        ], primary: 1)
        let changed = topology([
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 760)),
        ], primary: 1)
        let geometry = ScriptedScreenGeometryProvider(results: [
            .available(initial),
            .available(initial),
            .available(initial),
            .available(changed),
        ])
        let changes = InMemoryScreenParameterChangeAdapter()
        let observer = DisplayTopologyObserver(geometry: geometry, changes: changes)
        let stream = await observer.updates()
        var iterator = stream.makeAsyncIterator()

        let initialUpdate = await awaitNext(&iterator)
        _ = try XCTUnwrap(initialUpdate)
        await changes.send()
        await changes.send()
        await changes.send()
        let nextUpdate = await awaitNext(&iterator)
        let update = try XCTUnwrap(nextUpdate)

        XCTAssertEqual(update.generation.rawValue, 2)
        XCTAssertEqual(update.availableTopology, changed)
        let captureCount = await geometry.captureCount
        XCTAssertEqual(captureCount, 4)
    }

    func testUnavailableCaptureAdvancesGenerationSoPreviewCannotRemainCurrent() async throws {
        let initial = topology([
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 800)),
        ], primary: 1)
        let geometry = ScriptedScreenGeometryProvider(results: [
            .available(initial),
            .unavailable(.systemUnavailable),
        ])
        let changes = InMemoryScreenParameterChangeAdapter()
        let observer = DisplayTopologyObserver(geometry: geometry, changes: changes)
        let stream = await observer.updates()
        var iterator = stream.makeAsyncIterator()

        let initialUpdate = await awaitNext(&iterator)
        _ = try XCTUnwrap(initialUpdate)
        await changes.send()
        let nextUpdate = await awaitNext(&iterator)
        let update = try XCTUnwrap(nextUpdate)

        XCTAssertEqual(update, .unavailable(
            generation: DisplayTopologyGeneration(rawValue: 2),
            failure: .systemUnavailable
        ))
    }

    func testCancellingConsumerCancelsSystemObservationWithoutLeak() async {
        let initial = topology([
            display(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 800)),
        ], primary: 1)
        let geometry = ScriptedScreenGeometryProvider(results: [.available(initial)])
        let changes = InMemoryScreenParameterChangeAdapter()
        let observer = DisplayTopologyObserver(geometry: geometry, changes: changes)
        let stream = await observer.updates()
        let consumer = Task {
            for await _ in stream {}
        }

        consumer.cancel()
        await consumer.value
        for _ in 0..<100 where await changes.cancellationCount == 0 {
            await Task.yield()
        }

        let cancellationCount = await changes.cancellationCount
        let hasActiveObservation = await changes.hasActiveObservation
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertFalse(hasActiveObservation)
    }

    private func awaitNext(
        _ iterator: inout AsyncStream<DisplayTopologyState>.Iterator
    ) async -> DisplayTopologyState? {
        await iterator.next()
    }

    private func topology(
        _ displays: [DisplaySnapshot],
        primary: UInt32
    ) -> DisplayTopologySnapshot {
        DisplayTopologySnapshot(
            displays: displays,
            primaryDisplayID: DisplayID(rawValue: primary)
        )
    }

    private func display(
        id: UInt32,
        frame: CGRect,
        visibleFrame: CGRect? = nil
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: visibleFrame ?? frame,
            backingScaleFactor: 1,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            ),
            notchTrigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: frame.midX - 1, y: frame.maxY - 1, width: 2, height: 1)
            )
        )
    }
}

final class DisplayTopologyReconcilerTests: XCTestCase {
    func testPreviewRemainsValidOnlyAtTheExactAvailableGeneration() {
        let generation = DisplayTopologyGeneration(rawValue: 7)
        let topology = topologyWithNegativeOrigin()

        XCTAssertTrue(DisplayTopologyReconciler.previewRemainsValid(
            capturedAt: generation,
            current: .available(VersionedDisplayTopology(
                generation: generation,
                topology: topology
            ))
        ))
        XCTAssertFalse(DisplayTopologyReconciler.previewRemainsValid(
            capturedAt: generation,
            current: .available(VersionedDisplayTopology(
                generation: DisplayTopologyGeneration(rawValue: 8),
                topology: topology
            ))
        ))
        XCTAssertFalse(DisplayTopologyReconciler.previewRemainsValid(
            capturedAt: generation,
            current: .unavailable(
                generation: DisplayTopologyGeneration(rawValue: 8),
                failure: .systemUnavailable
            )
        ))
    }

    func testRemapsDetachedOversizedRestoreTargetIntoNearestCurrentVisibleFrame() throws {
        let result = DisplayTopologyReconciler.restoreTarget(
            CGRect(x: 3_000, y: 200, width: 1_500, height: 1_000),
            in: topologyWithNegativeOrigin()
        )

        let reconciliation = try XCTUnwrap(result.success)
        XCTAssertEqual(reconciliation.frame, CGRect(x: 0, y: 25, width: 1_000, height: 775))
        XCTAssertTrue(reconciliation.wasAdjusted)
    }

    func testClampsRestoreTargetWithinNegativeOriginVisibleFrame() throws {
        let result = DisplayTopologyReconciler.restoreTarget(
            CGRect(x: -1_900, y: -400, width: 600, height: 500),
            in: topologyWithNegativeOrigin()
        )

        let reconciliation = try XCTUnwrap(result.success)
        XCTAssertEqual(
            reconciliation.frame,
            CGRect(x: -1_600, y: -150, width: 600, height: 500)
        )
        XCTAssertTrue(reconciliation.wasAdjusted)
    }

    func testKeepsAlreadyVisibleRestoreTargetAndRejectsInvalidGeometry() throws {
        let visibleTarget = CGRect(x: -1_400, y: 0, width: 500, height: 400)

        let unchanged = try XCTUnwrap(DisplayTopologyReconciler.restoreTarget(
            visibleTarget,
            in: topologyWithNegativeOrigin()
        ).success)
        XCTAssertEqual(unchanged.frame, visibleTarget)
        XCTAssertFalse(unchanged.wasAdjusted)

        let invalid = DisplayTopologyReconciler.restoreTarget(
            CGRect(x: CGFloat.nan, y: 0, width: 500, height: 400),
            in: topologyWithNegativeOrigin()
        )
        XCTAssertEqual(
            invalid.failure,
            RestoreTargetReconciliationFailure.invalidRestoreTarget
        )
    }

    private func topologyWithNegativeOrigin() -> DisplayTopologySnapshot {
        DisplayTopologySnapshot(
            displays: [
                display(
                    id: 41,
                    frame: CGRect(x: -1_600, y: -200, width: 1_200, height: 900),
                    visibleFrame: CGRect(x: -1_600, y: -150, width: 1_200, height: 850)
                ),
                display(
                    id: 42,
                    frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                    visibleFrame: CGRect(x: 0, y: 25, width: 1_000, height: 775)
                ),
            ],
            primaryDisplayID: DisplayID(rawValue: 42)
        )
    }

    private func display(
        id: UInt32,
        frame: CGRect,
        visibleFrame: CGRect
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: visibleFrame,
            backingScaleFactor: 1,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            ),
            notchTrigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: CGRect(x: frame.midX - 1, y: frame.maxY - 1, width: 2, height: 1)
            )
        )
    }
}

private extension DisplayTopologyState {
    var availableTopology: DisplayTopologySnapshot? {
        guard case .available(let versioned) = self else { return nil }
        return versioned.topology
    }
}

private extension Result {
    var success: Success? {
        guard case .success(let value) = self else { return nil }
        return value
    }

    var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
