#!/usr/bin/env swift
//
//  make-icon.swift
//  Generate Yatu's AppIcon.icns.
//
//  The mark is concept 7, "Violet Aperture", chosen 2026-09-18 from the board in
//  docs/icon-concepts/: a white rounded opening on a violet field, the inner
//  field held black so the violet reads as a surround rather than as the screen,
//  and an amber caret set low and left rather than centred in the opening.
//
//  Deliberately a flat .icns, written from PNGs via iconutil. There is NO
//  Icon Composer (.icon) bundle: that is exactly what stopped rendering in the
//  Finder toolbar on macOS 26.6 (upstream GH-283, our fix GH-287), and shipping
//  one again would reintroduce the bug this fork exists to avoid.
//
//  --monochrome draws the single-ink variant of record: a light mark on a dark
//  field. The inverted form (dark on light) was rejected — the mark is carried
//  by a bright caret on black inside a light ring, and inverting collapses all
//  three contrasts at once. See docs/icon-concepts/README.md.
//
//  Usage: bin/make-icon.swift [output.icns] [--monochrome]
//

import AppKit
import Foundation

var outputPath = "Resources/AppIcon.icns"
var monochrome = false

for argument in CommandLine.arguments.dropFirst() {
    if argument == "--monochrome" {
        monochrome = true
    } else if argument.hasPrefix("-") {
        FileHandle.standardError.write(Data("unknown option: \(argument)\n".utf8))
        exit(2)
    } else {
        outputPath = argument
    }
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

struct Palette {
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let ring: NSColor
    let innerField: NSColor
    let caret: NSColor
}

let palette = monochrome
    ? Palette(backgroundTop: rgb(70, 74, 82), backgroundBottom: rgb(70, 74, 82),
              ring: .white, innerField: rgb(70, 74, 82), caret: rgb(152, 156, 164))
    : Palette(backgroundTop: rgb(120, 66, 168), backgroundBottom: rgb(74, 38, 118),
              ring: rgb(246, 247, 250), innerField: rgb(14, 15, 19), caret: rgb(255, 178, 84))

/// Concept 7 at an arbitrary edge length. Every measurement is a fraction of the
/// icon, so the 16pt and 1024pt renderings are the same drawing.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // The macOS app-icon shape.
    let inset = size * 0.085
    let body = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
        xRadius: size * 0.225, yRadius: size * 0.225)
    NSGradient(colors: [palette.backgroundTop, palette.backgroundBottom])?.draw(in: body, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    body.lineWidth = max(1, size * 0.005)
    body.stroke()

    let ringInset = size * 0.265
    let opening = NSRect(x: ringInset, y: ringInset,
                         width: size - ringInset * 2, height: size - ringInset * 2)

    let inner = NSBezierPath(roundedRect: opening, xRadius: size * 0.075, yRadius: size * 0.075)
    palette.innerField.setFill()
    inner.fill()

    let ring = NSBezierPath(roundedRect: opening, xRadius: size * 0.075, yRadius: size * 0.075)
    ring.lineWidth = size * 0.070
    palette.ring.setStroke()
    ring.stroke()

    // Set low and left rather than centred in the opening.
    let caret = NSBezierPath()
    caret.lineWidth = size * 0.070
    caret.lineCapStyle = .round
    caret.lineJoinStyle = .round
    caret.move(to: NSPoint(x: size * 0.388, y: size * 0.537))
    caret.line(to: NSPoint(x: size * 0.518, y: size * 0.452))
    caret.line(to: NSPoint(x: size * 0.388, y: size * 0.367))
    palette.caret.setStroke()
    caret.stroke()

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
        try writePNG(drawIcon(size: CGFloat(pixels)), pixels: pixels,
                     to: iconsetURL.appendingPathComponent("icon_\(pointSize)x\(pointSize)\(suffix).png"))
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

print("wrote \(outputPath) — concept 7, Violet Aperture\(monochrome ? " (single ink)" : "")")
