enum CapturedWindowFrameResult: Equatable, Sendable {
    case available(AXGlobalTopLeftFrame)
    case failed(WindowMutationFailure)
}

/// Exact-identity read seam used for planning and pre-mutation Window Snapshots.
protocol CapturedWindowFrameProviding: Sendable {
    func currentFrame(window: WindowIdentity) async -> CapturedWindowFrameResult
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
