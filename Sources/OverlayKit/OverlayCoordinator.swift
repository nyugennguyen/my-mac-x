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

/// Bridges privacy-safe hardware metadata from the shared Event Tap into the non-activating
/// Layout Chooser. The callback retains only whether a chooser is accepting input and dispatches
/// a semantic navigation intent to the MainActor; it never stores raw signals or typed text.
final class LayoutChooserKeyboardInputAdapter: @unchecked Sendable {
  private let lock = NSLock()
  private var acceptingInput = false
  @MainActor private weak var target: OverlayCoordinator?

  var isAcceptingInput: Bool {
    lock.lock()
    defer { lock.unlock() }
    return acceptingInput
  }

  @MainActor
  func bind(to target: OverlayCoordinator) {
    self.target = target
  }

  func setAcceptingInput(_ acceptingInput: Bool) {
    lock.lock()
    self.acceptingInput = acceptingInput
    lock.unlock()
  }

  func handle(_ signal: EventTapSignal) -> EventTapEventDisposition {
    lock.lock()
    let isActive = acceptingInput
    lock.unlock()
    guard isActive,
      case .key(let key) = signal,
      key.kind == .keyDown,
      Self.hasNoCommandModifiers(key.modifierFlags),
      let input = Self.input(for: key.hardwareKeyCode)
    else {
      return .passThrough
    }

    if input == .confirm || input == .escape {
      setAcceptingInput(false)
    }
    Task { @MainActor [weak self] in
      guard let self else { return }
      _ = target?.handleKeyboard(input)
    }
    return .consume
  }

  private static func input(for hardwareKeyCode: UInt16) -> OverlayKeyboardInput? {
    switch hardwareKeyCode {
    case 123: .arrow(.left)
    case 124: .arrow(.right)
    case 125: .arrow(.down)
    case 126: .arrow(.up)
    case 36, 76: .confirm
    case 53: .escape
    default: nil
    }
  }

  private static func hasNoCommandModifiers(_ rawFlags: UInt64) -> Bool {
    let commandModifiers = CGEventFlags([
      .maskShift,
      .maskControl,
      .maskAlternate,
      .maskCommand,
      .maskSecondaryFn,
    ]).rawValue
    return rawFlags & commandModifiers == 0
  }
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
  let visualStyle: OverlayChooserVisualStyle = .macOSNative
}

/// Semantic metrics for the signature Layout Chooser. Keeping these in the render model
/// makes its density and hit-target contract observable without testing AppKit internals.
struct OverlayChooserVisualStyle: Equatable {
  let cornerRadius: CGFloat
  let contentPadding: CGFloat
  let itemSpacing: CGFloat
  let minimumTargetSize: CGSize
  let showsOnlySelectedTitle: Bool
  let usesLayoutGlyphs: Bool

  static let macOSNative = OverlayChooserVisualStyle(
    cornerRadius: 16,
    contentPadding: 14,
    itemSpacing: 8,
    minimumTargetSize: CGSize(width: 64, height: 52),
    showsOnlySelectedTitle: true,
    usesLayoutGlyphs: true
  )
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

/// Internal render seam shared by the panel adapters and pixel-regression tests.
/// Tests receive the exact production view hierarchy without presenting a window.
@MainActor
enum OverlayProductionViewFactory {
  static func makeChooserView(
    model: OverlayChooserRenderModel,
    onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
  ) -> LayoutChooserView {
    LayoutChooserView(model: model, onSelect: onSelect)
  }

  static func makePreviewView(model: OverlayPreviewRenderModel) -> NSView {
    PlacementPreviewView(model: model)
  }
}

/// Owns transient chooser and preview presentation state. It never calls Accessibility,
/// reads screens, derives geometry, or commits a Window Action. Pointer/Input integration
/// drives selection through this Interface and decides when a selected action is committed.
@MainActor
final class OverlayCoordinator {
  private let renderer: any OverlayRendering
  var onEvent: @MainActor @Sendable (OverlayChooserEvent) -> Void
  private var presentationPolicy: OverlayPresentationPolicy
  private var chooser: OverlayChooserPresentation?
  private var selectedAction: ActionID?
  private var keyboardInput: LayoutChooserKeyboardInputAdapter?

