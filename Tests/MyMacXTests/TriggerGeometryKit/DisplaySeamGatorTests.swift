import CoreGraphics
import XCTest

@testable import MyMacX

final class DisplaySeamGatorTests: XCTestCase {
    // MARK: - S-04: Multi-Sample Pointer Trail Buffer (50 ms Window, 20 ms Floor, 512 Cap)

    func testS04_PointerTrailBufferSpanAndDivisorFloor() {
        var trail = PointerTrail()

        // 1. Minimum divisor floor (20 ms / 0.02 s)
        // Two points 5 ms apart (0.005 s) moving 10 pt
        // Without floor: 10 / 0.005 = 2000 pt/s
        // With 0.02 s floor: 10 / 0.02 = 500 pt/s
        trail.append(point: CGPoint(x: 100, y: 100), timestamp: 1.000)
        trail.append(point: CGPoint(x: 110, y: 100), timestamp: 1.005)

        let velocity = trail.velocity(at: 1.005)
        XCTAssertEqual(velocity.dx, 500.0, accuracy: 0.1)

        // 2. 50 ms span: samples older than 50 ms are pruned
        trail.append(point: CGPoint(x: 150, y: 100), timestamp: 1.060)
        // Sample at 1.000 is 60 ms older than 1.060, so it is pruned
        XCTAssertFalse(trail.samples.contains(where: { $0.timestamp == 1.000 }))

        // 3. Capacity cap at 512
        var largeTrail = PointerTrail()
        for i in 0..<600 {
            // All within 50 ms
            let t = 2.0 + Double(i) * 0.00005
            largeTrail.append(point: CGPoint(x: i, y: 0), timestamp: t)
        }
        XCTAssertLessThanOrEqual(largeTrail.samples.count, PointerTrail.capacity)
    }

    // MARK: - S-05: Raw Hardware Uptime Clock Stamping

    func testS05_HardwareUptimeClockStamping() {
        var trail = PointerTrail()
        // Hardware timestamp in nanoseconds: 5_000_000_000 ns = 5.0 s
        trail.append(point: CGPoint(x: 50, y: 50), timestampNano: 5_000_000_000)
        XCTAssertEqual(trail.samples.last?.timestamp, 5.0)

        // Synthetic / zero timestamp falls back to system uptime (> 0)
        trail.append(point: CGPoint(x: 60, y: 60), timestampNano: 0)
        let fallbackTimestamp = trail.samples.last?.timestamp ?? 0
        XCTAssertGreaterThan(fallbackTimestamp, 0)
    }

    // MARK: - S-06: Trail Pause Reset (100 ms Still Detection)

    func testS06_TrailPauseResetAfter100msStill() {
        var trail = PointerTrail()
        trail.append(point: CGPoint(x: 0, y: 0), timestamp: 1.0)
        trail.append(point: CGPoint(x: 50, y: 0), timestamp: 1.04)

        // Pause for 150 ms (>= 100 ms stillAfter)
        trail.append(point: CGPoint(x: 100, y: 0), timestamp: 1.20)

        // Previous sample at 1.04 was replaced by pause reset anchor
        XCTAssertFalse(trail.samples.contains(where: { $0.timestamp == 1.0 }))
        // Still evaluates from the rest anchor
        XCTAssertEqual(trail.samples.count, 2)
    }

    // MARK: - S-01: Outer Display Wall Immediate Flick Snapping

    func testS01_OuterDisplayWallSnapsAtAnySpeed() {
        // Single display: all edges are outer walls
        let display = makeDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let topology = DisplayTopologySnapshot(displays: [display], primaryDisplayID: display.id)
        let gator = DisplaySeamGator()

        // Fast flick against left outer wall: moving left at 1500 pt/s
        var trail = PointerTrail()
        trail.append(point: CGPoint(x: 60, y: 500), timestamp: 1.00)
        trail.append(point: CGPoint(x: 0, y: 500), timestamp: 1.04) // dx = -60 over 40 ms = -1500 pt/s

        let result = gator.evaluate(
            zone: .left,
            on: display,
            in: topology,
            trail: trail,
            evaluationTime: 1.04
        )

        XCTAssertEqual(result.boundary, .outerWall)
        XCTAssertTrue(result.isAllowed) // Outer wall allows snap at ANY speed!
    }

    // MARK: - S-02: Shared Display Seam Velocity Gating (400 pt/s Threshold)

    func testS02_SharedDisplaySeamGatedAt400Pts() {
        // Two displays: left (0...1000) and right (1000...2000). The seam is at x = 1000.
        let leftDisplay = makeDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let rightDisplay = makeDisplay(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000))
        let topology = DisplayTopologySnapshot(
            displays: [leftDisplay, rightDisplay],
            primaryDisplayID: leftDisplay.id
        )
        let gator = DisplaySeamGator()

        // 1. Fast crossing: moving right across seam at 800 pt/s (> 400 pt/s)
        var fastTrail = PointerTrail()
        fastTrail.append(point: CGPoint(x: 968, y: 500), timestamp: 1.00)
        fastTrail.append(point: CGPoint(x: 1000, y: 500), timestamp: 1.04) // 32 pt / 0.04 s = 800 pt/s

        let fastResult = gator.evaluate(
            zone: .right,
            on: leftDisplay,
            in: topology,
            trail: fastTrail,
            evaluationTime: 1.04
        )
        XCTAssertEqual(fastResult.boundary, .sharedSeam(neighborDisplayID: rightDisplay.id))
        XCTAssertFalse(fastResult.isAllowed) // Gated! Crossing too fast.

