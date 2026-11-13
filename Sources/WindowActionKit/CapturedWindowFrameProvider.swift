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

enum CapturedWindowFrameResult: Equatable, Sendable {
    case available(AXGlobalTopLeftFrame)
    case failed(WindowMutationFailure)
}

/// Exact-identity read seam used for planning and pre-mutation Window Snapshots.
protocol CapturedWindowFrameProviding: Sendable {
    func currentFrame(window: WindowIdentity) async -> CapturedWindowFrameResult
}

/// Exact-identity seam for resolving the owning app without exposing window content.
protocol CapturedWindowApplicationIdentifying: Sendable {
    func bundleIdentifier(for window: WindowIdentity) async -> String?
}

/// Keeps inspection on the same actor-confined Accessibility Adapter that owns identity.
struct AccessibilityCapturedWindowFrameAdapter: CapturedWindowFrameProviding {
    private let adapter: any AccessibilityWindowMutationAdapting

    init(adapter: any AccessibilityWindowMutationAdapting) {
        self.adapter = adapter
    }

    func currentFrame(window: WindowIdentity) async -> CapturedWindowFrameResult {
        switch await adapter.inspectWindow(window) {
        case .available(let inspection):
            return .available(inspection.frame)
        case .failure(.permissionRequired):
            return .failed(.accessibilityPermissionRequired)
        case .failure(.windowDisappeared):
            return .failed(.windowDisappeared)
        case .failure(.temporarilyUnavailable), .failure(.rejected):
            return .failed(.mutationRejected)
        }
    }
}