  convenience init() {
    self.init(renderer: AppKitOverlayRenderer())
  }

  init(
    renderer: any OverlayRendering,
    accessibilityPreferences: OverlayAccessibilityPreferences = .init(),
    onEvent: @escaping @MainActor @Sendable (OverlayChooserEvent) -> Void = { _ in }
  ) {
    self.renderer = renderer
    presentationPolicy = OverlayPresentationPolicy(
      accessibilityPreferences: accessibilityPreferences)
    self.onEvent = onEvent
  }

  func installKeyboardInputAdapter(_ keyboardInput: LayoutChooserKeyboardInputAdapter) {
    self.keyboardInput?.setAcceptingInput(false)
    self.keyboardInput = keyboardInput
    keyboardInput.bind(to: self)
    keyboardInput.setAcceptingInput(chooser != nil)
  }

  func presentChooser(_ presentation: OverlayChooserPresentation)
    -> OverlayChooserPresentationResult
  {
    switch validate(presentation) {
    case .success:
      break
    case .failure(let failure):
      return .rejected(failure)
    }

    let selection = presentation.initialSelection ?? presentation.choices[0].action
    chooser = presentation
    selectedAction = selection
    keyboardInput?.setAcceptingInput(true)
    renderChooser()
    return .shown(action: selection)
  }

