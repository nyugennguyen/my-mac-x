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

struct FocusedWindowProvider: FocusedWindowProviding {
    private let adapter: any AccessibilityWindowAdapting

    init() {
        adapter = SystemWindowAdapter.shared
    }

    init(adapter: any AccessibilityWindowAdapting) {
        self.adapter = adapter
    }

    func focusedWindow() async -> FocusedWindowResult {
        switch await adapter.captureFocusedWindow() {
        case .failure(let failure):
            return .unavailable(failure)
        case .unsupported:
            return .unavailable(.noEligibleWindow)
        case .candidate(let candidate):
            guard candidate.capabilities.participatesInWindowAction else {
                return .unavailable(.noEligibleWindow)
            }

            return .found(
                EligibleWindow(
                    identity: candidate.identity,
                    kind: candidate.kind,
                    capabilities: candidate.capabilities
                )
            )
        }
    }
}

protocol AccessibilityWindowAdapting: Sendable {
    func captureFocusedWindow() async -> AccessibilityWindowCapture
}

enum AccessibilityWindowCapture: Sendable {
    case candidate(AccessibilityWindowCandidate)
    case unsupported
    case failure(FocusedWindowFailure)
}

struct AccessibilityWindowCandidate: Sendable {
    let identity: WindowIdentity
    let kind: WindowKind
    let capabilities: WindowCapabilities

    init(
        identity: WindowIdentity,
        kind: WindowKind = .standard,
        capabilities: WindowCapabilities
    ) {
        self.identity = identity
        self.kind = kind
        self.capabilities = capabilities
    }
}

private extension WindowCapabilities {
    var participatesInWindowAction: Bool {
        minimized != .active
            && nativeFullScreen != .active
            && (isMovable || isResizable)
    }
}
