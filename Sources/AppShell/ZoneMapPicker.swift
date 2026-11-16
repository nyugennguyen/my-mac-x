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
import SwiftUI

// MARK: - Zone Map Glyph Geometry

/// Computes normalized unit rectangles (in [0, 1] space) for rendering
/// thumbnail glyphs representing edge snap zone actions and multi-area partitions.
public enum ZoneMapGlyphGeometry {
    public static func regions(for action: ActionID) -> [CGRect] {
        switch action {
        case .maximize:
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        case .leftHalf:
            return [CGRect(x: 0, y: 0, width: 0.5, height: 1)]
        case .rightHalf:
            return [CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .topHalf:
            return [CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]
        case .bottomHalf:
            return [CGRect(x: 0, y: 0, width: 1, height: 0.5)]
        case .topLeftQuarter:
            return [CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)]
        case .topRightQuarter:
            return [CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]
        case .bottomLeftQuarter:
            return [CGRect(x: 0, y: 0, width: 0.5, height: 0.5)]
        case .bottomRightQuarter:
            return [CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)]
        case .leftThird:
            return [CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)]
        case ActionID(rawValue: "window.center-third"):
            return [CGRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)]
        case ActionID(rawValue: "window.right-third"):
            return [CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)]
        case .leftTwoThirds:
            return [CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)]
        case ActionID(rawValue: "window.right-two-thirds"):
            return [CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)]
        case ActionID(rawValue: "window.top-third"):
            return [CGRect(x: 0, y: 2.0 / 3.0, width: 1, height: 1.0 / 3.0)]
        case ActionID(rawValue: "window.middle-third"):
            return [CGRect(x: 0, y: 1.0 / 3.0, width: 1, height: 1.0 / 3.0)]
        case ActionID(rawValue: "window.bottom-third"):
            return [CGRect(x: 0, y: 0, width: 1, height: 1.0 / 3.0)]
        case ActionID(rawValue: "window.left-quarter"):
            return [CGRect(x: 0, y: 0, width: 0.25, height: 1)]
        case ActionID(rawValue: "window.left-middle-quarter"):
            return [CGRect(x: 0.25, y: 0, width: 0.25, height: 1)]
        case ActionID(rawValue: "window.right-middle-quarter"):
            return [CGRect(x: 0.5, y: 0, width: 0.25, height: 1)]
        case ActionID(rawValue: "window.right-quarter"):
            return [CGRect(x: 0.75, y: 0, width: 0.25, height: 1)]
        case ActionID(rawValue: "window.top-quarter"):
            return [CGRect(x: 0, y: 0.75, width: 1, height: 0.25)]
        case ActionID(rawValue: "window.upper-middle-quarter"):
            return [CGRect(x: 0, y: 0.5, width: 1, height: 0.25)]
        case ActionID(rawValue: "window.lower-middle-quarter"):
            return [CGRect(x: 0, y: 0.25, width: 1, height: 0.25)]
        case ActionID(rawValue: "window.bottom-quarter"):
            return [CGRect(x: 0, y: 0, width: 1, height: 0.25)]
        default:
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
    }

    public static func regions(for actions: [ActionID], in zone: EdgeSnapZone) -> [CGRect] {
        guard !actions.isEmpty else {
            return regions(for: zone.defaultAction)
        }
        if actions.count == 1 {
            return regions(for: actions[0])
        }

        let count = actions.count
        if zone.isHorizontalEdge {
            return (0..<count).map { i in
                let w = 1.0 / CGFloat(count)
                let x = CGFloat(i) * w
                return CGRect(x: x, y: 0, width: w, height: 1.0)
            }
        } else {
            return (0..<count).map { i in
                let h = 1.0 / CGFloat(count)
                let y = CGFloat(count - 1 - i) * h
                return CGRect(x: 0, y: y, width: 1.0, height: h)
            }
        }
    }
}

// MARK: - Save Debouncer

/// Coalesces rapid zone mutations into a debounced disk persistence save.
@MainActor
public final class ZoneMapSaveDebouncer {
    private let delay: TimeInterval
    private let onSave: (EdgeSnapZoneConfigurationSnapshot) -> Void
    private var pendingSnapshot: EdgeSnapZoneConfigurationSnapshot?
    private var task: Task<Void, Never>?

