// MyMacX
// Copyright (C) 2026 NyugenNguyen
//
// This program is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// See the LICENSE file for details.

import AppKit
import CoreGraphics
import Foundation

/// Seam for window-server window frame queries (D-09).
///
/// Communicates directly with the Quartz WindowServer via `CGWindowListCopyWindowInfo`.
/// Does not call Accessibility IPC, does not touch `AXUIElement`, and requires no Screen Recording permission
/// for bounds and process ID.
public protocol WindowServerWindowSampling: Sendable {
    func windowBounds(windowID: CGWindowID) async -> CGRect?
    func topmostWindow(at point: CGPoint) async -> (windowID: CGWindowID, bounds: CGRect, processID: pid_t)?
}

/// Production WindowServer sampler using public CoreGraphics APIs.
public struct MacOSWindowServerSampler: WindowServerWindowSampling {
    public init() {}

    public func windowBounds(windowID: CGWindowID) async -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let windowDict = list.first,
              let boundsDict = windowDict[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else {
            return nil
        }
        return rect
    }

    public func topmostWindow(at point: CGPoint) async -> (windowID: CGWindowID, bounds: CGRect, processID: pid_t)? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for dict in list {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowNumber = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else {
                continue
            }

            // Note: Quartz bounds use top-left origin
            if bounds.contains(point) {
                return (windowNumber, bounds, pid)
            }
        }

        return nil
    }
}

/// Information captured for one authentic window move during an Edge Snap Run (D-10).
public struct ResolvedEdgeSnapCandidate: Equatable, Sendable {
    public let generation: UInt64
    public let windowID: CGWindowID
    public let initialFrame: CGRect
    public let windowIdentity: WindowIdentity
    public let bundleIdentifier: String?

    public init(
        generation: UInt64,
        windowID: CGWindowID,
        initialFrame: CGRect,
        windowIdentity: WindowIdentity,
        bundleIdentifier: String?
    ) {
        self.generation = generation
        self.windowID = windowID
        self.initialFrame = initialFrame
        self.windowIdentity = windowIdentity
        self.bundleIdentifier = bundleIdentifier
    }
}

public typealias ResolvedSnapTarget = ResolvedEdgeSnapCandidate

/// Failure outcomes during off-thread target resolution.
public enum TargetResolutionFailure: Error, Equatable, Sendable {
    case timedOut
    case noEligibleWindow
    case applicationExcluded
    case cancelled
    case staleGeneration
}

/// Off-thread target resolution engine with bounded AX timeout and generational cancellation (D-10).
public struct EdgeSnapTargetResolver: Sendable {
    private let sampler: any WindowServerWindowSampling
    private let accessibility: any AccessibilityWindowAdapting
    private let appRules: any AppRuleDeciding
    private let timeoutMilliseconds: UInt64
    private let bundleIDResolver: @Sendable (pid_t) -> String?

    init(
        sampler: any WindowServerWindowSampling = MacOSWindowServerSampler(),
        accessibility: any AccessibilityWindowAdapting = SystemWindowAdapter.shared,
        appRules: any AppRuleDeciding,
        timeoutMilliseconds: UInt64 = 280,
        bundleIDResolver: @escaping @Sendable (pid_t) -> String? = { pid in
            NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
    ) {
        self.sampler = sampler
        self.accessibility = accessibility
        self.appRules = appRules
        self.timeoutMilliseconds = timeoutMilliseconds
        self.bundleIDResolver = bundleIDResolver
    }

    /// Resolves the candidate window under `location` off the main thread.
    ///
    /// - Parameters:
    ///   - location: Pointer position at mouse-down.
    ///   - generation: Monotonic generation ID of the current mouse press.
    ///   - activeGeneration: Closure returning the current active generation to check for stale results.
    public func resolveTarget(
        at location: CGPoint,
        generation: UInt64,
        activeGeneration: @escaping @Sendable () -> UInt64
    ) async -> Result<ResolvedEdgeSnapCandidate, TargetResolutionFailure> {
        // Generational check before starting
        guard activeGeneration() == generation else {
            return .failure(.staleGeneration)
        }

        // 1. Identify window from WindowServer
        guard let candidate = await sampler.topmostWindow(at: location) else {
            return .failure(.noEligibleWindow)
        }

        // Generational check after window-server query
        guard activeGeneration() == generation else {
            return .failure(.staleGeneration)
        }

        // 2. Resolve bundle identifier and evaluate per-app rules (fail closed)
        let bundleID = bundleIDResolver(candidate.processID)
        let decision = await appRules.decision(for: bundleID)
        guard decision == .included else {
            return .failure(.applicationExcluded)
        }

        // 3. Resolve Accessibility handle with bounded timeout off-main
        let accessibility = self.accessibility
        let axResult: AccessibilityWindowCapture
        do {
            axResult = try await withThrowingTaskGroup(of: AccessibilityWindowCapture.self) { group in
                group.addTask {
                    await accessibility.captureFocusedWindow()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: self.timeoutMilliseconds * 1_000_000)
                    throw TargetResolutionFailure.timedOut
                }

                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch let failure as TargetResolutionFailure {
            return .failure(failure)
        } catch {
            return .failure(.timedOut)
        }

        // Generational check after AX resolution
        guard activeGeneration() == generation else {
            return .failure(.staleGeneration)
        }

        guard case let .candidate(windowCandidate) = axResult else {
            return .failure(.noEligibleWindow)
        }

        guard windowCandidate.identity.processID == candidate.processID else {
            return .failure(.noEligibleWindow)
        }

        let target = ResolvedEdgeSnapCandidate(
            generation: generation,
            windowID: candidate.windowID,
            initialFrame: candidate.bounds,
            windowIdentity: windowCandidate.identity,
            bundleIdentifier: bundleID
        )

        return .success(target)
    }
}
