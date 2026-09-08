import AppKit
import CoreGraphics

struct SuperHUDPresentation: Equatable {
  let panelFrame: CGRect
  let actionTitle: String?
}

enum SuperHUDState: Equatable {
  case waiting
  case submenu
  case pending
  case success
  case error
  case timeout
}

struct SuperHUDRenderModel: Equatable {
  let panelFrame: CGRect
  let state: SuperHUDState
  let title: String
  let detail: String
  let accessibilityLabel: String
  let presentationPolicy: OverlayPresentationPolicy
}

enum SuperHUDDismissal: Equatable {
  case escape
  case timeout
  case cancelled
  case feedbackCompleted
  case explicit
}

@MainActor
protocol SuperHUDRendering: AnyObject {
  func show(_ model: SuperHUDRenderModel)
  func dismiss()
}

@MainActor
protocol SuperHUDDismissScheduling: AnyObject {
  func schedule(after delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void)
  func cancel()
}

/// Maps reducer and Window Action outcomes onto a compact, non-activating Super Mode HUD.
/// Session matching prevents late action results from replacing a newer session's presentation.
@MainActor
final class SuperHUDCoordinator {
  private let renderer: any SuperHUDRendering
  private let dismissScheduler: any SuperHUDDismissScheduling
  private var presentationPolicy: OverlayPresentationPolicy
  private let feedbackDuration: TimeInterval
  private var activeSession: SuperModeSessionID?
  private var presentation: SuperHUDPresentation?
  private var lastRenderedState: SuperHUDState?
  private var lastRenderedTitle: String?
  private var lastRenderedDetail: String?
  private(set) var lastDismissal: SuperHUDDismissal?

  convenience init(accessibilityPreferences: OverlayAccessibilityPreferences = .init()) {
    self.init(
      renderer: AppKitSuperHUDRenderer(),
      dismissScheduler: TaskSuperHUDDismissScheduler(),
      accessibilityPreferences: accessibilityPreferences
    )
  }

  init(
    renderer: any SuperHUDRendering,
    dismissScheduler: any SuperHUDDismissScheduling,
    accessibilityPreferences: OverlayAccessibilityPreferences = .init(),
    feedbackDuration: TimeInterval = 0.8
  ) {
    self.renderer = renderer
    self.dismissScheduler = dismissScheduler
    presentationPolicy = OverlayPresentationPolicy(
      accessibilityPreferences: accessibilityPreferences)
    self.feedbackDuration = feedbackDuration
  }

  func present(transition: SuperModeTransition, presentation: SuperHUDPresentation) {
    switch transition.outcome {
    case .armed:
      guard case .armed(let session) = transition.current else { return }
      begin(session: session, presentation: presentation)
      show(.waiting, title: "Super Mode", detail: "Waiting for a key")
    case .submenuEntered:
      guard case .submenu(let session, _) = transition.current else { return }
      begin(session: session, presentation: presentation)
      show(.submenu, title: "Super Mode", detail: "Choose the next key")
    case .execute:
      guard let session = Self.session(from: transition.previous), session == activeSession else {
        return
      }
      self.presentation = presentation
      show(.pending, title: presentation.actionTitle ?? "Super Mode", detail: "Working…")
    case .cancelled(let reason):
      guard let session = Self.session(from: transition.previous), session == activeSession else {
        return
      }
      handleCancellation(reason)
    case .none:
      break
    }
  }

  func present(dispatchResult: SuperModeDispatchResult, session: SuperModeSessionID) {
    guard session == activeSession else { return }
    switch dispatchResult {
    case .dispatchedAppAction:
      show(.success, title: presentation?.actionTitle ?? "Action complete", detail: "Done")
      scheduleDismissal(.feedbackCompleted)
    case .dispatched(let result):
      switch result.disposition {
      case .succeeded:
        show(.success, title: presentation?.actionTitle ?? "Action complete", detail: "Done")
        scheduleDismissal(.feedbackCompleted)
      case .rejected:
        show(.error, title: "Action unavailable", detail: "Try another action")
        scheduleDismissal(.feedbackCompleted)
      case .superseded, .cancelled:
        dismiss(.cancelled)
      }
    case .unavailable:
      show(.error, title: "Action unavailable", detail: "Try another action")
      scheduleDismissal(.feedbackCompleted)
    }
  }

  func dismiss(_ reason: SuperHUDDismissal = .explicit) {
    dismissScheduler.cancel()
    renderer.dismiss()
    activeSession = nil
    presentation = nil
    lastRenderedState = nil
    lastRenderedTitle = nil
    lastRenderedDetail = nil
    lastDismissal = reason
  }

  func updateAccessibilityPreferences(_ preferences: OverlayAccessibilityPreferences) {
    let policy = OverlayPresentationPolicy(accessibilityPreferences: preferences)
    guard policy != presentationPolicy else { return }
    presentationPolicy = policy
    if let state = lastRenderedState,
      let title = lastRenderedTitle,
      let detail = lastRenderedDetail
    {
      show(state, title: title, detail: detail)
    }
  }

