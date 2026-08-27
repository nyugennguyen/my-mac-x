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
    private let hotkeyRuntime: HotkeyRuntimeCoordinator
    private let lifecycleCoordinator: AppLifecycleCoordinator

    override init() {
        let permissionManager = AccessibilityPermissionManager()
        let hotkeyManager = GlobalHotkeyManager(system: MacOSGlobalHotkeySystem())
        let settingsURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("My Mac X", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
        let settingsStore = SettingsStore(
            documents: LocalSettingsDocumentAdapter(documentURL: settingsURL),
            actionRegistry: .builtIn
        )
        let hotkeyRuntime = HotkeyRuntimeCoordinator(
            manager: hotkeyManager,
            bindingUpdater: HotkeyRuntimeBindingUpdater(
                store: settingsStore,
                manager: hotkeyManager
            ),
            dispatcher: HotkeyActionDispatcher(windowActions: WindowActionEngine())
        )
        self.permissionManager = permissionManager
        self.hotkeyRuntime = hotkeyRuntime
        lifecycleCoordinator = AppLifecycleCoordinator(
            system: AppKitAppShellSystem(),
            refreshAccessibilityPermission: {
                _ = permissionManager.refresh()
            },
            startHotkeyRuntime: {
                hotkeyRuntime.start()
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
