import XCTest
@testable import MyMacX

@MainActor
final class AppLifecycleCoordinatorTests: XCTestCase {
    func testStartAppliesAccessoryPolicyAndInstallsMenuBarItem() {
        let system = AppShellSystemSpy()
        let coordinator = AppLifecycleCoordinator(system: system)

        coordinator.start()

        XCTAssertEqual(
            system.state,
            AppShellSystemState(accessoryPolicyApplications: 1, menuBarItemInstallations: 1)
        )
    }

    func testStartInstallsOnlyOneMenuBarItemWhenCalledRepeatedly() {
        let system = AppShellSystemSpy()
        let coordinator = AppLifecycleCoordinator(system: system)

        coordinator.start()
        coordinator.start()

        XCTAssertEqual(
            system.state,
            AppShellSystemState(accessoryPolicyApplications: 1, menuBarItemInstallations: 1)
        )
    }

    func testEachApplicationActivationRefreshesAccessibilityPermission() {
        let system = AppShellSystemSpy()
        var refreshCount = 0
        let coordinator = AppLifecycleCoordinator(
            system: system,
            refreshAccessibilityPermission: { refreshCount += 1 }
        )

        coordinator.applicationDidBecomeActive()
        coordinator.applicationDidBecomeActive()

        XCTAssertEqual(refreshCount, 2)
    }
}

@MainActor
private final class AppShellSystemSpy: AppShellSystem {
    private(set) var state = AppShellSystemState()

    func applyAccessoryActivationPolicy() {
        state.accessoryPolicyApplications += 1
    }

    func installMenuBarItem() {
        state.menuBarItemInstallations += 1
    }
}

private struct AppShellSystemState: Equatable {
    var accessoryPolicyApplications = 0
    var menuBarItemInstallations = 0
}
