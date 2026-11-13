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

import XCTest
@testable import MyMacX

final class SuperModeAdvancedActionsTests: XCTestCase {
    func testBuiltInCatalogResolvesEveryRequiredAdvancedAction() {
        let resolver = SuperModeAdvancedActionResolver(windowActions: .builtIn)

        for id in [ActionID.restore, .cycleLeftEdge, .moveDisplayNext, .moveDisplayPrevious] {
            guard case let .window(descriptor) = resolver.resolve(id) else {
                return XCTFail("Expected registered Window Action: \(id.rawValue)")
            }
            XCTAssertEqual(descriptor.id, id)
        }
        XCTAssertEqual(resolver.resolve(.openSettings), .app(.openSettings))
        XCTAssertEqual(resolver.resolve(.toggleGaps), .app(.toggleGaps))
        XCTAssertEqual(resolver.resolve(.selectProfile), .app(.selectProfile))
    }

    func testAdvancedWindowActionDispatchesExactlyOnceThroughWindowActionInterface() async {
        let windowActions = RecordingSuperModeWindowActions()
        let dispatcher = SuperModeAdvancedActionDispatcher(
            actionRegistry: .builtIn,
            windowActions: windowActions
        )

        let result = await dispatcher.dispatch(.restore)
        guard case .dispatched = result else { return XCTFail("Expected dispatch") }

        let commits = await windowActions.recordedCommits()
        XCTAssertEqual(
            commits,
            [SuperModeRecordedCommit(action: .restore, source: .superMode)]
        )
    }

    func testOpenSettingsDispatchesThroughAppActionAdapterWithoutWindowDispatch() async {
        let windowActions = RecordingSuperModeWindowActions()
        let appActions = RecordingSuperModeAppActions()
        let dispatcher = SuperModeAdvancedActionDispatcher(
            actionRegistry: .builtIn,
            windowActions: windowActions,
            appActionPerformer: appActions
        )

        let result = await dispatcher.dispatch(.openSettings)
        let recordedAppActions = await appActions.recordedActions()
        let recordedWindowActions = await windowActions.recordedCommits()

        XCTAssertEqual(result, .dispatchedAppAction(.openSettings))
        XCTAssertEqual(recordedAppActions, [.openSettings])
        XCTAssertEqual(recordedWindowActions, [])
    }

    func testMissingOptionalAppAdaptersAndUnknownIDsFailClosedWithoutWindowDispatch() async {
        let windowActions = RecordingSuperModeWindowActions()
        let dispatcher = SuperModeAdvancedActionDispatcher(
            actionRegistry: .builtIn,
            windowActions: windowActions
        )

        let gapsResult = await dispatcher.dispatch(.toggleGaps)
        let profileResult = await dispatcher.dispatch(.selectProfile)
        let unknownResult = await dispatcher.dispatch(ActionID(rawValue: "unknown.action"))
        let commits = await windowActions.recordedCommits()

        XCTAssertEqual(
            gapsResult,
            .unavailable(.productionAdapterUnavailable(.toggleGaps))
        )
        XCTAssertEqual(
            profileResult,
            .unavailable(.productionAdapterUnavailable(.selectProfile))
        )
        XCTAssertEqual(unknownResult, .unavailable(.notRegistered))
        XCTAssertEqual(commits, [])
    }

    func testProductionAdapterPerformsGapAndProfileActionsThroughRuntimeClosures() async {
        let recorder = RecordingProductionAppActionClosures()
        let adapter = SuperModeAppActionAdapter(
            openSettings: {},
            toggleGaps: { await recorder.record(.toggleGaps); return true },
            selectProfile: { await recorder.record(.selectProfile); return true }
        )

        let gapsSucceeded = await adapter.perform(.toggleGaps)
        let profileSucceeded = await adapter.perform(.selectProfile)

        XCTAssertTrue(gapsSucceeded)
        XCTAssertTrue(profileSucceeded)
        let actions = await recorder.recordedActions()
        XCTAssertEqual(actions, [.toggleGaps, .selectProfile])
    }
}

private actor RecordingSuperModeAppActions: SuperModeAppActionPerforming {
    private var actions: [SuperModeAppAction] = []

    func perform(_ action: SuperModeAppAction) async -> Bool {
        actions.append(action)
        return true
    }

    func recordedActions() -> [SuperModeAppAction] {
        actions
    }
}

private actor RecordingProductionAppActionClosures {
    private(set) var actions: [SuperModeAppAction] = []

    func record(_ action: SuperModeAppAction) {
        actions.append(action)
    }

    func recordedActions() -> [SuperModeAppAction] {
        actions
    }
}