  /// Changes the policy used by the next chooser/preview render without recreating panels.
  /// If a chooser is visible it is immediately redrawn with the new policy.
  func updateAccessibilityPreferences(_ preferences: OverlayAccessibilityPreferences) {
    let policy = OverlayPresentationPolicy(accessibilityPreferences: preferences)
    guard policy != presentationPolicy else { return }
    presentationPolicy = policy
    if chooser != nil {
      renderChooser()
    }
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

    let padding = OverlayChooserVisualStyle.macOSNative.contentPadding
    let contentFrame = chooser.panelFrame.insetBy(dx: padding, dy: padding)
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
      guard case .selected(let action) = moveSelection(direction) else {
        return .ignored
      }
      return .selectionChanged(action: action)

    case .confirm:
      guard let selectedAction else { return .ignored }
      chooser = nil
      self.selectedAction = nil
      keyboardInput?.setAcceptingInput(false)
      renderer.dismiss()
      onEvent(.confirmed(action: selectedAction))
      return .confirmed(action: selectedAction)

    case .escape:
      guard chooser != nil else { return .ignored }
      chooser = nil
      selectedAction = nil
      keyboardInput?.setAcceptingInput(false)
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
    keyboardInput?.setAcceptingInput(false)
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
    if let initialSelection = presentation.initialSelection,
      !uniqueActions.contains(initialSelection)
    {
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
  private var chooserView: LayoutChooserView?

  func showChooser(
    _ model: OverlayChooserRenderModel,
    onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
  ) {
    if let chooserView, chooserView.canUpdate(with: model) {
      chooserView.updateSelection(model.selectedAction, onSelect: onSelect)
    } else {
      let view = OverlayProductionViewFactory.makeChooserView(
        model: model,
        onSelect: onSelect
      )
      chooserView = view
      chooserPanel.contentView = view
    }
    chooserPanel.setFrame(model.panelFrame, display: true)
    chooserPanel.orderFrontRegardless()
  }

  func showPreview(_ model: OverlayPreviewRenderModel) {
    previewPanel.contentView = OverlayProductionViewFactory.makePreviewView(model: model)
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
final class LayoutChooserView: NSVisualEffectView {
  private let choiceActions: [ActionID]
  private let columnCount: Int
  private var buttons: [ActionID: OverlayChoiceButton] = [:]

  init(
    model: OverlayChooserRenderModel,
    onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
  ) {
    choiceActions = model.choices.map(\.action)
    columnCount = model.columnCount
    super.init(frame: .zero)
    material = .hudWindow
    blendingMode = .withinWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = model.visualStyle.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    if model.presentationPolicy.background == .opaque {
      state = .inactive
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    if model.presentationPolicy.contrast == .increased {
      layer?.borderWidth = 2
      layer?.borderColor = NSColor.labelColor.cgColor
    } else {
      layer?.borderWidth = 1
      layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
    }

    let grid = NSGridView()
    grid.rowSpacing = model.visualStyle.itemSpacing
    grid.columnSpacing = model.visualStyle.itemSpacing
    grid.translatesAutoresizingMaskIntoConstraints = false

    var allButtons: [OverlayChoiceButton] = []
    for start in stride(from: 0, to: model.choices.count, by: model.columnCount) {
      let rowChoices = model.choices[start..<min(start + model.columnCount, model.choices.count)]
      let rowButtons = rowChoices.map { choice in
        let button = OverlayChoiceButton(
          choice: choice,
          isSelected: choice.action == model.selectedAction,
          contrast: model.presentationPolicy.contrast,
          style: model.visualStyle,
          onSelect: onSelect
        )
        buttons[choice.action] = button
        allButtons.append(button)
        return button
      }
      grid.addRow(with: rowButtons)
    }

    // Ensure all columns and rows have equal, stable sizing so buttons never shift
    for colIndex in 0..<grid.numberOfColumns {
      grid.column(at: colIndex).xPlacement = .fill
    }
    for rowIndex in 0..<grid.numberOfRows {
      grid.row(at: rowIndex).yPlacement = .fill
    }

    if let firstButton = allButtons.first {
      for button in allButtons.dropFirst() {
        button.widthAnchor.constraint(equalTo: firstButton.widthAnchor).isActive = true
        button.heightAnchor.constraint(equalTo: firstButton.heightAnchor).isActive = true
      }
    }

    addSubview(grid)
    NSLayoutConstraint.activate([
      grid.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: model.visualStyle.contentPadding),
      grid.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -model.visualStyle.contentPadding),
      grid.topAnchor.constraint(equalTo: topAnchor, constant: model.visualStyle.contentPadding),
      grid.bottomAnchor.constraint(
        equalTo: bottomAnchor, constant: -model.visualStyle.contentPadding),
    ])
    setAccessibilityLabel("Layout Chooser")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func canUpdate(with model: OverlayChooserRenderModel) -> Bool {
    choiceActions == model.choices.map(\.action) && columnCount == model.columnCount
  }

  func updateSelection(
    _ selectedAction: ActionID,
    onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
  ) {
    for (action, button) in buttons {
      button.update(isSelected: action == selectedAction, onSelect: onSelect)
    }
  }
}

@MainActor
private final class OverlayChoiceButton: NSButton {
  private let actionID: ActionID
  private let choiceTitle: String
  private let style: OverlayChooserVisualStyle
  private let contrast: OverlayContrastTreatment
  private var onSelect: @MainActor @Sendable (ActionID) -> Void

  private let glyphImageView = NSImageView()
  private let titleLabel = NSTextField()

  init(
    choice: OverlayLayoutChoice,
    isSelected: Bool,
    contrast: OverlayContrastTreatment,
    style: OverlayChooserVisualStyle,
    onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
  ) {
    actionID = choice.action
    choiceTitle = choice.title
    self.style = style
    self.contrast = contrast
    self.onSelect = onSelect
    super.init(frame: .zero)
    title = ""
    image = nil
    imagePosition = .noImage
    setAccessibilityLabel(choice.accessibilityLabel)
    setAccessibilityTitle(choice.title)
    setButtonType(.momentaryPushIn)
    isBordered = false
    state = isSelected ? .on : .off
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    updateAppearance(isSelected: isSelected)

    target = self
    action = #selector(didPress)
    translatesAutoresizingMaskIntoConstraints = false

    glyphImageView.translatesAutoresizingMaskIntoConstraints = false
    glyphImageView.imageScaling = .scaleProportionallyUpOrDown
    if style.usesLayoutGlyphs {
      glyphImageView.image = WindowsSnapGlyphRenderer.image(
        for: choice.action,
        isSelected: isSelected,
        contrast: contrast
      )
    }
    addSubview(glyphImageView)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.isBezeled = false
    titleLabel.drawsBackground = false
    titleLabel.isEditable = false
    titleLabel.isSelectable = false
    titleLabel.alignment = .center
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.font = .systemFont(ofSize: 10, weight: isSelected ? .semibold : .regular)
    titleLabel.textColor = contrast == .increased
      ? .labelColor
      : (isSelected ? .controlAccentColor : .secondaryLabelColor)
    titleLabel.stringValue = style.showsOnlySelectedTitle && !isSelected ? "" : choiceTitle
    // Never allow title text width to force-expand the button or grid
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    addSubview(titleLabel)

    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    NSLayoutConstraint.activate([
      widthAnchor.constraint(greaterThanOrEqualToConstant: style.minimumTargetSize.width),
      heightAnchor.constraint(greaterThanOrEqualToConstant: style.minimumTargetSize.height),

      glyphImageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      glyphImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      glyphImageView.widthAnchor.constraint(equalToConstant: 46),
      glyphImageView.heightAnchor.constraint(equalToConstant: 28),

      titleLabel.topAnchor.constraint(equalTo: glyphImageView.bottomAnchor, constant: 2),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      titleLabel.heightAnchor.constraint(equalToConstant: 14),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func didPress() {
    onSelect(actionID)
  }

  func update(
    isSelected: Bool,
    onSelect: @escaping @MainActor @Sendable (ActionID) -> Void
  ) {
    self.onSelect = onSelect
    state = isSelected ? .on : .off
    updateAppearance(isSelected: isSelected)

    if style.usesLayoutGlyphs {
      glyphImageView.image = WindowsSnapGlyphRenderer.image(
        for: actionID,
        isSelected: isSelected,
        contrast: contrast
      )
    }
    titleLabel.stringValue = style.showsOnlySelectedTitle && !isSelected ? "" : choiceTitle
    titleLabel.font = .systemFont(ofSize: 10, weight: isSelected ? .semibold : .regular)
    titleLabel.textColor = contrast == .increased
      ? .labelColor
      : (isSelected ? .controlAccentColor : .secondaryLabelColor)
  }

  private func updateAppearance(isSelected: Bool) {
    contentTintColor = contrast == .increased
      ? .labelColor
      : (isSelected ? .controlAccentColor : .secondaryLabelColor)

    if contrast == .increased {
      layer?.borderWidth = isSelected ? 2.5 : 1.5
      layer?.borderColor = isSelected ? NSColor.labelColor.cgColor : NSColor.secondaryLabelColor.cgColor
      layer?.backgroundColor = isSelected
        ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        : NSColor.clear.cgColor
    } else {
      layer?.borderWidth = isSelected ? 1.5 : 0.5
      layer?.borderColor = isSelected
        ? NSColor.controlAccentColor.cgColor
        : NSColor.separatorColor.withAlphaComponent(0.5).cgColor
      layer?.backgroundColor = isSelected
        ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        : NSColor.labelColor.withAlphaComponent(0.04).cgColor
    }
  }
}

/// Renders crisp Windows 11 Snap Bar style layout glyphs depicting screen zones and accent states.
@MainActor
enum WindowsSnapGlyphRenderer {
  static func image(
    for action: ActionID,
    isSelected: Bool,
    contrast: OverlayContrastTreatment
  ) -> NSImage {
    let size = CGSize(width: 46, height: 28)
    return NSImage(size: size, flipped: false) { _ in
      let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)

      // Outer screen bezel
      let screenPath = NSBezierPath(roundedRect: bounds, xRadius: 3.5, yRadius: 3.5)
      let screenFill = NSColor.windowBackgroundColor.withAlphaComponent(0.5)
      screenFill.setFill()
      screenPath.fill()

      let screenBorderColor: NSColor = contrast == .increased
        ? .labelColor
        : (isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.9)
            : NSColor.separatorColor.withAlphaComponent(0.8))
      screenBorderColor.setStroke()
      screenPath.lineWidth = contrast == .increased ? 1.5 : 1.0
      screenPath.stroke()

      // Inner area for window snap zones
      let innerRect = bounds.insetBy(dx: 2.5, dy: 2.5)
      let gap: CGFloat = 1.5

      let activeColor: NSColor = contrast == .increased
        ? (isSelected ? .labelColor : .secondaryLabelColor)
        : (isSelected ? .controlAccentColor : .secondaryLabelColor.withAlphaComponent(0.5))
      let inactiveColor: NSColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25)
      let zoneRadius: CGFloat = 1.5

      func drawZone(_ zoneRect: CGRect, active: Bool) {
        let path = NSBezierPath(roundedRect: zoneRect, xRadius: zoneRadius, yRadius: zoneRadius)
        if active {
          activeColor.setFill()
          path.fill()
        } else {
          inactiveColor.setFill()
          path.fill()
          if contrast == .increased {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
          }
        }
      }

      let halfW = (innerRect.width - gap) / 2
      let halfH = (innerRect.height - gap) / 2

      switch action {
      case .maximize:
        drawZone(innerRect, active: true)

      case .leftHalf:
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY, width: halfW, height: innerRect.height),
          active: true
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY, width: halfW, height: innerRect.height),
          active: false
        )

      case .rightHalf:
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY, width: halfW, height: innerRect.height),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY, width: halfW, height: innerRect.height),
          active: true
        )

      case .topHalf:
        // AppKit coordinates: top half is at innerRect.minY + halfH + gap
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY + halfH + gap, width: innerRect.width, height: halfH),
          active: true
        )
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY, width: innerRect.width, height: halfH),
          active: false
        )

      case .bottomHalf:
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY + halfH + gap, width: innerRect.width, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY, width: innerRect.width, height: halfH),
          active: true
        )

      case .topLeftQuarter:
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY + halfH + gap, width: halfW, height: halfH),
          active: true
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY + halfH + gap, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY, width: halfW, height: halfH),
          active: false
        )

      case .topRightQuarter:
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY + halfH + gap, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY + halfH + gap, width: halfW, height: halfH),
          active: true
        )
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY, width: halfW, height: halfH),
          active: false
        )

      case .bottomLeftQuarter:
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY + halfH + gap, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY + halfH + gap, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY, width: halfW, height: halfH),
          active: true
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY, width: halfW, height: halfH),
          active: false
        )

      case .bottomRightQuarter:
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY + halfH + gap, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY + halfH + gap, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX, y: innerRect.minY, width: halfW, height: halfH),
          active: false
        )
        drawZone(
          CGRect(x: innerRect.minX + halfW + gap, y: innerRect.minY, width: halfW, height: halfH),
          active: true
        )

      default:
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let symbol = NSImage(systemSymbolName: symbolName(for: action), accessibilityDescription: nil)?
          .withSymbolConfiguration(config) {
          let iconRect = CGRect(
            x: innerRect.midX - 7,
            y: innerRect.midY - 7,
            width: 14,
            height: 14
          )
          symbol.draw(in: iconRect)
        }
      }
      return true
    }
  }

  private static func symbolName(for action: ActionID) -> String {
    switch action {
    case .maximize: "rectangle.inset.filled"
    case .leftHalf: "rectangle.lefthalf.inset.filled"
    case .rightHalf: "rectangle.righthalf.inset.filled"
    case .topHalf: "rectangle.tophalf.inset.filled"
    case .bottomHalf: "rectangle.bottomhalf.inset.filled"
    case .topLeftQuarter: "arrow.up.left.square"
    case .topRightQuarter: "arrow.up.right.square"
    case .bottomLeftQuarter: "arrow.down.left.square"
    case .bottomRightQuarter: "arrow.down.right.square"
    default: "rectangle.grid.2x2"
    }
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
