import AppKit
import SwiftUI
import XCTest
@testable import MyMacX

@MainActor
final class SuperModeSettingsWindowControllerTests: XCTestCase {
    func testHotkeyEditorsRenderLongestReasonableLabelsAtAccessibilityTextSizeAndMinimumWindow() async {
        let longAction = ActionDescriptor(
            id: .moveDisplayPrevious,
            title: "Move the captured window to the previous connected Display",
            symbolName: "arrow.left.to.line",
            availability: .available
        )
        let registry = ActionRegistry(actions: [longAction])
        let superConfiguration = SuperModeConfiguration(
            prefix: HotkeyChord(hardwareKeyCode: 49, modifiers: [.control, .option, .shift, .command]),
            timeoutMilliseconds: 1_000,
            commandBindings: [
                .init(hardwareKeyCodes: [116, 121], actionID: .moveDisplayPrevious),
            ]
        )
        let superController = SuperModeSettingsWindowController(
            actionRegistry: registry,
            presenter: FixtureChordPresenter(labels: [49: "Space", 116: "Page Up", 121: "Page Down"]),
            load: { HotkeySettings(bindings: [], superModeConfiguration: superConfiguration) },
            apply: { .rejected(.invalidTimeout(milliseconds: $0.timeoutMilliseconds)) }
        )
        await superController.modelForTesting.reload()

        let binding = HotkeyBinding(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            hardwareKeyCode: 122,
            modifiers: [.control, .option, .shift, .command],
            actionID: .moveDisplayPrevious
        )
        let globalController = GlobalHotkeySettingsWindowController(
            actionRegistry: registry,
            load: { HotkeySettings(bindings: [binding]) },
            apply: { .applied(.active(bindingIDs: $0.bindings.map(\.id))) },
            presenter: FixtureChordPresenter(labels: [122: "F1"])
        )
        await globalController.modelForTesting.reload()
        let size = NSSize(width: 760, height: 520)

        assertProductionSettingsWindowRenders(
            superController.windowForTesting(contentSize: size, dynamicTypeSize: .accessibility3),
            contentSize: size
        )
        assertProductionSettingsWindowRenders(
            globalController.windowForTesting(contentSize: size, dynamicTypeSize: .accessibility3),
            contentSize: size
        )
    }

    func testSuperModeEditorRendersEmptyErrorAndRecordingAtSettingsWindowSizes() async {
        let recorder = HoldingHotkeyRecorder()
        let harness = Harness(recorder: recorder)
        let controller = harness.makeController()

        assertEditorRendersAtSettingsWindowSizes(controller)

        await controller.modelForTesting.save()
        guard case .error = controller.modelForTesting.status else {
            return XCTFail("Expected the rejected save to expose the error state")
        }
        assertEditorRendersAtSettingsWindowSizes(controller)

        controller.modelForTesting.recordPrefix()
        await waitUntil { controller.modelForTesting.isRecordingPrefix }
        assertEditorRendersAtSettingsWindowSizes(controller)
    }

    func testGlobalHotkeyEditorRendersEmptyErrorAndRecordingAtSettingsWindowSizes() async {
        let recorder = HoldingHotkeyRecorder()
        let binding = HotkeyBinding(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            hardwareKeyCode: 4,
            modifiers: [.control],
            actionID: .leftHalf
        )
        let controller = GlobalHotkeySettingsWindowController(
            actionRegistry: .builtIn,
            load: { HotkeySettings(bindings: []) },
            apply: { _ in .saveFailed(.documentNotWritable) },
            recorder: recorder,
            presenter: FixtureChordPresenter(labels: [4: "H"])
        )

        assertEditorRendersAtSettingsWindowSizes(controller)

        controller.modelForTesting.addBinding()
        await controller.modelForTesting.save()
        guard case .error = controller.modelForTesting.status else {
            return XCTFail("Expected the failed save to expose the error state")
        }
        assertEditorRendersAtSettingsWindowSizes(controller)

        let bindingController = GlobalHotkeySettingsWindowController(
            actionRegistry: .builtIn,
            load: { HotkeySettings(bindings: [binding]) },
            apply: { .applied(.active(bindingIDs: $0.bindings.map(\.id))) },
            recorder: recorder,
            presenter: FixtureChordPresenter(labels: [4: "H"])
        )
        await bindingController.modelForTesting.reload()
        bindingController.modelForTesting.record(binding.id)
        await waitUntil { bindingController.modelForTesting.recordingBindingID == binding.id }
        assertEditorRendersAtSettingsWindowSizes(bindingController)
    }

