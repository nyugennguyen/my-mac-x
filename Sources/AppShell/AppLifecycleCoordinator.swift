import AppKit

@MainActor
protocol AppShellSystem: AnyObject {
    func applyAccessoryActivationPolicy()
    func installMenuBarItem()
}

@MainActor
final class AppLifecycleCoordinator {
    private let system: AppShellSystem
    private let refreshAccessibilityPermission: @MainActor () -> Void
    private var hasStarted = false

    init(
        system: AppShellSystem,
        refreshAccessibilityPermission: @escaping @MainActor () -> Void = {}
    ) {
        self.system = system
        self.refreshAccessibilityPermission = refreshAccessibilityPermission
    }

    func start() {
        guard !hasStarted else { return }

        hasStarted = true
        system.applyAccessoryActivationPolicy()
        system.installMenuBarItem()
    }

    func applicationDidBecomeActive() {
        refreshAccessibilityPermission()
    }
}

@MainActor
final class AppKitAppShellSystem: AppShellSystem {
    private let application: NSApplication
    private let statusBar: NSStatusBar
    private var statusItem: NSStatusItem?

    convenience init() {
        self.init(application: .shared, statusBar: .system)
    }

    init(application: NSApplication, statusBar: NSStatusBar) {
        self.application = application
        self.statusBar = statusBar
    }

    func applyAccessoryActivationPolicy() {
        application.setActivationPolicy(.accessory)
    }

    func installMenuBarItem() {
        guard statusItem == nil else { return }

        let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "My Mac X"
        item.button?.setAccessibilityLabel("My Mac X")
        statusItem = item
    }
}
