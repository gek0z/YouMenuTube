#!/usr/bin/env swift
//
// Renders the YouMenuTube AppIcon at every macOS size required by
// Xcode's asset catalog and writes the 10 PNGs + Contents.json into
// Sources/Assets.xcassets/AppIcon.appiconset.
//
// Re-run whenever the design changes:
//   swift tools/gen_app_icon.swift
//
// Design: red squircle with a top→bottom gradient and a white optically
// centred play triangle. Mirrors the in-app `YouTubeLogo` mark.

import AppKit
import CoreGraphics
import Foundation

func render(sizePx: Int) -> Data {
    let s = CGFloat(sizePx)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: sizePx,
        height: sizePx,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    let cornerRadius = s * 0.2237  // approximates macOS's squircle
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil)

    // Background gradient — bright red at top, deeper red at bottom.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let bg = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1.00, green: 0.20, blue: 0.20, alpha: 1),
            CGColor(red: 0.78, green: 0.05, blue: 0.05, alpha: 1),
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        bg,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: 0, y: 0),
        options: [])
    ctx.restoreGState()

    // Top highlight — subtle glassy sheen.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let hl = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        hl,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: 0, y: s * 0.55),
        options: [])
    ctx.restoreGState()

    // Play triangle — equilateral pointing right, centroid at icon centre.
    // The vertices (r, 0), (-r/2, ±r·√3/2) average to (0, 0), so placing
    // them relative to (cx, cy) puts the centroid — i.e. the visual
    // balance point — exactly at the icon's centre. The tip extends
    // further right than the back extends left, which is the "play
    // button" look people expect (see SF Symbols' play.fill).
    let cx = s / 2
    let cy = s / 2
    let r = s * 0.28
    let h = r * sqrt(3) / 2
    let p1 = CGPoint(x: cx + r, y: cy)
    let p2 = CGPoint(x: cx - r / 2, y: cy + h)
    let p3 = CGPoint(x: cx - r / 2, y: cy - h)

    let tri = CGMutablePath()
    tri.move(to: p1)
    tri.addLine(to: p2)
    tri.addLine(to: p3)
    tri.closeSubpath()

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(tri)
    ctx.fillPath()

    let cgImage = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])!
}

let script = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let outDir = script.deletingLastPathComponent()
    .appendingPathComponent("Sources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

struct Spec {
    let point: Int
    let scale: Int
    var filename: String { scale == 1 ? "icon_\(point)x\(point).png" : "icon_\(point)x\(point)@2x.png" }
}

let specs: [Spec] = [
    .init(point: 16, scale: 1), .init(point: 16, scale: 2),
    .init(point: 32, scale: 1), .init(point: 32, scale: 2),
    .init(point: 128, scale: 1), .init(point: 128, scale: 2),
    .init(point: 256, scale: 1), .init(point: 256, scale: 2),
    .init(point: 512, scale: 1), .init(point: 512, scale: 2),
]

for spec in specs {
    let px = spec.point * spec.scale
    let data = render(sizePx: px)
    let file = outDir.appendingPathComponent(spec.filename)
    try! data.write(to: file)
    print("wrote \(spec.filename) (\(px)×\(px))")
}

// Contents.json
let images = specs.map {
    """
        {
          "idiom" : "mac",
          "size" : "\($0.point)x\($0.point)",
          "scale" : "\($0.scale)x",
          "filename" : "\($0.filename)"
        }
    """.trimmingCharacters(in: .whitespaces)
}
let manifest = """
    {
      "images" : [
    \(images.map { "    \($0)" }.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
try! manifest.write(
    to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