    func testSuperModePresentsPrefixAndCommandKeysWithoutHardwareNumbers() {
        let presenter = FixtureChordPresenter(labels: [49: "Space", 4: "H", 37: "L"])
        let harness = Harness(presenter: presenter)
        let model = harness.makeModel()
        model.loadTestPreset()

        XCTAssertEqual(model.prefixPresentation.visibleLabel, "⌃ Space")
        XCTAssertEqual(model.prefixPresentation.accessibilityLabel, "Control Space")
        XCTAssertEqual(model.bindingKeyPresentation(for: model.bindings[0], level: 0).visibleLabel, "H")
        XCTAssertEqual(model.bindingKeyPresentation(for: model.bindings[1], level: 0).visibleLabel, "L")
    }

    func testUnknownSuperModeKeyUsesDescriptiveNonNumericFallback() {
        let harness = Harness(presenter: FixtureChordPresenter(labels: [:]))
        let model = harness.makeModel()
        model.addBinding()

        let presentation = model.bindingKeyPresentation(for: model.bindings[0], level: 0)

        XCTAssertEqual(presentation.visibleLabel, "Unknown key")
        XCTAssertEqual(presentation.accessibilityLabel, "Unknown key")
        XCTAssertFalse(presentation.visibleLabel.contains("0"))
    }

    func testPresetContainsExactSprintFiveBindings() {
        let harness = Harness()
        let model = harness.makeModel()

        model.loadTestPreset()

        XCTAssertEqual(
            model.configuration,
            SuperModeConfiguration(
                prefix: HotkeyChord(hardwareKeyCode: 49, modifiers: [.control]),
                timeoutMilliseconds: 1_000,
                commandBindings: [
                    SuperModeCommandBinding(hardwareKeyCodes: [4], actionID: .leftHalf),
                    SuperModeCommandBinding(hardwareKeyCodes: [37], actionID: .rightHalf),
                    SuperModeCommandBinding(hardwareKeyCodes: [46], actionID: .maximize),
                    SuperModeCommandBinding(hardwareKeyCodes: [15], actionID: .restore),
                    SuperModeCommandBinding(hardwareKeyCodes: [2, 45], actionID: .moveDisplayNext),
                    SuperModeCommandBinding(hardwareKeyCodes: [2, 35], actionID: .moveDisplayPrevious),
                    SuperModeCommandBinding(hardwareKeyCodes: [8, 37], actionID: .cycleLeftEdge),
                    SuperModeCommandBinding(hardwareKeyCodes: [1], actionID: .openSettings),
                ]
            )
        )
    }

    func testDraftChangesDoNotApplyUntilSave() async {
        let persisted = configuration(timeout: 750)
        let harness = Harness(configuration: persisted)
        let model = harness.makeModel()

        await model.reload()
        model.timeoutMilliseconds = 2_000
        model.addBinding()

        XCTAssertEqual(harness.appliedConfigurations, [])
        XCTAssertEqual(harness.configuration, persisted)
    }

    func testSaveCallsApplyExactlyOnceWithCurrentDraft() async {
        let harness = Harness()
        harness.applyResult = { configuration in
            .applied(
                settings: HotkeySettings(bindings: [], superModeConfiguration: configuration),
                runtime: SuperModeRuntimeSnapshot(
                    revision: SuperModeConfigurationRevision(rawValue: 1),
                    configuration: configuration,
                    commandTree: SuperModeCommandTree()
                )
            )
        }
        let model = harness.makeModel()
        model.loadTestPreset()

        await model.save()

        XCTAssertEqual(harness.appliedConfigurations, [model.configuration])
        XCTAssertEqual(model.status, .saved)
    }

    func testRejectedSaveShowsConciseTypedError() async {
        let harness = Harness()
        harness.applyResult = { _ in .rejected(.duplicatePath([4])) }
        let model = harness.makeModel()

        await model.save()

        XCTAssertEqual(model.status, .error("Two bindings use the same key sequence."))
        XCTAssertEqual(harness.appliedConfigurations.count, 1)
    }

    func testBindingDraftCanAddChangeLevelActionAndDelete() {
        let harness = Harness()
        let model = harness.makeModel()

        model.addBinding()
        let id = try! XCTUnwrap(model.bindings.first?.id)
        model.setBindingLevelCount(id: id, count: 2)
        model.setBindingKeyCode(id: id, level: 0, keyCode: 2)
        model.setBindingKeyCode(id: id, level: 1, keyCode: 45)
        model.setBindingAction(id: id, actionID: .moveDisplayNext)

        XCTAssertEqual(
            model.configuration.commandBindings,
            [SuperModeCommandBinding(hardwareKeyCodes: [2, 45], actionID: .moveDisplayNext)]
        )

        model.deleteBinding(id: id)
        XCTAssertTrue(model.bindings.isEmpty)
    }