        // 2. Slow approach: moving right across seam at 250 pt/s (<= 400 pt/s)
        var slowTrail = PointerTrail()
        slowTrail.append(point: CGPoint(x: 990, y: 500), timestamp: 1.00)
        slowTrail.append(point: CGPoint(x: 1000, y: 500), timestamp: 1.04) // 10 pt / 0.04 s = 250 pt/s

        let slowResult = gator.evaluate(
            zone: .right,
            on: leftDisplay,
            in: topology,
            trail: slowTrail,
            evaluationTime: 1.04
        )
        XCTAssertEqual(slowResult.boundary, .sharedSeam(neighborDisplayID: rightDisplay.id))
        XCTAssertTrue(slowResult.isAllowed) // Allowed! Under 400 pt/s.
    }

    // MARK: - S-03: Independence of Parallel Velocity Along the Seam

    func testS03_IndependenceOfParallelVelocityAlongSeam() {
        // Vertical seam at x = 1000.
        let leftDisplay = makeDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let rightDisplay = makeDisplay(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000))
        let topology = DisplayTopologySnapshot(
            displays: [leftDisplay, rightDisplay],
            primaryDisplayID: leftDisplay.id
        )
        let gator = DisplaySeamGator()

        // Cursor travels rapidly down the edge (vy = 1000 pt/s), but slow normal velocity (vx = 100 pt/s)
        var trail = PointerTrail()
        trail.append(point: CGPoint(x: 996, y: 800), timestamp: 1.00)
        trail.append(point: CGPoint(x: 1000, y: 760), timestamp: 1.04) // dx = 4/0.04 = 100 pt/s, dy = -40/0.04 = -1000 pt/s

        let result = gator.evaluate(
            zone: .right,
            on: leftDisplay,
            in: topology,
            trail: trail,
            evaluationTime: 1.04
        )

        XCTAssertEqual(result.boundary, .sharedSeam(neighborDisplayID: rightDisplay.id))
        XCTAssertEqual(result.normalVelocity, 100.0, accuracy: 0.1)
        XCTAssertEqual(result.tangentialVelocity, 1000.0, accuracy: 0.1)
        XCTAssertTrue(result.isAllowed) // Parallel velocity is ignored; normal velocity 100 <= 400 passes!
    }

    // MARK: - S-07: Deferred Still-Check at Seams

    func testS07_DeferredStillCheckAtSeams() {
        let leftDisplay = makeDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let rightDisplay = makeDisplay(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000))
        let topology = DisplayTopologySnapshot(
            displays: [leftDisplay, rightDisplay],
            primaryDisplayID: leftDisplay.id
        )
        let gator = DisplaySeamGator()

        // Pointer arrived fast at 1.04 (vx = 800 pt/s)
        var trail = PointerTrail()
        trail.append(point: CGPoint(x: 968, y: 500), timestamp: 1.00)
        trail.append(point: CGPoint(x: 1000, y: 500), timestamp: 1.04)

        // At arrival time 1.04, it is blocked
        let arrivalResult = gator.evaluate(
            zone: .right,
            on: leftDisplay,
            in: topology,
            trail: trail,
            evaluationTime: 1.04
        )
        XCTAssertFalse(arrivalResult.isAllowed)

        // After stopping for 110 ms (at time 1.15 >= 1.04 + 0.10s):
        // Pointer is still; velocity evaluates to .zero <= 400
        let stillResult = gator.evaluate(
            zone: .right,
            on: leftDisplay,
            in: topology,
            trail: trail,
            evaluationTime: 1.15
        )
        XCTAssertEqual(stillResult.normalVelocity, 0.0)
        XCTAssertTrue(stillResult.isAllowed) // Deferred still check allows snap without further mouse events!
    }

    // MARK: - S-08: Still-Check Delay Calculation

    func testS08_StillCheckDelayCalculation() {
        var trail = PointerTrail()
        trail.append(point: CGPoint(x: 1000, y: 500), timestamp: 1.00)

        // At 1.03 (30 ms later), remaining delay until 100 ms is 70 ms (0.07 s)
        let remaining = trail.delayUntilStill(at: 1.03)
        XCTAssertEqual(remaining, 0.07, accuracy: 0.001)

        // At 1.12 (120 ms later), remaining delay is 0
        let expired = trail.delayUntilStill(at: 1.12)
        XCTAssertEqual(expired, 0.0, accuracy: 0.001)
    }

    // MARK: - S-09: Generational Invalidation of Seam Timers

    func testS09_GenerationalInvalidationOfStillCheck() {
        var session = SeamStillCheckSession()
        let token = session.generation

        XCTAssertTrue(session.isValid(generation: token))

        // Reset/cancel increments generation
        session.invalidate()
        XCTAssertFalse(session.isValid(generation: token))
        XCTAssertTrue(session.isValid(generation: session.generation))
    }

    // MARK: - Helper

    private func makeDisplay(id: UInt32, frame: CGRect) -> DisplaySnapshot {
        DisplaySnapshot(
            id: DisplayID(rawValue: id),
            frame: frame,
            visibleFrame: frame,
            backingScaleFactor: 2,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            ),
            notchTrigger: NotchTrigger(
                classification: .topCenterFallback,
                inferredNotchRegion: nil,
                region: .zero
            )
        )
    }
}
