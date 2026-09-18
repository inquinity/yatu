#!/usr/bin/env swift
//
//  make-icon.swift
//  Generate Yatu's .icns from code.
//
//  Deliberately a flat .icns, written from PNGs via iconutil. There is NO
//  Icon Composer (.icon) bundle: that is exactly what stopped rendering in the
//  Finder toolbar on macOS 26.6 (upstream GH-283, our fix GH-287), and shipping
//  one again would reintroduce the bug this fork exists to avoid.
//
//  The current artwork is a PLACEHOLDER. The real icon comes from the concept
//  board in docs/icon-concepts/ (docs/YATU-PLAN.md §8.6). Until then this at
//  least gives every build a complete, correctly-sized icon.
//
//  Usage: bin/make-icon.swift [output.icns]
//

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"

/// Draw the placeholder mark at a given edge length.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let inset = size * 0.08
    let bounds = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let body = NSBezierPath(roundedRect: bounds,
                            xRadius: size * 0.22,
                            yRadius: size * 0.22)

    // A dark terminal-ish slab; the board will replace all of this.
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1.0),
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1.0),
    ])
    gradient?.draw(in: body, angle: -90)

    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    body.lineWidth = max(1, size * 0.006)
    body.stroke()

    // A prompt: chevron plus underscore, drawn rather than typeset so it scales
    // cleanly to 16pt without font hinting turning it to mush.
    let accent = NSColor(calibratedRed: 0.36, green: 0.80, blue: 0.62, alpha: 1.0)
    accent.setStroke()

    let stroke = NSBezierPath()
    stroke.lineWidth = size * 0.075
    stroke.lineCapStyle = .round
    stroke.lineJoinStyle = .round

    let chevronLeft = size * 0.30
    let chevronMiddle = size * 0.46
    let chevronTop = size * 0.64
    let chevronBottom = size * 0.36
    stroke.move(to: NSPoint(x: chevronLeft, y: chevronTop))
    stroke.line(to: NSPoint(x: chevronMiddle, y: size * 0.50))
    stroke.line(to: NSPoint(x: chevronLeft, y: chevronBottom))
    stroke.stroke()

    let underscore = NSBezierPath()
    underscore.lineWidth = size * 0.075
    underscore.lineCapStyle = .round
    underscore.move(to: NSPoint(x: size * 0.54, y: chevronBottom))
    underscore.line(to: NSPoint(x: size * 0.70, y: chevronBottom))
    underscore.stroke()

    return image
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else {
        throw NSError(domain: "make-icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot create a \(pixels)px bitmap"])
    }
    representation.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "cannot encode PNG"])
    }
    try data.write(to: url)
}

let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Yatu-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetURL) }

// The set iconutil expects: each point size at 1x and 2x.
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = pointSize * scale
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(pointSize)x\(pointSize)\(suffix).png"
        try writePNG(drawIcon(size: CGFloat(pixels)), pixels: pixels,
                     to: iconsetURL.appendingPathComponent(name))
    }
}

let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

print("wrote \(outputPath) (placeholder — see docs/YATU-PLAN.md §8.6)")