  private func begin(session: SuperModeSessionID, presentation: SuperHUDPresentation) {
    dismissScheduler.cancel()
    activeSession = session
    self.presentation = presentation
    lastDismissal = nil
  }

  private func handleCancellation(_ reason: SuperModeCancellationReason) {
    switch reason {
    case .invalidKey:
      show(.error, title: "Key not assigned", detail: "Press the Prefix to try again")
      scheduleDismissal(.feedbackCompleted)
    case .timeout:
      show(.timeout, title: "Super Mode timed out", detail: "Press the Prefix to try again")
      scheduleDismissal(.timeout)
    case .escape:
      dismiss(.escape)
    case .repeatedPrefix, .tapDisabled, .stopped:
      dismiss(.cancelled)
    }
  }

  private func show(_ state: SuperHUDState, title: String, detail: String) {
    guard let presentation else { return }
    lastRenderedState = state
    lastRenderedTitle = title
    lastRenderedDetail = detail
    let stateLabel: String
    switch state {
    case .waiting: stateLabel = "Waiting"
    case .submenu: stateLabel = "Submenu"
    case .pending: stateLabel = "Action in progress"
    case .success: stateLabel = "Success"
    case .error: stateLabel = "Error"
    case .timeout: stateLabel = "Timed out"
    }
    renderer.show(
      SuperHUDRenderModel(
        panelFrame: presentation.panelFrame,
        state: state,
        title: title,
        detail: detail,
        accessibilityLabel: "Super Mode. \(stateLabel). \(title). \(detail).",
        presentationPolicy: presentationPolicy
      ))
  }

  private func scheduleDismissal(_ reason: SuperHUDDismissal) {
    dismissScheduler.schedule(after: feedbackDuration) { [weak self] in self?.dismiss(reason) }
  }

  private static func session(from state: SuperModePresentationState) -> SuperModeSessionID? {
    switch state {
    case .armed(let session), .submenu(let session, _): session
    case .idle: nil
    }
  }
}

@MainActor
private final class TaskSuperHUDDismissScheduler: SuperHUDDismissScheduling {
  private var task: Task<Void, Never>?

  func schedule(after delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) {
    cancel()
    task = Task { @MainActor in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      action()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}

@MainActor
private final class AppKitSuperHUDRenderer: SuperHUDRendering {
  private let panel = SuperHUDPanel()

  func show(_ model: SuperHUDRenderModel) {
    panel.contentView = OverlayProductionViewFactory.makeSuperHUDView(model: model)
    panel.setFrame(model.panelFrame, display: true)
    panel.orderFrontRegardless()
  }

  func dismiss() {
    panel.orderOut(nil)
  }
}

@MainActor
extension OverlayProductionViewFactory {
  static func makeSuperHUDView(model: SuperHUDRenderModel) -> NSView {
    SuperHUDView(model: model)
  }
}

@MainActor
final class SuperHUDPanel: OverlayPresentationPanel {}

@MainActor
private final class SuperHUDView: NSVisualEffectView {
  init(model: SuperHUDRenderModel) {
    super.init(frame: .zero)
    material = .hudWindow
    blendingMode = .withinWindow
    state = model.presentationPolicy.background == .opaque ? .inactive : .active
    wantsLayer = true
    layer?.cornerRadius = 12
    if model.presentationPolicy.background == .opaque {
      layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    if model.presentationPolicy.contrast == .increased {
      layer?.borderWidth = 2
      layer?.borderColor = NSColor.labelColor.cgColor
    }

    let symbol = NSImageView(
      image: NSImage(
        systemSymbolName: Self.symbol(for: model.state),
        accessibilityDescription: nil
      ) ?? NSImage())
    symbol.contentTintColor = Self.tint(for: model.state)
    symbol.translatesAutoresizingMaskIntoConstraints = false

    let title = NSTextField(labelWithString: model.title)
    title.font = .systemFont(ofSize: 15, weight: .semibold)
    title.textColor = .labelColor
    let detail = NSTextField(labelWithString: model.detail)
    detail.font = .systemFont(ofSize: 12)
    detail.textColor = .secondaryLabelColor
    let labels = NSStackView(views: [title, detail])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 2
    labels.translatesAutoresizingMaskIntoConstraints = false

    addSubview(symbol)
    addSubview(labels)
    NSLayoutConstraint.activate([
      symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
      symbol.widthAnchor.constraint(equalToConstant: 22),
      symbol.heightAnchor.constraint(equalToConstant: 22),
      labels.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 12),
      labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      labels.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(model.accessibilityLabel)
    setAccessibilityHelp("Press Escape to dismiss Super Mode.")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private static func symbol(for state: SuperHUDState) -> String {
    switch state {
    case .waiting: "keyboard"
    case .submenu: "arrow.turn.down.right"
    case .pending: "ellipsis.circle"
    case .success: "checkmark.circle.fill"
    case .error: "exclamationmark.triangle.fill"
    case .timeout: "clock.fill"
    }
  }

  private static func tint(for state: SuperHUDState) -> NSColor {
    switch state {
    case .waiting, .submenu, .pending: .controlAccentColor
    case .success: .systemGreen
    case .error: .systemRed
    case .timeout: .systemOrange
    }
  }
}