    public init(
        delay: TimeInterval = 0.3,
        onSave: @escaping (EdgeSnapZoneConfigurationSnapshot) -> Void
    ) {
        self.delay = delay
        self.onSave = onSave
    }

    public func schedule(snapshot: EdgeSnapZoneConfigurationSnapshot) {
        pendingSnapshot = snapshot
        task?.cancel()
        task = Task { @MainActor [weak self, delay] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.flush()
        }
    }

    public func flush() {
        task?.cancel()
        task = nil
        if let snapshot = pendingSnapshot {
            pendingSnapshot = nil
            onSave(snapshot)
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        pendingSnapshot = nil
    }

    public var hasPendingSave: Bool {
        pendingSnapshot != nil
    }
}

// MARK: - Zone Map Picker ViewModel

@MainActor
public final class ZoneMapPickerViewModel: ObservableObject {
    public let store: EdgeSnapZoneConfigurationStore
    @Published public var selectedZone: EdgeSnapZone?
    @Published public var hoveredZone: EdgeSnapZone?

    private let debouncer: ZoneMapSaveDebouncer

    public init(
        store: EdgeSnapZoneConfigurationStore,
        initialSelectedZone: EdgeSnapZone? = .top,
        debounceDelay: TimeInterval = 0.3,
        onSave: (@MainActor (EdgeSnapZoneConfigurationSnapshot) -> Void)? = nil
    ) {
        self.store = store
        self.selectedZone = initialSelectedZone
        let debouncer = ZoneMapSaveDebouncer(delay: debounceDelay) { snapshot in
            onSave?(snapshot)
        }
        self.debouncer = debouncer
        store.onConfigurationChanged = { [weak self] snapshot in
            self?.debouncer.schedule(snapshot: snapshot)
        }
    }

    public func select(zone: EdgeSnapZone?) {
        selectedZone = zone
    }

    public func hover(zone: EdgeSnapZone?) {
        hoveredZone = zone
    }

    public func isZoneEnabled(_ zone: EdgeSnapZone) -> Bool {
        store.isEnabled(zone)
    }

    public func setZoneEnabled(_ isEnabled: Bool, for zone: EdgeSnapZone) {
        store.setEnabled(isEnabled, for: zone)
    }

    public func toggleZoneEnabled(for zone: EdgeSnapZone) {
        store.toggleEnabled(for: zone)
    }

    public func actions(for zone: EdgeSnapZone) -> [ActionID] {
        store.actions(for: zone)
    }

    public func partitionCount(for zone: EdgeSnapZone) -> Int {
        store.actions(for: zone).count
    }

    public func setPartitionCount(_ count: Int, for zone: EdgeSnapZone) {
        guard zone.isStraightEdge else { return }
        let clamped = min(max(count, 1), 4)
        let newActions = zone.defaultPartitions(count: clamped)
        store.setActions(newActions, for: zone)
    }

    public func setAction(_ action: ActionID, for zone: EdgeSnapZone, at partitionIndex: Int = 0) {
        var current = store.actions(for: zone)
        if zone.isCorner {
            store.setAction(action, for: zone)
            return
        }
        if partitionIndex >= 0 && partitionIndex < current.count {
            current[partitionIndex] = action
            store.setActions(current, for: zone)
        }
    }

    public func resetZone(_ zone: EdgeSnapZone) {
        store.reset(zone: zone)
    }

    public func resetAllZones() {
        store.resetAllToDefaults()
    }

    public func isZoneDefault(_ zone: EdgeSnapZone) -> Bool {
        store.isDefault(zone: zone)
    }

    public var isAllDefault: Bool {
        store.isAllDefault
    }

    public func glyphRegions(for zone: EdgeSnapZone) -> [CGRect] {
        let acts = store.actions(for: zone)
        return ZoneMapGlyphGeometry.regions(for: acts, in: zone)
    }

