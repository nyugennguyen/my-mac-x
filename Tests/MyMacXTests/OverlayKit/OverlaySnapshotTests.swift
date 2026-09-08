import AppKit
import XCTest

@testable import MyMacX

@MainActor
final class OverlaySnapshotTests: XCTestCase {
  func testProductionViewsRenderPixelsAcrossAppearanceMatrix() throws {
    let variants: [(NSAppearance.Name, OverlayAccessibilityPreferences)] = [
      (.aqua, .init()), (.aqua, .init(reduceTransparency: true)),
      (.aqua, .init(increaseContrast: true)),
      (.aqua, .init(reduceTransparency: true, increaseContrast: true)),
      (.darkAqua, .init()), (.darkAqua, .init(reduceTransparency: true)),
      (.darkAqua, .init(increaseContrast: true)),
      (.darkAqua, .init(reduceTransparency: true, increaseContrast: true)),
    ]
    for (appearance, preferences) in variants {
      let policy = OverlayPresentationPolicy(accessibilityPreferences: preferences)
      let fixtures: [(String, NSView, CGSize)] = [
        (
          "chooser",
          OverlayProductionViewFactory.makeChooserView(model: chooser(policy), onSelect: { _ in }),
          .init(width: 360, height: 220)
        ),
        (
          "preview", OverlayProductionViewFactory.makePreviewView(model: preview(policy)),
          .init(width: 320, height: 180)
        ),
        (
          "hud", OverlayProductionViewFactory.makeSuperHUDView(model: hud(policy)),
          .init(width: 320, height: 64)
        ),
      ]
      for (name, view, size) in fixtures {
        let result = try signature(of: view, size: size, appearance: appearance)
        XCTAssertEqual(result.width, Int(size.width * 2), name)
        XCTAssertEqual(result.height, Int(size.height * 2), name)
        XCTAssertGreaterThan(result.visiblePixels, 0, name)
        XCTAssertNotEqual(result.digest, 0, name)
      }
    }
  }

  func testFixedProductionRenderIsDeterministic() throws {
    let policy = OverlayPresentationPolicy(
      accessibilityPreferences: .init(reduceTransparency: true))
    let a = OverlayProductionViewFactory.makeChooserView(model: chooser(policy), onSelect: { _ in })
    let b = OverlayProductionViewFactory.makeChooserView(model: chooser(policy), onSelect: { _ in })
    XCTAssertEqual(
      try signature(of: a, size: .init(width: 360, height: 220), appearance: .aqua).stable,
      try signature(of: b, size: .init(width: 360, height: 220), appearance: .aqua).stable
    )
  }

  func testMeaningfulStateChangesProducePixelDiffs() throws {
    let p = OverlayPresentationPolicy(accessibilityPreferences: .init(reduceTransparency: true))
    let views: [(NSView, NSView, CGSize)] = [
      (
        OverlayProductionViewFactory.makeChooserView(
          model: chooser(p, .maximize), onSelect: { _ in }),
        OverlayProductionViewFactory.makeChooserView(
          model: chooser(p, .rightHalf), onSelect: { _ in }), .init(width: 360, height: 220)
      ),
      (
        OverlayProductionViewFactory.makePreviewView(model: preview(p)),
        OverlayProductionViewFactory.makePreviewView(model: preview(p, true)),
        .init(width: 320, height: 180)
      ),
      (
        OverlayProductionViewFactory.makeSuperHUDView(model: hud(p)),
        OverlayProductionViewFactory.makeSuperHUDView(model: hud(p, .error)),
        .init(width: 320, height: 64)
      ),
    ]
    for (before, after, size) in views {
      XCTAssertNotEqual(
        try signature(of: before, size: size, appearance: .aqua).digest,
        try signature(of: after, size: size, appearance: .aqua).digest
      )
    }
  }
}

private struct StablePixelSignature: Equatable {
  let width: Int
  let height: Int
  let visiblePixels: Int
  let quantizedColorHistogram: [Int]
}

private struct PixelSignature: Equatable {
  let width: Int
  let height: Int
  let visiblePixels: Int
  let digest: UInt64
  let quantizedColorHistogram: [Int]

  var stable: StablePixelSignature {
    .init(
      width: width,
      height: height,
      visiblePixels: visiblePixels,
      quantizedColorHistogram: quantizedColorHistogram
    )
  }
}
private enum SnapshotFailure: Error { case bitmapAllocation, missingPixels }

@MainActor private func signature(of view: NSView, size: CGSize, appearance: NSAppearance.Name)
  throws -> PixelSignature
{
  view.appearance = NSAppearance(named: appearance)
  view.frame = .init(origin: .zero, size: size)
  view.layoutSubtreeIfNeeded()
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)
  else { throw SnapshotFailure.bitmapAllocation }
  bitmap.size = size
  view.cacheDisplay(in: view.bounds, to: bitmap)
  guard let bytes = bitmap.bitmapData else { throw SnapshotFailure.missingPixels }
  var digest: UInt64 = 14_695_981_039_346_656_037
  var visible = 0
  var colorHistogram = Array(repeating: 0, count: 64)
  for offset in stride(from: 0, to: bitmap.bytesPerRow * bitmap.pixelsHigh, by: 4) {
    if bytes[offset + 3] != 0 { visible += 1 }
    let bucket =
      Int(bytes[offset] >> 6) * 16
      + Int(bytes[offset + 1] >> 6) * 4
      + Int(bytes[offset + 2] >> 6)
    colorHistogram[bucket] += 1
    for channel in 0..<4 {
      digest ^= UInt64(bytes[offset + channel])
      digest &*= 1_099_511_628_211
    }
  }
  let stableHistogram = colorHistogram.map { (($0 + 127) / 256) * 256 }
  return .init(
    width: bitmap.pixelsWide,
    height: bitmap.pixelsHigh,
    visiblePixels: visible,
    digest: digest,
    quantizedColorHistogram: stableHistogram
  )
}

private func chooser(_ policy: OverlayPresentationPolicy, _ selected: ActionID = .maximize)
  -> OverlayChooserRenderModel
{
  .init(
    panelFrame: .init(x: 540, y: 720, width: 360, height: 220),
    choices: [
      .init(action: .maximize, title: "Maximize", accessibilityLabel: "Maximize"),
      .init(action: .leftHalf, title: "Left Half", accessibilityLabel: "Left Half"),
      .init(action: .rightHalf, title: "Right Half", accessibilityLabel: "Right Half"),
      .init(action: .topHalf, title: "Top Half", accessibilityLabel: "Top Half"),
      .init(action: .bottomHalf, title: "Bottom Half", accessibilityLabel: "Bottom Half"),
      .init(action: .topLeftQuarter, title: "Top Left", accessibilityLabel: "Top Left"),
    ], selectedAction: selected, columnCount: 3, presentationPolicy: policy)
}

private func preview(_ policy: OverlayPresentationPolicy, _ constrained: Bool = false)
  -> OverlayPreviewRenderModel
{
  .init(
    targetFrame: .init(x: 0, y: 25, width: 320, height: 180),
    isConstrainedByMinimumSize: constrained, presentationPolicy: policy)
}

private func hud(_ policy: OverlayPresentationPolicy, _ state: SuperHUDState = .waiting)
  -> SuperHUDRenderModel
{
  .init(
    panelFrame: .init(x: 520, y: 440, width: 320, height: 64), state: state,
    title: state == .error ? "Action unavailable" : "Super Mode",
    detail: state == .error ? "Try another action" : "Waiting for a key",
    accessibilityLabel: "Super Mode status", presentationPolicy: policy)
}
