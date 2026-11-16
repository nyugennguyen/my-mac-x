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

import Foundation
import CoreGraphics

public actor WindowActionEngine: WindowActionPerforming {
    private struct CapturedBinding: Sendable {
        let window: WindowIdentity
        let topology: WindowActionTopologySnapshot
        let currentFrame: AppKitGlobalLogicalFrame
    }

    private enum CapturedBindingResult: Sendable {
        case available(CapturedBinding)
        case failed(WindowActionFailure)
    }

    private struct PlacementPlan: Sendable {
        let window: WindowIdentity
        let topology: WindowActionTopologySnapshot
        let before: AppKitGlobalLogicalFrame
        let target: AppKitGlobalLogicalFrame
        let allowed: AppKitGlobalLogicalFrame
        let displayID: DisplayID
        let constrained: Bool
        let historyPlacement: WindowHistoryPlacement
        let warnings: [WindowActionResult.Warning]
        let action: ActionID?

        func replacingBefore(_ frame: AppKitGlobalLogicalFrame) -> Self {
            Self(
                window: window,
                topology: topology,
                before: frame,
                target: target,
                allowed: allowed,
                displayID: displayID,
                constrained: constrained,
                historyPlacement: historyPlacement,
                warnings: warnings,
                action: action
            )
        }
    }

    private struct PreviewEntry: Sendable {
        let binding: Task<CapturedBindingResult, Never>
        let capturedWindow: WindowIdentity?
        let catalog: WindowActionCatalog
        var revision: UInt64
        var plan: PlacementPlan?
    }

    private let focusedWindows: any FocusedWindowProviding
    private let topology: any WindowActionTopologyProviding
    private let frames: any CapturedWindowFrameProviding
    private let mutation: any WindowMutationPerforming
    private let history: any WindowHistoryManaging
    private let cycles: any CycleGroupManaging
    private let nativeFullScreen: any NativeFullScreenActionPerforming
    private let applicationIdentities: any CapturedWindowApplicationIdentifying
    private let appRules: any AppRuleDeciding
    private let profileLayouts: any DisplayProfileLayoutResolving
    private let catalog: WindowActionCatalog
    private let layoutCalculator = LayoutCalculator()
    private let displayMovePlanner = DisplayMovePlanner()

    private var previews: [InteractionID: PreviewEntry] = [:]
    private var busyWindows: Set<WindowIdentity> = []
    private var windowWaiters: [WindowIdentity: [CheckedContinuation<Void, Never>]] = [:]

    public init(appRules: AppRuleRuntime = AppRuleRuntime()) {
        let accessibility = SystemWindowAdapter.shared
        focusedWindows = FocusedWindowProvider(adapter: accessibility)
        topology = ObservedWindowActionTopologyAdapter(observer: DisplayTopologyObserver())
        frames = AccessibilityCapturedWindowFrameAdapter(adapter: accessibility)
        mutation = WindowMutationModule(adapter: accessibility)
        history = BoundedSessionWindowHistory()
        cycles = BoundedSessionCycleGroups()
        nativeFullScreen = NativeFullScreenActionStrategy(adapter: accessibility)
        applicationIdentities = accessibility
        self.appRules = appRules
        profileLayouts = DefaultDisplayProfileLayoutResolver()
        catalog = .builtIn
    }

    init(
        appRules: AppRuleRuntime,
        profileLayouts: any DisplayProfileLayoutResolving
    ) {
        let accessibility = SystemWindowAdapter.shared
        focusedWindows = FocusedWindowProvider(adapter: accessibility)
        topology = ObservedWindowActionTopologyAdapter(observer: DisplayTopologyObserver())
        frames = AccessibilityCapturedWindowFrameAdapter(adapter: accessibility)
        mutation = WindowMutationModule(adapter: accessibility)
        history = BoundedSessionWindowHistory()
        cycles = BoundedSessionCycleGroups()
        nativeFullScreen = NativeFullScreenActionStrategy(adapter: accessibility)
        applicationIdentities = accessibility
        self.appRules = appRules
        self.profileLayouts = profileLayouts
        catalog = .builtIn
    }

    init(
        focusedWindows: any FocusedWindowProviding,
        topology: any WindowActionTopologyProviding,
        frames: any CapturedWindowFrameProviding,
        mutation: any WindowMutationPerforming,
        history: any WindowHistoryManaging,
        cycles: any CycleGroupManaging,
        nativeFullScreen: any NativeFullScreenActionPerforming,
        catalog: WindowActionCatalog = .builtIn,
        applicationIdentities: any CapturedWindowApplicationIdentifying,
        appRules: any AppRuleDeciding,
        profileLayouts: any DisplayProfileLayoutResolving = DefaultDisplayProfileLayoutResolver()
    ) {
        self.focusedWindows = focusedWindows
        self.topology = topology
        self.frames = frames
        self.mutation = mutation
        self.history = history
        self.cycles = cycles
        self.nativeFullScreen = nativeFullScreen
        self.catalog = catalog
        self.applicationIdentities = applicationIdentities
        self.appRules = appRules
        self.profileLayouts = profileLayouts
    }

    public func perform(_ intent: WindowIntent) async -> WindowActionResult {
        switch intent {
        case let .preview(action, interaction, capturedWindow, targetDisplay):
            return await preview(
                action: action,
                interaction: interaction,
                capturedWindow: capturedWindow,
                targetDisplay: targetDisplay
            )
        case let .commit(action, _):
            return await directCommit(action: action)
        case let .commitPreview(interaction, acceptancePolicy):
            return await commitPreview(interaction: interaction, acceptancePolicy: acceptancePolicy)
        case .cancelPreview(let interaction):
            return cancelPreview(interaction: interaction)
        case let .undo(token, _):
            return await undo(token: token)
        }
    }

    private func preview(
        action: ActionID,
        interaction: InteractionID,
        capturedWindow: WindowIdentity?,
        targetDisplay: DisplayID? = nil
    ) async -> WindowActionResult {
        let revision: UInt64
        let bindingTask: Task<CapturedBindingResult, Never>
        let snapshotCatalog: WindowActionCatalog

        if var entry = previews[interaction] {
            guard entry.capturedWindow == capturedWindow else {
                return .superseded
            }
            entry.revision &+= 1
            entry.plan = nil
            revision = entry.revision
            bindingTask = entry.binding
            snapshotCatalog = entry.catalog
            previews[interaction] = entry
        } else {
            snapshotCatalog = catalog
            guard let definition = snapshotCatalog.definition(for: action) else {
                return .rejected(.unknownAction(action))
            }
            guard definition.isEnabled, definition.supportsPreview else {
                return .rejected(.actionDisabled(action))
            }

            let topology = topology
            let frames = frames
            let applicationIdentities = applicationIdentities
            let appRules = appRules
            if let capturedWindow {
                bindingTask = Task {
                    await Self.captureBinding(
                        capturedWindow: capturedWindow,
                        topology: topology,
                        frames: frames,
                        applicationIdentities: applicationIdentities,
                        appRules: appRules
                    )
                }
            } else {
                let focusedWindows = focusedWindows
                bindingTask = Task {
                    await Self.captureBinding(
                        focusedWindows: focusedWindows,
                        topology: topology,
                        frames: frames,
                        applicationIdentities: applicationIdentities,
                        appRules: appRules
                    )
                }
            }
            revision = 1
            previews[interaction] = PreviewEntry(
                binding: bindingTask,
                capturedWindow: capturedWindow,
                catalog: snapshotCatalog,
                revision: revision,
                plan: nil
            )
        }

        guard let definition = snapshotCatalog.definition(for: action) else {
            previews.removeValue(forKey: interaction)
            return .rejected(.unknownAction(action))
        }
        guard definition.isEnabled, definition.supportsPreview else {
            previews.removeValue(forKey: interaction)
            return .rejected(.actionDisabled(action))
        }

        let captured = await bindingTask.value
        guard var entry = previews[interaction], entry.revision == revision else {
            return .superseded
        }

        let binding: CapturedBinding
        switch captured {
        case .available(let value):
            binding = value
        case .failed(let failure):
            previews.removeValue(forKey: interaction)
            return .rejected(failure)
        }

        let plan: PlacementPlan
        switch await compile(
            definition: definition,
            binding: binding,
            targetDisplay: targetDisplay
        ) {
        case .success(let value):
            plan = value
        case .failure(let failure):
            previews.removeValue(forKey: interaction)
            return .rejected(failure)
        }

        entry.plan = plan
        previews[interaction] = entry
        return WindowActionResult(
            disposition: .succeeded,
            effect: .preview(
                frame: plan.target.cgRect,
                displayID: plan.displayID.rawValue,
                constrained: plan.constrained
            ),
            undoToken: nil,
            warnings: plan.warnings
        )
    }

    private func directCommit(action: ActionID) async -> WindowActionResult {
        guard let definition = catalog.definition(for: action) else {
            return .rejected(.unknownAction(action))
        }
        guard definition.isEnabled else {
            return .rejected(.actionDisabled(action))
        }

        let eligible: EligibleWindow
        switch await captureFocusedWindow() {
        case .success(let value):
            eligible = value
        case .failure(let failure):
            return .rejected(failure)
        }

        await acquire(window: eligible.identity)
        defer { release(window: eligible.identity) }

        guard await isIncluded(window: eligible.identity) else {
            return .rejected(.applicationExcluded)
        }

        if case .nativeFullScreen = definition.operation {
            let result = await nativeFullScreen.perform(on: eligible.identity)
            return mapNativeFullScreen(result)
        }

        let binding: CapturedBinding
        switch await captureBinding(for: eligible) {
        case .available(let value):
            binding = value
        case .failed(let failure):
            return .rejected(failure)
        }

        switch definition.operation {
        case .restore:
            guard let anchor = await history.restore(for: eligible.identity) else {
                return .rejected(.previewMissingOrExpired)
            }
            switch planForExistingTarget(anchor.frame, binding: binding, placement: .nonLayout) {
            case .success(let plan):
                return await execute(plan: plan, cycle: nil)
            case .failure(let failure):
                return .rejected(failure)
            }

        case .cycle(let group):
            let staging = await cycles.stageNext(window: eligible.identity, in: group)
            guard let stagedDefinition = catalog.definition(for: staging.action) else {
                await cycles.discard(staging)
                return .rejected(.unknownAction(staging.action))
            }
            switch await compile(definition: stagedDefinition, binding: binding) {
            case .success(let plan):
                return await execute(plan: plan, cycle: staging)
            case .failure(let failure):
                await cycles.discard(staging)
                return .rejected(failure)
            }

        case .layout, .moveDisplay:
            switch await compile(definition: definition, binding: binding) {
            case .success(let plan):
                return await execute(plan: plan, cycle: nil)
            case .failure(let failure):
                return .rejected(failure)
            }

        case .nativeFullScreen:
            return .rejected(.mutationRejected)
        }
    }

    private func commitPreview(
        interaction: InteractionID,
        acceptancePolicy: EdgeSnapAcceptancePolicy? = nil
    ) async -> WindowActionResult {
        guard let entry = previews.removeValue(forKey: interaction),
              let originalPlan = entry.plan else {
            return .rejected(.previewMissingOrExpired)
        }

        await acquire(window: originalPlan.window)
        defer { release(window: originalPlan.window) }

        guard await isIncluded(window: originalPlan.window) else {
            return .rejected(.applicationExcluded)
        }

        guard case let .available(freshTopology) = await topology.captureTopology(),
              freshTopology.generation == originalPlan.topology.generation else {
            return .rejected(.previewMissingOrExpired)
        }

        let currentAX: AXGlobalTopLeftFrame
        switch await frames.currentFrame(window: originalPlan.window) {
        case .available(let frame):
            currentAX = frame
        case .failed(let failure):
            return .rejected(Self.map(failure))
        }
        guard let converter = try? CoordinateConverter(
            topology: CoordinateSpaceTopology(freshTopology.topology)
        ), let current = try? converter.convert(currentAX) else {
            return .rejected(.displayUnavailable)
        }

        return await execute(
            plan: originalPlan.replacingBefore(current),
            cycle: nil,
            acceptancePolicy: acceptancePolicy
        )
    }

    private func cancelPreview(interaction: InteractionID) -> WindowActionResult {
        previews.removeValue(forKey: interaction)?.binding.cancel()
        return .cancelled
    }

    private func undo(token: UndoToken?) async -> WindowActionResult {
        let eligible: EligibleWindow
        switch await captureFocusedWindow() {
        case .success(let value):
            eligible = value
        case .failure(let failure):
            return .rejected(failure)
        }

        await acquire(window: eligible.identity)
        defer { release(window: eligible.identity) }

        guard await isIncluded(window: eligible.identity) else {
            return .rejected(.applicationExcluded)
        }

        let binding: CapturedBinding
        switch await captureBinding(for: eligible) {
        case .available(let value):
            binding = value
        case .failed(let failure):
            return .rejected(failure)
        }
        guard let stagedUndo = await history.stageUndo(token: token, for: eligible.identity) else {
            return .rejected(.previewMissingOrExpired)
        }
        let plan: PlacementPlan
        switch planForExistingTarget(
            stagedUndo.targetFrame,
            binding: binding,
            placement: .nonLayout
        ) {
        case .success(let value):
            plan = value
        case .failure(let failure):
            await history.discard(stagedUndo)
            return .rejected(failure)
        }

        let converted = convert(plan: plan)
        let mutationResult: WindowMutationResult
        switch converted {
        case .success(let frames):
            mutationResult = await mutation.mutate(
                window: plan.window,
                to: frames.target,
                within: frames.allowed
            )
        case .failure:
            mutationResult = .failed(.mutationRejected)
        }
        switch mutationResult {
        case .applied(let actualAX, _):
            guard let actual = convert(actualAX, topology: plan.topology.topology) else {
                await history.discard(stagedUndo)
                return .rejected(.displayUnavailable)
            }
            await history.commit(stagedUndo)
            await cycles.interrupt(window: plan.window)
            return WindowActionResult(
                disposition: .succeeded,
                effect: .undone(actualFrame: actual.cgRect),
                undoToken: nil,
                warnings: plan.warnings
            )
        case .failed(let failure):
            await history.discard(stagedUndo)
            return failureResult(failure)
        }
    }

    private func execute(
        plan: PlacementPlan,
        cycle: CycleGroupStaging?,
        acceptancePolicy: EdgeSnapAcceptancePolicy? = nil
    ) async -> WindowActionResult {
        let historyStage = await history.stage(
            window: plan.window,
            before: plan.before,
            destination: plan.historyPlacement
        )

        guard case let .success(converted) = convert(plan: plan) else {
            await history.discard(historyStage)
            if let cycle { await cycles.discard(cycle) }
            return .rejected(.displayUnavailable)
        }

        let acceptance: (@Sendable (AXGlobalTopLeftFrame, AXGlobalTopLeftFrame) -> Bool)?
        if let policy = acceptancePolicy, let action = plan.action {
            let topology = plan.topology.topology
            acceptance = { actualAX, targetAX in
                guard let converter = try? CoordinateConverter(topology: CoordinateSpaceTopology(topology)),
                      let actualAppKit = try? converter.convert(actualAX),
                      let targetAppKit = try? converter.convert(targetAX)
                else {
                    return false
                }
                return policy.accepts(
                    actualRect: actualAppKit.cgRect,
                    targetRect: targetAppKit.cgRect,
                    action: action
                )
            }
        } else {
            acceptance = nil
        }

        let outcome = await mutation.mutate(
            window: plan.window,
            to: converted.target,
            within: converted.allowed,
            acceptance: acceptance
        )
        switch outcome {
        case .applied(let actualAX, let applicationConstrained):
            guard let actual = convert(actualAX, topology: plan.topology.topology),
                  let token = await history.commit(historyStage, actualFrame: actual) else {
                await history.discard(historyStage)
                if let cycle { await cycles.discard(cycle) }
                return .rejected(.mutationRejected)
            }
            if let cycle {
                await cycles.commit(cycle)
            } else {
                await cycles.interrupt(window: plan.window)
            }
            return WindowActionResult(
                disposition: .succeeded,
                effect: .committed(
                    actualFrame: actual.cgRect,
                    constrained: plan.constrained || applicationConstrained
                ),
                undoToken: token,
                warnings: plan.warnings
                    + (applicationConstrained ? [.constrainedByApplication] : [])
            )

        case .failed(let failure):
            await history.discard(historyStage)
            if let cycle { await cycles.discard(cycle) }
            return failureResult(failure)
        }
    }

    private func compile(
        definition: WindowActionCatalog.Definition,
        binding: CapturedBinding,
        targetDisplay: DisplayID? = nil
    ) async -> Result<PlacementPlan, WindowActionFailure> {
        guard definition.isEnabled else {
            return .failure(.actionDisabled(definition.id))
        }

        switch definition.operation {
        case let .layout(layoutID, region):
            let display: DisplaySnapshot?
            if let targetDisplay {
                display = binding.topology.topology.displays.first(where: {
                    $0.id == targetDisplay
                })
            } else {
                display = displayContaining(
                    binding.currentFrame.cgRect,
                    topology: binding.topology.topology
                )
            }
            guard let display else {
                return .failure(.displayUnavailable)
            }
            let constraints: LayoutConstraints
            switch await profileLayouts.decision(for: layoutID, on: display.id) {
            case let .available(value):
                constraints = value
            case .layoutUnavailable:
                return .failure(.actionDisabled(definition.id))
            }
            do {
                let layoutPlan = try layoutCalculator.plan(
                    for: region,
                    in: display,
                    constraints: constraints
                )
                return .success(
                    PlacementPlan(
                        window: binding.window,
                        topology: binding.topology,
                        before: binding.currentFrame,
                        target: AppKitGlobalLogicalFrame(layoutPlan.frame),
                        allowed: AppKitGlobalLogicalFrame(display.visibleFrame),
                        displayID: display.id,
                        constrained: layoutPlan.isConstrained,
                        historyPlacement: .layout,
                        warnings: [],
                        action: definition.id
                    )
                )
            } catch {
                return .failure(.constraintsUnsatisfiable)
            }

        case .moveDisplay(let direction):
            switch displayMovePlanner.plan(
                window: binding.currentFrame,
                direction: direction,
                topology: binding.topology.topology
            ) {
            case .failure:
                return .failure(.displayUnavailable)
            case .success(let movePlan):
                guard let destination = binding.topology.topology.displays.first(where: {
                    $0.id == movePlan.destinationDisplayID
                }) else {
                    return .failure(.displayUnavailable)
                }
                return .success(
                    PlacementPlan(
                        window: binding.window,
                        topology: binding.topology,
                        before: binding.currentFrame,
                        target: movePlan.targetFrame,
                        allowed: AppKitGlobalLogicalFrame(destination.visibleFrame),
                        displayID: destination.id,
                        constrained: movePlan.isConstrained,
                        historyPlacement: .nonLayout,
                        warnings: [],
                        action: definition.id
                    )
                )
            }

        case .restore, .cycle, .nativeFullScreen:
            return .failure(.actionDisabled(definition.id))
        }
    }

    private func planForExistingTarget(
        _ target: AppKitGlobalLogicalFrame,
        binding: CapturedBinding,
        placement: WindowHistoryPlacement
    ) -> Result<PlacementPlan, WindowActionFailure> {
        let reconciliation: RestoreTargetReconciliation
        switch DisplayTopologyReconciler.restoreTarget(
            target.cgRect,
            in: binding.topology.topology
        ) {
        case .success(let value):
            reconciliation = value
        case .failure:
            return .failure(.displayUnavailable)
        }
        guard let display = binding.topology.topology.displays.first(where: {
            Self.contains($0.visibleFrame, reconciliation.frame)
        }) else {
            return .failure(.displayUnavailable)
        }
        return .success(
            PlacementPlan(
                window: binding.window,
                topology: binding.topology,
                before: binding.currentFrame,
                target: AppKitGlobalLogicalFrame(reconciliation.frame),
                allowed: AppKitGlobalLogicalFrame(display.visibleFrame),
                displayID: display.id,
                constrained: reconciliation.wasAdjusted,
                historyPlacement: placement,
                warnings: reconciliation.wasAdjusted ? [.targetDisplayChanged] : [],
                action: nil
            )
        )
    }

    private static func captureBinding(
        focusedWindows: any FocusedWindowProviding,
        topology: any WindowActionTopologyProviding,
        frames: any CapturedWindowFrameProviding,
        applicationIdentities: any CapturedWindowApplicationIdentifying,
        appRules: any AppRuleDeciding
    ) async -> CapturedBindingResult {
        let eligible: EligibleWindow
        switch await focusedWindows.focusedWindow() {
        case .found(let value):
            eligible = value
        case .unavailable(.permissionRequired):
            return .failed(.accessibilityPermissionRequired)
        case .unavailable(.noEligibleWindow), .unavailable(.temporarilyUnavailable),
                .unavailable(.systemUnavailable):
            return .failed(.noFocusedWindow)
        }

        guard await isIncluded(
            window: eligible.identity,
            applicationIdentities: applicationIdentities,
            appRules: appRules
        ) else {
            return .failed(.applicationExcluded)
        }

        guard case let .available(snapshot) = await topology.captureTopology() else {
            return .failed(.displayUnavailable)
        }
        let currentAX: AXGlobalTopLeftFrame
        switch await frames.currentFrame(window: eligible.identity) {
        case .available(let frame):
            currentAX = frame
        case .failed(let failure):
            return .failed(map(failure))
        }
        guard let converter = try? CoordinateConverter(
            topology: CoordinateSpaceTopology(snapshot.topology)
        ), let current = try? converter.convert(currentAX) else {
            return .failed(.displayUnavailable)
        }
        return .available(
            CapturedBinding(window: eligible.identity, topology: snapshot, currentFrame: current)
        )
    }

    private static func captureBinding(
        capturedWindow: WindowIdentity,
        topology: any WindowActionTopologyProviding,
        frames: any CapturedWindowFrameProviding,
        applicationIdentities: any CapturedWindowApplicationIdentifying,
        appRules: any AppRuleDeciding
    ) async -> CapturedBindingResult {
        guard await isIncluded(
            window: capturedWindow,
            applicationIdentities: applicationIdentities,
            appRules: appRules
        ) else {
            return .failed(.applicationExcluded)
        }
        guard case let .available(snapshot) = await topology.captureTopology() else {
            return .failed(.displayUnavailable)
        }
        let currentAX: AXGlobalTopLeftFrame
        switch await frames.currentFrame(window: capturedWindow) {
        case .available(let frame):
            currentAX = frame
        case .failed(let failure):
            return .failed(map(failure))
        }
        guard let converter = try? CoordinateConverter(
            topology: CoordinateSpaceTopology(snapshot.topology)
        ), let current = try? converter.convert(currentAX) else {
            return .failed(.displayUnavailable)
        }
        return .available(
            CapturedBinding(window: capturedWindow, topology: snapshot, currentFrame: current)
        )
    }

    private func captureBinding(for eligible: EligibleWindow) async -> CapturedBindingResult {
        guard case let .available(snapshot) = await topology.captureTopology() else {
            return .failed(.displayUnavailable)
        }
        let currentAX: AXGlobalTopLeftFrame
        switch await frames.currentFrame(window: eligible.identity) {
        case .available(let frame):
            currentAX = frame
        case .failed(let failure):
            return .failed(Self.map(failure))
        }
        guard let converter = try? CoordinateConverter(
            topology: CoordinateSpaceTopology(snapshot.topology)
        ), let current = try? converter.convert(currentAX) else {
            return .failed(.displayUnavailable)
        }
        return .available(
            CapturedBinding(window: eligible.identity, topology: snapshot, currentFrame: current)
        )
    }

    private func captureFocusedWindow() async -> Result<EligibleWindow, WindowActionFailure> {
        switch await focusedWindows.focusedWindow() {
        case .found(let window):
            return .success(window)
        case .unavailable(.permissionRequired):
            return .failure(.accessibilityPermissionRequired)
        case .unavailable(.noEligibleWindow), .unavailable(.temporarilyUnavailable),
                .unavailable(.systemUnavailable):
            return .failure(.noFocusedWindow)
        }
    }

    private func isIncluded(window: WindowIdentity) async -> Bool {
        await Self.isIncluded(
            window: window,
            applicationIdentities: applicationIdentities,
            appRules: appRules
        )
    }

    private static func isIncluded(
        window: WindowIdentity,
        applicationIdentities: any CapturedWindowApplicationIdentifying,
        appRules: any AppRuleDeciding
    ) async -> Bool {
        let bundleIdentifier = await applicationIdentities.bundleIdentifier(for: window)
        if let bundleIdentifier, let ownID = Bundle.main.bundleIdentifier, bundleIdentifier.caseInsensitiveCompare(ownID) == .orderedSame {
            return false
        }
        return await appRules.decision(for: bundleIdentifier) == .included
    }

    private func convert(
        plan: PlacementPlan
    ) -> Result<(target: AXGlobalTopLeftFrame, allowed: AXGlobalTopLeftFrame), WindowActionFailure> {
        do {
            let converter = try CoordinateConverter(
                topology: CoordinateSpaceTopology(plan.topology.topology)
            )
            return .success((
                target: try converter.convert(plan.target),
                allowed: try converter.convert(plan.allowed)
            ))
        } catch {
            return .failure(.displayUnavailable)
        }
    }

    private func convert(
        _ frame: AXGlobalTopLeftFrame,
        topology: DisplayTopologySnapshot
    ) -> AppKitGlobalLogicalFrame? {
        guard let converter = try? CoordinateConverter(
            topology: CoordinateSpaceTopology(topology)
        ) else { return nil }
        return try? converter.convert(frame)
    }

    private func displayContaining(
        _ window: CGRect,
        topology: DisplayTopologySnapshot
    ) -> DisplaySnapshot? {
        topology.displays.min { left, right in
            let leftArea = Self.area(window.intersection(left.frame))
            let rightArea = Self.area(window.intersection(right.frame))
            if leftArea != rightArea { return leftArea > rightArea }
            let leftDistance = Self.distance(window, left.frame)
            let rightDistance = Self.distance(window, right.frame)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            return left.id.rawValue < right.id.rawValue
        }
    }

    private func acquire(window: WindowIdentity) async {
        guard busyWindows.contains(window) else {
            busyWindows.insert(window)
            return
        }
        await withCheckedContinuation { continuation in
            windowWaiters[window, default: []].append(continuation)
        }
    }

    private func release(window: WindowIdentity) {
        if var waiters = windowWaiters[window], !waiters.isEmpty {
            let next = waiters.removeFirst()
            windowWaiters[window] = waiters.isEmpty ? nil : waiters
            next.resume()
        } else {
            busyWindows.remove(window)
        }
    }

    private func mapNativeFullScreen(_ result: NativeFullScreenActionResult) -> WindowActionResult {
        switch result {
        case .acceptedButUnverified, .rejected, .temporarilyUnavailable:
            return .rejected(.mutationRejected)
        case .cancelled:
            return .cancelled
        case .accessibilityPermissionRequired:
            return .rejected(.accessibilityPermissionRequired)
        case .windowDisappeared:
            return .rejected(.windowDisappeared)
        case .timedOut:
            return .rejected(.verificationTimedOut)
        }
    }

    private func failureResult(_ failure: WindowMutationFailure) -> WindowActionResult {
        if failure == .rollbackIncomplete {
            return .rejected(.rollbackIncomplete, warnings: [.rollbackIncomplete])
        }
        return .rejected(Self.map(failure))
    }

    private static func map(_ failure: WindowMutationFailure) -> WindowActionFailure {
        switch failure {
        case .accessibilityPermissionRequired: .accessibilityPermissionRequired
        case .windowNotMovable: .windowNotMovable
        case .windowNotResizable: .windowNotResizable
        case .windowDisappeared: .windowDisappeared
        case .mutationRejected: .mutationRejected
        case .verificationTimedOut: .verificationTimedOut
        case .rollbackIncomplete: .rollbackIncomplete
        }
    }

    private static func contains(_ bounds: CGRect, _ frame: CGRect) -> Bool {
        frame.minX >= bounds.minX
            && frame.minY >= bounds.minY
            && frame.maxX <= bounds.maxX
            && frame.maxY <= bounds.maxY
    }

    private static func area(_ frame: CGRect) -> CGFloat {
        frame.isNull || frame.isEmpty ? 0 : frame.width * frame.height
    }

    private static func distance(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let x = first.midX - second.midX
        let y = first.midY - second.midY
        return x * x + y * y
    }
}
