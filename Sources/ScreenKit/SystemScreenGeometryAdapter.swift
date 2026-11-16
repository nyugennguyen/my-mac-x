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

/// System Adapter backed only by documented `NSScreen` geometry and display identity.
struct SystemScreenGeometryAdapter: ScreenGeometryAdapting {
    func captureDisplays() async -> ScreenGeometryCapture {
        await MainActor.run {
            let screens = NSScreen.screens
            return .displays(screens.enumerated().map { index, screen in
                candidate(for: screen, isPrimary: index == screens.startIndex)
            })
        }
    }

    @MainActor
    private func candidate(
        for screen: NSScreen,
        isPrimary: Bool
    ) -> DisplayGeometryCandidate {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let displayID = (screen.deviceDescription[screenNumberKey] as? NSNumber)
            .flatMap { number -> DisplayID? in
                let rawValue = number.uint32Value
                guard rawValue != kCGNullDirectDisplay else { return nil }
                return DisplayID(rawValue: rawValue)
            }
        let systemInsets = screen.safeAreaInsets

        return DisplayGeometryCandidate(
            displayID: displayID,
            isPrimary: isPrimary,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            backingScaleFactor: screen.backingScaleFactor,
            safeArea: DisplaySafeArea(
                insets: DisplayEdgeInsets(
                    top: systemInsets.top,
                    left: systemInsets.left,
                    bottom: systemInsets.bottom,
                    right: systemInsets.right
                ),
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea
            )
        )
    }
}

/// Production Adapter backed by AppKit's documented screen-parameter notification.
struct SystemScreenParameterChangeAdapter: ScreenParameterChangeAdapting {
    func changes() async -> AsyncStream<Void> {
        await MainActor.run {
            ApplicationScreenParameterRegistration.makeStream()
        }
    }
}

@MainActor
private final class ApplicationScreenParameterRegistration {
    private let notificationCenter: NotificationCenter
    private var token: NSObjectProtocol?

    private init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
    }

    static func makeStream(
        notificationCenter: NotificationCenter = .default
    ) -> AsyncStream<Void> {
        let registration = ApplicationScreenParameterRegistration(
            notificationCenter: notificationCenter
        )

        return AsyncStream { continuation in
            registration.token = notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    continuation.yield(())
                }
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    registration.cancel()
                }
            }
        }
    }

    private func cancel() {
        guard let token else { return }
        notificationCenter.removeObserver(token)
        self.token = nil
    }
}
