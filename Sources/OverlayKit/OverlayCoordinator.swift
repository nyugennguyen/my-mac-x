import AppKit
import CoreGraphics

/// UI-owned description of a selectable Window Action. The caller supplies display-safe
/// metadata from ActionRegistry; OverlayKit does not discover or execute Window Actions.
struct OverlayLayoutChoice: Equatable {
    let action: ActionID
    let title: String
    let accessibilityLabel: String
}

/// A chooser request whose panel frame has already been resolved by the interaction and
/// screen-geometry modules. OverlayKit only presents this exact frame.
struct OverlayChooserPresentation: Equatable {
    let displayID: DisplayID
    let panelFrame: CGRect
    let choices: [OverlayLayoutChoice]
    let columnCount: Int
    let initialSelection: ActionID?
}

/// A preview request whose target was already calculated by WindowActionKit.
struct OverlayPreviewPresentation: Equatable {
    let displayID: DisplayID
    let targetFrame: CGRect
    let isConstrainedByMinimumSize: Bool
}

enum OverlayChooserPresentationResult: Equatable {
    case shown(action: ActionID)
    case rejected(OverlayPresentationFailure)
}

enum OverlayPreviewPresentationResult: Equatable {
    case shown
    case rejected(OverlayPresentationFailure)
}

enum OverlayPresentationFailure: Error, Equatable {
    case invalidPanelFrame
    case invalidPreviewFrame
    case emptyChoices
    case duplicateChoiceAction(ActionID)
    case invalidColumnCount
    case unknownInitialSelection(ActionID)
}

enum OverlaySelectionDirection: Equatable {
    case left
    case right
    case up
    case down
}

enum OverlaySelectionMoveResult: Equatable {
    case selected(action: ActionID)
    case ignored
}

enum OverlayPointerTrackingResult: Equatable {
    case outsideChooser
    case insideChooser(displayID: DisplayID, action: ActionID?)
}

/// Privacy-safe chooser interaction forwarded to the drag state machine. OverlayKit reports
/// user intent only; the caller decides whether it previews, commits, or cancels a Window Action.
enum OverlayChooserEvent: Equatable, Sendable {
    case selectionChanged(action: ActionID)
    case confirmed(action: ActionID)
    case cancelled
}

enum OverlayKeyboardInput: Equatable {
    case arrow(OverlaySelectionDirection)
    case confirm
    case escape
}

enum OverlayKeyboardResult: Equatable {
    case selectionChanged(action: ActionID)
    case confirmed(action: ActionID)
    case cancelled
    case ignored
}

/// The accessibility state supplied by application composition. OverlayKit maps it to a
/// rendering policy and does not inspect system preferences or persist them.
struct OverlayAccessibilityPreferences: Equatable {
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let increaseContrast: Bool