    func testPresentReusesOneWindow() {
        let harness = Harness()
        let controller = harness.makeController()

        controller.present()
        let firstWindow = controller.windowForTesting
        controller.present()

        XCTAssertNotNil(firstWindow)
        XCTAssertTrue(firstWindow === controller.windowForTesting)
        firstWindow?.close()
    }

    func testRequestInputMonitoringRefreshesStateAndRetriesRuntimeWhenGranted() async {
        let harness = Harness()
        harness.hasInputMonitoringAccess = false
        harness.requestInputMonitoringResult = true
        let model = harness.makeModel()

        XCTAssertEqual(model.inputMonitoringState, .required)

        await model.requestInputMonitoring()

        XCTAssertEqual(harness.requestInputMonitoringCount, 1)
        XCTAssertEqual(harness.retrySuperModeRuntimeCount, 1)
        XCTAssertEqual(model.inputMonitoringState, .granted)
    }

    func testGlobalHotkeyEditorLoadsAndSavesBindingsWhilePreservingSuperMode() async {
        let superMode = configuration(timeout: 1_750)
        let original = HotkeyBinding(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            hardwareKeyCode: 4,
            modifiers: [.control],
            actionID: .leftHalf
        )
        var applied: [HotkeySettings] = []
        let model = GlobalHotkeySettingsModel(
            actionRegistry: .builtIn,
            load: { HotkeySettings(bindings: [original], superModeConfiguration: superMode) },
            apply: { settings in
                applied.append(settings)
                return .applied(.active(bindingIDs: settings.bindings.map(\.id)))
            }
        )

        await model.reload()
        model.addBinding()
        await model.save()

        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.superModeConfiguration, superMode)
        XCTAssertEqual(applied.first?.bindings.first, original)
        XCTAssertEqual(model.status, .saved)
    }

    func testGlobalHotkeyEditorRejectsDuplicateChordBeforeRuntimeApply() async {
        let first = HotkeyBinding(
            id: UUID(),
            hardwareKeyCode: 4,
            modifiers: [.control],
            actionID: .leftHalf
        )
        let second = HotkeyBinding(
            id: UUID(),
            hardwareKeyCode: 4,
            modifiers: [.control],
            actionID: .rightHalf
        )
        var applyCount = 0
        let model = GlobalHotkeySettingsModel(
            actionRegistry: .builtIn,
            load: { HotkeySettings(bindings: [first, second]) },
            apply: { _ in
                applyCount += 1
                return .applied(.active(bindingIDs: []))
            }
        )

        await model.reload()
        await model.save()

        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(model.status, .error("Two bindings use the same shortcut."))
    }

    func testGlobalHotkeyEditorPresentsMacShortcutAndNonNumericUnknownFallback() {
        let presenter = FixtureChordPresenter(labels: [4: "H"])
        let model = GlobalHotkeySettingsModel(
            actionRegistry: .builtIn,
            load: { HotkeySettings(bindings: []) },
            apply: { _ in .applied(.active(bindingIDs: [])) },
            presenter: presenter
        )

        XCTAssertEqual(
            model.presentation(for: HotkeyChord(hardwareKeyCode: 4, modifiers: [.option, .command])).visibleLabel,
            "⌥⌘H"
        )
        XCTAssertEqual(
            model.presentation(for: HotkeyChord(hardwareKeyCode: 126, modifiers: [])).visibleLabel,
            "Unknown key"
        )
    }

    private func configuration(timeout: UInt32) -> SuperModeConfiguration {
        SuperModeConfiguration(
            prefix: HotkeyChord(hardwareKeyCode: 49, modifiers: [.control]),
            timeoutMilliseconds: timeout,
            commandBindings: []
        )
    }
}

@MainActor
private final class Harness {
    var configuration: SuperModeConfiguration
    var appliedConfigurations: [SuperModeConfiguration] = []
    var applyResult: (SuperModeConfiguration) -> SuperModeConfigurationApplyResult = {
        .rejected(.invalidTimeout(milliseconds: $0.timeoutMilliseconds))
    }
    var hasInputMonitoringAccess = true
    var requestInputMonitoringResult = true
    var requestInputMonitoringCount = 0
    var retrySuperModeRuntimeCount = 0
    let presenter: any HotkeyChordPresenting
    let recorder: (any HotkeyRecording)?

    init(
        configuration: SuperModeConfiguration = .default,
        presenter: any HotkeyChordPresenting = FixtureChordPresenter(labels: [49: "Space"]),
        recorder: (any HotkeyRecording)? = nil
    ) {
        self.configuration = configuration
        self.presenter = presenter
        self.recorder = recorder
    }

