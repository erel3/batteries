#!/usr/bin/env swift

// Draws App/Assets.xcassets/AppIcon.appiconset (`just app` compiles it with actool): the widget's battery ring with a charging bolt, one colour on a
// deep green squircle. Same recipe as LidGuard's icon (one-colour symbol, dark gradient),
// different background. Run with `just icon`; pass a path to also write a 1024 px preview PNG.

import AppKit
import Foundation

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let green = CGColor(colorSpace: sRGB, components: [0.30, 0.85, 0.42, 1])!  // #4CD96B

func drawIcon(pixels: Int) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
  // Apple's macOS icon grid: the squircle is 824 of 1024 px, centred, with a soft drop shadow.
  // Art that fills the whole canvas gets shrunk into a grey frame by newer macOS.
  let inset = CGFloat(pixels) * 100 / 1024
  ctx.translateBy(x: inset, y: inset)
  let s = CGFloat(pixels) - inset * 2
  drawBackground(ctx, s)
  drawRing(ctx, s)
  drawBolt(ctx, s)
  return rep
}

func drawBackground(_ ctx: CGContext, _ s: CGFloat) {
  let radius = s * 0.225
  let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: radius, cornerHeight: radius, transform: nil)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                color: CGColor(gray: 0, alpha: 0.35))
  ctx.addPath(path)
  ctx.fillPath()
  ctx.restoreGState()
  ctx.saveGState()
  ctx.addPath(path)
  ctx.clip()
  // Deep green, lighter at the top.
  let colors = [CGColor(colorSpace: sRGB, components: [0.07, 0.20, 0.13, 1])!,
                CGColor(colorSpace: sRGB, components: [0.03, 0.10, 0.06, 1])!]
  let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(gradient, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])
  ctx.restoreGState()
}

/// Track plus a three-quarter charge arc from 12 o'clock, clockwise, as BatteryRing draws it.
func drawRing(_ ctx: CGContext, _ s: CGFloat) {
  let center = CGPoint(x: s / 2, y: s / 2)
  let radius = s * 0.29
  ctx.saveGState()
  ctx.setLineWidth(s * 0.075)
  ctx.setLineCap(.round)
  ctx.setStrokeColor(green.copy(alpha: 0.22)!)
  ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
  ctx.strokePath()
  ctx.setStrokeColor(green)
  ctx.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: -.pi, clockwise: true)
  ctx.strokePath()
  ctx.restoreGState()
}

func drawBolt(_ ctx: CGContext, _ s: CGFloat) {
  let width = s * 0.20, height = s * 0.30
  let origin = CGPoint(x: (s - width) / 2, y: (s - height) / 2)
  let points: [(CGFloat, CGFloat)] = [(0.62, 1), (0, 0.42), (0.42, 0.42), (0.30, 0), (1, 0.60), (0.56, 0.60)]
  ctx.saveGState()
  ctx.setFillColor(green)
  ctx.setLineJoin(.round)
  ctx.setLineWidth(s * 0.012)
  ctx.setStrokeColor(green)
  ctx.addLines(between: points.map { CGPoint(x: origin.x + $0.0 * width, y: origin.y + $0.1 * height) })
  ctx.closePath()
  ctx.drawPath(using: .fillStroke)
  ctx.restoreGState()
}

let projectDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = projectDir.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    try drawIcon(pixels: points * scale).representation(using: .png, properties: [:])!
      .write(to: iconset.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
  }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
  .write(to: iconset.appendingPathComponent("Contents.json"))
print("Created \(iconset.path)")

if CommandLine.arguments.count > 1 {
  let preview = URL(fileURLWithPath: CommandLine.arguments[1])
  try drawIcon(pixels: 1024).representation(using: .png, properties: [:])!.write(to: preview)
  print("Preview \(preview.path)")
}
