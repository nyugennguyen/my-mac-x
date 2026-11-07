import CoreGraphics
import Foundation

/// One timestamped point in a pointer trail buffer (S-04).
public struct PointerTrailSample: Equatable, Sendable {
    public let point: CGPoint
    public let timestamp: TimeInterval

    public init(point: CGPoint, timestamp: TimeInterval) {
        self.point = point
        self.timestamp = timestamp
    }
}

/// Rolling multi-sample pointer trail buffer for smoothing velocity calculations (S-04).
///
/// - Rolling time span: 0.05 s (50 ms).
/// - Minimum divisor floor: 0.02 s (20 ms).
/// - Buffer capacity: 512 samples.
/// - Still detection: 0.1 s (100 ms) idle interval resets trail history (S-06).
public struct PointerTrail: Equatable, Sendable {
    public static let span: TimeInterval = 0.05 // 50 ms
    public static let minimumSpan: TimeInterval = 0.02 // 20 ms
    public static let stillAfter: TimeInterval = 0.1 // 100 ms
    public static let capacity: Int = 512

    private(set) public var samples: [PointerTrailSample] = []

    public init() {}

    /// Appends a new pointer point. Nanosecond hardware timestamps are converted to seconds (S-05).
    public mutating func append(point: CGPoint, timestampNano: UInt64) {
        let seconds: TimeInterval
        if timestampNano > 0 {
            seconds = TimeInterval(timestampNano) / 1_000_000_000.0
        } else {
            seconds = Self.currentUptimeSeconds()
        }
        append(point: point, timestamp: seconds)
    }

    /// Appends a new pointer point with a floating-point seconds timestamp.
    public mutating func append(point: CGPoint, timestamp: TimeInterval) {
        if let last = samples.last {
            // S-06: Trail pause reset after 100 ms motionless
            if timestamp - last.timestamp >= Self.stillAfter {
                samples = [
                    PointerTrailSample(point: last.point, timestamp: timestamp - Self.minimumSpan),
                    PointerTrailSample(point: point, timestamp: timestamp)
                ]
                return
            }
        }

        samples.append(PointerTrailSample(point: point, timestamp: timestamp))

        // S-04: Prune samples older than 50 ms rolling span
        let cutoff = timestamp - Self.span
        samples.removeAll(where: { $0.timestamp < cutoff })

        // S-04: Cap capacity at 512
        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    /// Computes velocity vector (points per second) at given reference time.
    /// If pointer has paused for >= 100 ms, velocity evaluates to .zero (S-06, S-07).
    public func velocity(at referenceTime: TimeInterval? = nil) -> CGVector {
        guard let last = samples.last, let first = samples.first else {
            return .zero
        }

        let now = referenceTime ?? last.timestamp
        if now - last.timestamp >= Self.stillAfter {
            return .zero
        }

        let dt = max(last.timestamp - first.timestamp, Self.minimumSpan)
        let vx = (last.point.x - first.point.x) / dt
        let vy = (last.point.y - first.point.y) / dt
        return CGVector(dx: vx, dy: vy)
    }

    /// Calculates remaining delay until pointer is considered motionless (S-08).
    public func delayUntilStill(at referenceTime: TimeInterval? = nil) -> TimeInterval {
        guard let last = samples.last else { return Self.stillAfter }
        let now = referenceTime ?? Self.currentUptimeSeconds()
        let elapsed = max(0, now - last.timestamp)
        return min(max(0, Self.stillAfter - elapsed), Self.stillAfter)
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    public static func currentUptimeSeconds() -> TimeInterval {
        var ts = timespec()
        clock_gettime(CLOCK_UPTIME_RAW, &ts)
        return TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000.0
    }
}
