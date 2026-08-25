import AppKit

@main
@MainActor
enum MyMacXApplication {
    private static let applicationDelegate = ApplicationDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = applicationDelegate
        application.run()
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let permissionManager: AccessibilityPermissionManager
    private let lifecycleCoordinator: AppLifecycleCoordinator

    override init() {
        let permissionManager = AccessibilityPermissionManager()
        self.permissionManager = permissionManager
        lifecycleCoordinator = AppLifecycleCoordinator(
            system: AppKitAppShellSystem(),
            refreshAccessibilityPermission: {
                _ = permissionManager.refresh()
            }
        )
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        lifecycleCoordinator.applicationDidBecomeActive()
    }
}