    public func flushSave() {
        debouncer.flush()
    }
}

// MARK: - Permitted Actions Registry

public extension ActionRegistry {
    static var edgeSnapPermittedActions: [ActionDescriptor] {
        var list = ActionRegistry.builtIn.actions.filter { EdgeSnapZone.isPermittedAction($0.id) }
        let present = Set(list.map(\.id))

        let additional: [(ActionID, String, String)] = [
            (ActionID(rawValue: "window.right-third"), "Right Third", "rectangle.righthalf.filled"),
            (ActionID(rawValue: "window.center-third"), "Center Third", "rectangle.centerthird.inset.filled"),
            (ActionID(rawValue: "window.left-two-thirds"), "Left Two Thirds", "rectangle.lefthalf.filled"),
            (ActionID(rawValue: "window.right-two-thirds"), "Right Two Thirds", "rectangle.righthalf.filled"),
            (ActionID(rawValue: "window.top-third"), "Top Third", "rectangle.tophalf.filled"),
            (ActionID(rawValue: "window.middle-third"), "Middle Third", "rectangle.centerhalf.inset.filled"),
            (ActionID(rawValue: "window.bottom-third"), "Bottom Third", "rectangle.bottomhalf.filled"),
            (ActionID(rawValue: "window.left-quarter"), "Left Quarter", "rectangle.split.3x1"),
            (ActionID(rawValue: "window.left-middle-quarter"), "Left-Middle Quarter", "rectangle.split.3x1"),
            (ActionID(rawValue: "window.right-middle-quarter"), "Right-Middle Quarter", "rectangle.split.3x1"),
            (ActionID(rawValue: "window.right-quarter"), "Right Quarter", "rectangle.split.3x1"),
            (ActionID(rawValue: "window.top-quarter"), "Top Quarter", "rectangle.split.1x2"),
            (ActionID(rawValue: "window.upper-middle-quarter"), "Upper-Middle Quarter", "rectangle.split.1x2"),
            (ActionID(rawValue: "window.lower-middle-quarter"), "Lower-Middle Quarter", "rectangle.split.1x2"),
            (ActionID(rawValue: "window.bottom-quarter"), "Bottom Quarter", "rectangle.split.1x2"),
        ]

        for (id, title, symbol) in additional {
            if !present.contains(id) && EdgeSnapZone.isPermittedAction(id) {
                list.append(ActionDescriptor(id: id, title: title, symbolName: symbol, availability: .available))
            }
        }
        return list
    }
}

// MARK: - Zone Map Picker View

public struct ZoneMapPickerView: View {
    @ObservedObject public var model: ZoneMapPickerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: ZoneMapPickerViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with reset all button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsCopy.edgeSnapZoneMapTitle)
                        .font(SettingsTypography.rowTitle)
                        .foregroundStyle(.primary)
                    Text(SettingsCopy.edgeSnapZoneMapCaption)
                        .font(SettingsTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    model.resetAllZones()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(model.isAllDefault)
                .accessibilityLabel(SettingsCopy.resetAllZonesToDefaults)
                .accessibilityIdentifier(SettingsAccessibilityID.zoneMapResetAll)
            }

            // 3x3 Screen Miniature Grid
            HStack(alignment: .center, spacing: 16) {
                gridMiniature
                    .accessibilityIdentifier(SettingsAccessibilityID.zoneMapPicker)
                Spacer()
            }