    func makeModel() -> SuperModeSettingsModel {
        makeController().modelForTesting
    }

    func makeController() -> SuperModeSettingsWindowController {
        SuperModeSettingsWindowController(
            actionRegistry: .builtIn,
            hasInputMonitoringAccess: { [weak self] in
                self?.hasInputMonitoringAccess ?? false
            },
            requestInputMonitoringAccess: { [weak self] in
                guard let self else { return false }
                requestInputMonitoringCount += 1
                hasInputMonitoringAccess = requestInputMonitoringResult
                return requestInputMonitoringResult
            },
            retrySuperModeRuntime: { [weak self] in
                self?.retrySuperModeRuntimeCount += 1
            },
            presenter: presenter,
            load: { [weak self] in
                HotkeySettings(
                    bindings: [],
                    superModeConfiguration: self?.configuration ?? .default
                )
            },
            apply: { [weak self] configuration in
                guard let self else {
                    return .rejected(.invalidTimeout(milliseconds: configuration.timeoutMilliseconds))
                }
                appliedConfigurations.append(configuration)
                return applyResult(configuration)
            },
            recorder: recorder
        )
    }
}

@MainActor
private func assertEditorRendersAtSettingsWindowSizes(_ controller: SuperModeSettingsWindowController) {
    for size in [NSSize(width: 880, height: 620), NSSize(width: 760, height: 520)] {
        assertProductionSettingsWindowRenders(controller.windowForTesting(contentSize: size), contentSize: size)
    }
}

@MainActor
private func assertEditorRendersAtSettingsWindowSizes(_ controller: GlobalHotkeySettingsWindowController) {
    for size in [NSSize(width: 880, height: 620), NSSize(width: 760, height: 520)] {
        assertProductionSettingsWindowRenders(controller.windowForTesting(contentSize: size), contentSize: size)
    }
}

@MainActor
func assertProductionSettingsWindowRenders(
    _ window: NSWindow,
    contentSize: NSSize,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let contentView = window.contentView else {
        return XCTFail("Expected a production content view", file: file, line: line)
    }
    contentView.layoutSubtreeIfNeeded()

    XCTAssertEqual(contentView.bounds.size.width, contentSize.width, accuracy: 0.5, file: file, line: line)
    XCTAssertEqual(contentView.bounds.size.height, contentSize.height, accuracy: 0.5, file: file, line: line)
    XCTAssertLessThanOrEqual(contentView.fittingSize.width, contentSize.width + 0.5, file: file, line: line)

    guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
        return XCTFail("Expected the production view to allocate a bitmap", file: file, line: line)
    }
    contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
    XCTAssertGreaterThan(bitmap.pixelsWide, 0, file: file, line: line)
    XCTAssertGreaterThan(bitmap.pixelsHigh, 0, file: file, line: line)
    XCTAssertGreaterThan(bitmap.representation(using: .png, properties: [:])?.count ?? 0, 1_000, file: file, line: line)
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<100 where !condition() {
        await Task.yield()
    }
    XCTAssertTrue(condition(), file: file, line: line)
}

private actor HoldingHotkeyRecorder: HotkeyRecording {
    let updates: AsyncStream<HotkeyRecorderState>
    private let continuation: AsyncStream<HotkeyRecorderState>.Continuation

    init() {
        let stream = AsyncStream.makeStream(of: HotkeyRecorderState.self, bufferingPolicy: .bufferingNewest(8))
        updates = stream.stream
        continuation = stream.continuation
    }

    func begin() async { continuation.yield(.recording) }
    func cancel() async { continuation.yield(.cancelled) }
    func clear() async { continuation.yield(.cleared) }
}

private struct FixtureChordPresenter: HotkeyChordPresenting {
    let labels: [UInt16: String]

    func present(_ chord: HotkeyChord) -> HotkeyChordPresentation {
        let symbols: [(HotkeyModifiers, HotkeyModifierSymbol, String, String)] = [
            (.control, .control, "⌃", "Control"),
            (.option, .option, "⌥", "Option"),
            (.shift, .shift, "⇧", "Shift"),
            (.command, .command, "⌘", "Command"),
        ]
        let active = symbols.filter { chord.modifiers.contains($0.0) }
        let key = labels[chord.hardwareKeyCode] ?? "Unknown key"
        return HotkeyChordPresentation(
            modifierSymbols: active.map(\.1),
            keyLabel: key,
            accessibilityLabel: (active.map(\.3) + [key]).joined(separator: " "),
            usedHardwareCodeFallback: labels[chord.hardwareKeyCode] == nil
        )
    }
}