    init(
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

enum OverlayMotionTreatment: Equatable {
    case standard
    case immediate
}

enum OverlayBackgroundTreatment: Equatable {
    case translucent
    case opaque
}

enum OverlayContrastTreatment: Equatable {
    case standard
    case increased
}

/// A compact rendering policy shared by the Layout Chooser and Placement Preview.
struct OverlayPresentationPolicy: Equatable {
    let motion: OverlayMotionTreatment
    let background: OverlayBackgroundTreatment
    let contrast: OverlayContrastTreatment

    init(accessibilityPreferences: OverlayAccessibilityPreferences = .init()) {
        motion = accessibilityPreferences.reduceMotion ? .immediate : .standard
        background = accessibilityPreferences.reduceTransparency ? .opaque : .translucent
        contrast = accessibilityPreferences.increaseContrast ? .increased : .standard
    }
}

/// Internal rendering model. Display selection and frame calculation have deliberately
/// happened before this seam.
struct OverlayChooserRenderModel: Equatable {
    let panelFrame: CGRect
    let choices: [OverlayLayoutChoice]
    let selectedAction: ActionID
    let columnCount: Int
    let presentationPolicy: OverlayPresentationPolicy
}

/// Internal rendering model. A constrained flag is the typed warning supplied by
/// WindowActionKit rather than a local minimum-size calculation.
struct OverlayPreviewRenderModel: Equatable {
    let targetFrame: CGRect
    let isConstrainedByMinimumSize: Bool
    let presentationPolicy: OverlayPresentationPolicy
}

/// The rendering seam has two real adapters: AppKit panels in production and a deterministic
/// recording renderer in OverlayKit's Interface tests.
@MainActor
protocol OverlayRendering: AnyObject {
    func showChooser(
        _ model: OverlayChooserRenderModel,
        onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
    )
    func showPreview(_ model: OverlayPreviewRenderModel)
    func dismiss()
}

/// Owns transient chooser and preview presentation state. It never calls Accessibility,
/// reads screens, derives geometry, or commits a Window Action. Pointer/Input integration
/// drives selection through this Interface and decides when a selected action is committed.
@MainActor
final class OverlayCoordinator {
    private let renderer: any OverlayRendering
    var onEvent: @MainActor @Sendable (OverlayChooserEvent) -> Void
    private let presentationPolicy: OverlayPresentationPolicy
    private var chooser: OverlayChooserPresentation?
    private var selectedAction: ActionID?

    convenience init() {
        self.init(renderer: AppKitOverlayRenderer())
    }

    init(
        renderer: any OverlayRendering,
        accessibilityPreferences: OverlayAccessibilityPreferences = .init(),
        onEvent: @escaping @MainActor @Sendable (OverlayChooserEvent) -> Void = { _ in }
    ) {
        self.renderer = renderer
        presentationPolicy = OverlayPresentationPolicy(accessibilityPreferences: accessibilityPreferences)
        self.onEvent = onEvent
    }

    func presentChooser(_ presentation: OverlayChooserPresentation) -> OverlayChooserPresentationResult {
        switch validate(presentation) {
        case .success:
            break
        case .failure(let failure):
            return .rejected(failure)
        }

        let selection = presentation.initialSelection ?? presentation.choices[0].action
        chooser = presentation
        selectedAction = selection
        renderChooser()
        return .shown(action: selection)
    }

    func moveSelection(_ direction: OverlaySelectionDirection) -> OverlaySelectionMoveResult {
        guard let chooser,
              let selectedAction,
              let currentIndex = chooser.choices.firstIndex(where: { $0.action == selectedAction })
        else {
            return .ignored
        }

        let count = chooser.choices.count
        let nextIndex: Int
        switch direction {
        case .left:
            nextIndex = (currentIndex - 1 + count) % count
        case .right:
            nextIndex = (currentIndex + 1) % count
        case .up:
            nextIndex = max(0, currentIndex - chooser.columnCount)
        case .down:
            nextIndex = min(count - 1, currentIndex + chooser.columnCount)
        }

        let nextAction = chooser.choices[nextIndex].action
        self.selectedAction = nextAction
        renderChooser()
        onEvent(.selectionChanged(action: nextAction))
        return .selected(action: nextAction)
    }

    /// Maps the global pointer used by an in-progress cross-application drag into the chooser.
    /// AppKit mouse-enter events are not relied on because the originating application owns the
    /// drag sequence until mouse-up.
    func trackPointer(at location: CGPoint) -> OverlayPointerTrackingResult {
        guard let chooser, chooser.panelFrame.contains(location) else {
            return .outsideChooser
        }

        let contentFrame = chooser.panelFrame.insetBy(dx: 12, dy: 12)
        guard contentFrame.contains(location) else {
            return .insideChooser(displayID: chooser.displayID, action: nil)
        }

        let rowCount = Int(ceil(Double(chooser.choices.count) / Double(chooser.columnCount)))
        let columnWidth = contentFrame.width / CGFloat(chooser.columnCount)
        let rowHeight = contentFrame.height / CGFloat(rowCount)
        let column = min(
            chooser.columnCount - 1,
            Int((location.x - contentFrame.minX) / columnWidth)
        )
        let rowFromTop = min(
            rowCount - 1,
            Int((contentFrame.maxY - location.y) / rowHeight)
        )
        let index = rowFromTop * chooser.columnCount + column
        guard chooser.choices.indices.contains(index) else {
            return .insideChooser(displayID: chooser.displayID, action: nil)
        }

        let action = chooser.choices[index].action
        if action != selectedAction {
            select(action)
        }
        return .insideChooser(displayID: chooser.displayID, action: action)
    }

    func handleKeyboard(_ input: OverlayKeyboardInput) -> OverlayKeyboardResult {
        switch input {
        case .arrow(let direction):
            guard case let .selected(action) = moveSelection(direction) else {
                return .ignored
            }
            return .selectionChanged(action: action)

        case .confirm:
            guard let selectedAction else { return .ignored }
            onEvent(.confirmed(action: selectedAction))
            return .confirmed(action: selectedAction)

        case .escape:
            guard chooser != nil else { return .ignored }
            chooser = nil
            selectedAction = nil
            renderer.dismiss()
            onEvent(.cancelled)
            return .cancelled
        }
    }

    func showPreview(_ presentation: OverlayPreviewPresentation) -> OverlayPreviewPresentationResult {
        guard Self.isValid(frame: presentation.targetFrame) else {
            return .rejected(.invalidPreviewFrame)
        }

        renderer.showPreview(
            OverlayPreviewRenderModel(
                targetFrame: presentation.targetFrame,
                isConstrainedByMinimumSize: presentation.isConstrainedByMinimumSize,
                presentationPolicy: presentationPolicy
            )
        )
        return .shown
    }

    func dismiss() {
        chooser = nil
        selectedAction = nil
        renderer.dismiss()
    }

    private func renderChooser() {
        guard let chooser, let selectedAction else { return }
        renderer.showChooser(
            OverlayChooserRenderModel(
                panelFrame: chooser.panelFrame,
                choices: chooser.choices,
                selectedAction: selectedAction,
                columnCount: chooser.columnCount,
                presentationPolicy: presentationPolicy
            ),
            onSelect: { [weak self] action in
                self?.select(action)
            }
        )
    }

    private func select(_ action: ActionID) {
        guard let chooser, chooser.choices.contains(where: { $0.action == action }) else {
            return
        }
        selectedAction = action
        renderChooser()
        onEvent(.selectionChanged(action: action))
    }

    private func validate(
        _ presentation: OverlayChooserPresentation
    ) -> Result<Void, OverlayPresentationFailure> {
        guard Self.isValid(frame: presentation.panelFrame) else {
            return .failure(.invalidPanelFrame)
        }
        guard !presentation.choices.isEmpty else {
            return .failure(.emptyChoices)
        }
        guard presentation.columnCount > 0 else {
            return .failure(.invalidColumnCount)
        }
        let uniqueActions = Set(presentation.choices.map(\.action))
        guard uniqueActions.count == presentation.choices.count else {
            let duplicate = presentation.choices.first { choice in
                presentation.choices.filter { $0.action == choice.action }.count > 1
            }!
            return .failure(.duplicateChoiceAction(duplicate.action))
        }
        if let initialSelection = presentation.initialSelection, !uniqueActions.contains(initialSelection) {
            return .failure(.unknownInitialSelection(initialSelection))
        }
        return .success(())
    }

    private static func isValid(frame: CGRect) -> Bool {
        frame.minX.isFinite
            && frame.minY.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
            && frame.maxX.isFinite
            && frame.maxY.isFinite
    }
}

@MainActor
private final class AppKitOverlayRenderer: OverlayRendering {
    private let chooserPanel = SnapOverlayPanel()
    private let previewPanel = SnapPreviewPanel()

    func showChooser(
        _ model: OverlayChooserRenderModel,
        onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
    ) {
        chooserPanel.contentView = LayoutChooserView(model: model, onSelect: onSelect)
        chooserPanel.setFrame(model.panelFrame, display: true)
        chooserPanel.orderFrontRegardless()
    }

    func showPreview(_ model: OverlayPreviewRenderModel) {
        previewPanel.contentView = PlacementPreviewView(model: model)
        previewPanel.setFrame(model.targetFrame, display: true)
        previewPanel.orderFrontRegardless()
    }

    func dismiss() {
        chooserPanel.orderOut(nil)
        previewPanel.orderOut(nil)
    }
}

@MainActor
/// AppKit presentation seam for a transient overlay that must not take application focus.
class OverlayPresentationPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class SnapOverlayPanel: OverlayPresentationPanel {}

@MainActor
private final class SnapPreviewPanel: OverlayPresentationPanel {}

@MainActor
private final class LayoutChooserView: NSVisualEffectView {
    init(
        model: OverlayChooserRenderModel,
        onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
    ) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        if model.presentationPolicy.background == .opaque {
            state = .inactive
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        if model.presentationPolicy.contrast == .increased {
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.labelColor.cgColor
        }

        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        for start in stride(from: 0, to: model.choices.count, by: model.columnCount) {
            let rowChoices = model.choices[start..<min(start + model.columnCount, model.choices.count)]
            let buttons = rowChoices.map { choice in
                OverlayChoiceButton(
                    choice: choice,
                    isSelected: choice.action == model.selectedAction,
                    contrast: model.presentationPolicy.contrast,
                    onSelect: onSelect
                )
            }
            grid.addRow(with: buttons)
        }

        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        setAccessibilityLabel("Layout Chooser")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class OverlayChoiceButton: NSButton {
    private let actionID: ActionID
    private let onSelect: @MainActor @Sendable (ActionID) -> Void

    init(
        choice: OverlayLayoutChoice,
        isSelected: Bool,
        contrast: OverlayContrastTreatment,
        onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
    ) {
        actionID = choice.action
        self.onSelect = onSelect
        super.init(frame: .zero)
        title = choice.title
        setAccessibilityLabel(choice.accessibilityLabel)
        setButtonType(.pushOnPushOff)
        state = isSelected ? .on : .off
        if contrast == .increased {
            contentTintColor = .labelColor
            wantsLayer = true
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.labelColor.cgColor
        }
        target = self
        action = #selector(didPress)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func didPress() {
        onSelect(actionID)
    }
}

@MainActor
private final class PlacementPreviewView: NSView {
    init(model: OverlayPreviewRenderModel) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.cornerRadius = 8
        if model.presentationPolicy.background == .opaque {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        if model.presentationPolicy.contrast == .increased {
            layer?.borderWidth = 3
            layer?.borderColor = NSColor.labelColor.cgColor
        }
        setAccessibilityLabel(
            model.isConstrainedByMinimumSize
                ? "Placement Preview. Constrained by application minimum size."
                : "Placement Preview"
        )

        if model.isConstrainedByMinimumSize {
            let warning = NSTextField(labelWithString: "Minimum size")
            warning.textColor = .white
            warning.backgroundColor = .systemOrange
            warning.wantsLayer = true
            warning.layer?.cornerRadius = 4
            warning.translatesAutoresizingMaskIntoConstraints = false
            addSubview(warning)
            NSLayoutConstraint.activate([
                warning.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                warning.centerXAnchor.constraint(equalTo: centerXAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