            // Selected Zone Inspector Card
            if let selected = model.selectedZone {
                zoneInspector(for: selected)
            } else {
                Text(SettingsCopy.selectZonePrompt)
                    .font(SettingsTypography.rowCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 3x3 Grid

    private var gridMiniature: some View {
        let rows: [[EdgeSnapZone?]] = [
            [.topLeft, .top, .topRight],
            [.left, nil, .right],
            [.bottomLeft, .bottom, .bottomRight]
        ]

        return VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { c in
                        if let zone = rows[r][c] {
                            zoneCell(zone)
                        } else {
                            centerCell
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func zoneCell(_ zone: EdgeSnapZone) -> some View {
        let isSelected = model.selectedZone == zone
        let isHovered = model.hoveredZone == zone
        let isEnabled = model.isZoneEnabled(zone)

        return Button {
            model.select(zone: zone)
        } label: {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(nsColor: .controlAccentColor).opacity(0.15)
                            : (isHovered ? Color(nsColor: .separatorColor).opacity(0.25) : Color(nsColor: .windowBackgroundColor).opacity(0.5))
                    )

                // Glyph
                LayoutThumbnailView(
                    regions: model.glyphRegions(for: zone),
                    isSelected: isSelected,
                    size: CGSize(width: 44, height: 28)
                )
                .opacity(isEnabled ? 1.0 : 0.35)

                // Disabled strikethrough badge
                if !isEnabled {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
            .frame(width: 48, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color(nsColor: .controlAccentColor)
                            : (isHovered ? Color(nsColor: .separatorColor) : Color.clear),
                        lineWidth: isSelected ? 1.5 : 0.8
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            model.hover(zone: isHovering ? zone : nil)
        }
        .accessibilityLabel("\(SettingsCopy.zoneTitle(zone)), \(isEnabled ? SettingsCopy.permissionGranted : SettingsCopy.unavailable)")
        .accessibilityIdentifier(SettingsAccessibilityID.zoneCell(zone))
    }

    private var centerCell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.2))
            Image(systemName: "display")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .frame(width: 48, height: 34)
    }

    // MARK: - Inspector Detail

    private func zoneInspector(for zone: EdgeSnapZone) -> some View {
        let isEnabled = model.isZoneEnabled(zone)
        let isDefault = model.isZoneDefault(zone)
        let actions = model.actions(for: zone)

        return VStack(alignment: .leading, spacing: 12) {
            Divider()

            // Inspector Header
            HStack {
                Text(SettingsCopy.zoneTitle(zone))
                    .font(SettingsTypography.rowTitle)
                    .foregroundStyle(.primary)

                Spacer()

                Button(SettingsCopy.resetZoneToDefault) {
                    model.resetZone(zone)
                }
                .font(SettingsTypography.rowCaption)
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .buttonStyle(.plain)
                .disabled(isDefault)
                .accessibilityIdentifier(SettingsAccessibilityID.zoneMapResetZone)
            }

            // Enable / Disable switch (Z-08)
            Toggle(
                SettingsCopy.enableEdgeSnapZone,
                isOn: Binding(
                    get: { model.isZoneEnabled(zone) },
                    set: { model.setZoneEnabled($0, for: zone) }
                )
            )

            if isEnabled {
                if zone.isStraightEdge {
                    // Straight Edge: Partitions (1..4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(SettingsCopy.partitionCountTitle)
                                .font(SettingsTypography.rowCaption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { model.partitionCount(for: zone) },
                                set: { model.setPartitionCount($0, for: zone) }
                            )) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                                Text("3").tag(3)
                                Text("4").tag(4)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                            .accessibilityIdentifier(SettingsAccessibilityID.zoneMapPartitionPicker)
                        }

                        // Sub-partition Action Pickers
                        ForEach(0..<actions.count, id: \.self) { index in
                            HStack {
                                Text(SettingsCopy.partitionAreaLabel(index: index, total: actions.count))
                                    .font(SettingsTypography.rowCaption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                actionPicker(selectedAction: actions[index]) { newAction in
                                    model.setAction(newAction, for: zone, at: index)
                                }
                            }
                        }
                    }
                } else {
                    // Corner: Single Action Picker
                    HStack {
                        Text(SettingsCopy.trigger)
                            .font(SettingsTypography.rowCaption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        actionPicker(selectedAction: actions.first ?? zone.defaultAction) { newAction in
                            model.setAction(newAction, for: zone, at: 0)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func actionPicker(selectedAction: ActionID, onSelect: @escaping (ActionID) -> Void) -> some View {
        Picker("", selection: Binding(
            get: { selectedAction },
            set: { onSelect($0) }
        )) {
            ForEach(ActionRegistry.edgeSnapPermittedActions, id: \.id) { descriptor in
                Text(descriptor.title).tag(descriptor.id)
            }
        }
        .frame(minWidth: 160)
    }
}

// MARK: - System Tiling Stand-Down Banner

public struct SystemTilingStandDownBanner: View {
    public let reason: SystemTilingStandDownReason?

    public init(reason: SystemTilingStandDownReason? = nil) {
        self.reason = reason
    }

    public var body: some View {
        HStack(alignment: .top, spacing: SettingsSpacing.rowGap) {
            IconTile(systemName: "exclamationmark.triangle.fill", tint: .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(SettingsCopy.systemTilingStandDownBannerTitle)
                    .font(SettingsTypography.rowTitle)
                    .foregroundStyle(.primary)
                Text(SettingsCopy.systemTilingStandDownBannerMessage)
                    .font(SettingsTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            CapsuleBadge("SYSTEM TILING", tint: .systemOrange)
        }
        .padding(SettingsCardLayout.padding)
        .background(
            RoundedRectangle(cornerRadius: SettingsCardLayout.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .systemOrange).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsCardLayout.cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .systemOrange).opacity(0.35), lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SettingsAccessibilityID.systemTilingBanner)
    }
}
