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

@testable import MyMacX

struct InMemoryScreenGeometryAdapter: ScreenGeometryAdapting {
    let capture: ScreenGeometryCapture

    func captureDisplays() async -> ScreenGeometryCapture {
        capture
    }
}

actor ScriptedScreenGeometryProvider: ScreenGeometryProviding {
    private let results: [ScreenGeometryResult]
    private var index = 0
    private(set) var captureCount = 0

    init(results: [ScreenGeometryResult]) {
        precondition(!results.isEmpty)
        self.results = results
    }

    func displays() -> ScreenGeometryResult {
        captureCount += 1
        let result = results[min(index, results.index(before: results.endIndex))]
        index += 1
        return result
    }
}

actor InMemoryScreenParameterChangeAdapter: ScreenParameterChangeAdapting {
    private var continuation: AsyncStream<Void>.Continuation?
    private(set) var cancellationCount = 0

    var hasActiveObservation: Bool {
        continuation != nil
    }

    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.didCancel() }
            }
        }
    }

    func send() {
        continuation?.yield(())
    }

    private func didCancel() {
        continuation = nil
        cancellationCount += 1
    }
}
