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
//  The .icns is deliberately NOT one drawing at ten sizes:
//
//    16pt and 32pt   a template glyph, one ink on transparent — what the Finder
//                    toolbar and list views draw
//    128pt and up    the colour tile — what the Dock, Get Info and Quick Look draw
//
//  A Finder toolbar is a row of outline glyphs, and both a colour tile and a
//  grey one read as a block dropped into that row; only a glyph belongs there.
//  Upstream solved this by being a glyph at every size, which is the right
//  answer for the toolbar and the wrong one for the Dock. macOS picks a
//  representation by size, so one bundle can be both.
//
//  The glyph cannot adapt to a dark toolbar — macOS does not tint an app icon
//  the way it tints a real template image — so its ink is a mid grey chosen to
//  stay legible against both light and dark toolbars.
//
//  Deliberately a flat .icns, written from PNGs via iconutil. There is NO
//  Icon Composer (.icon) bundle: that is exactly what stopped rendering in the
//  Finder toolbar on macOS 26.6 (upstream GH-283, our fix GH-287).
//
//  Usage: bin/make-icon.swift [output.icns] [--glyph|--monochrome|--colour]
//

import AppKit
import Foundation

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

/// How one representation is drawn.
enum Ink {
    /// The violet tile. The app icon proper.
    case colour
    /// One ink on transparent. Belongs in a toolbar.
    case glyph
    /// The tile in a single ink. Kept for a one-colour context that still
    /// wants a tile — printing, or a flattened asset.
    case monochromeTile
}

enum InkPolicy {
    /// Glyph up to and including 32pt, colour above it. The shipping policy.
    case bySize
    case always(Ink)

    func ink(atPointSize pointSize: Int) -> Ink {
        switch self {
        case .bySize: return pointSize <= 32 ? .glyph : .colour
        case .always(let ink): return ink
        }
    }
}

var outputPath = "Resources/AppIcon.icns"
var inkPolicy = InkPolicy.bySize

for argument in CommandLine.arguments.dropFirst() {
    switch argument {
    case "--glyph":
        inkPolicy = .always(.glyph)
    case "--monochrome":
        inkPolicy = .always(.monochromeTile)
    case "--colour", "--color":
        inkPolicy = .always(.colour)
    default:
        if argument.hasPrefix("-") {
            FileHandle.standardError.write(Data("unknown option: \(argument)\n".utf8))
            exit(2)
        }
        outputPath = argument
    }
}

// MARK: - Drawing

struct TilePalette {
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let ring: NSColor
    let innerField: NSColor
    let caret: NSColor
}

let colourPalette = TilePalette(
    backgroundTop: rgb(120, 66, 168), backgroundBottom: rgb(74, 38, 118),
    ring: rgb(246, 247, 250), innerField: rgb(14, 15, 19), caret: rgb(255, 178, 84))

let monochromePalette = TilePalette(
    backgroundTop: rgb(70, 74, 82), backgroundBottom: rgb(70, 74, 82),
    ring: .white, innerField: rgb(70, 74, 82), caret: rgb(152, 156, 164))

/// Mid grey: an app icon is not tinted by the system, so one value has to work
/// on a light toolbar and a dark one.
let glyphInk = rgb(94, 98, 106)

/// The tile: a macOS app-icon shape carrying the mark.
func drawTile(size: CGFloat, palette: TilePalette) {
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
}

/// The glyph: the same aperture and caret, one ink, no tile, drawn at a larger
/// optical scale because there is no tile to sit inside.
func drawGlyph(size: CGFloat) {
    let inset = size * 0.14
    let opening = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    let ring = NSBezierPath(roundedRect: opening, xRadius: size * 0.16, yRadius: size * 0.16)
    ring.lineWidth = size * 0.085
    glyphInk.setStroke()
    ring.stroke()

    let caret = NSBezierPath()
    caret.lineWidth = size * 0.085
    caret.lineCapStyle = .round
    caret.lineJoinStyle = .round
    caret.move(to: NSPoint(x: size * 0.375, y: size * 0.590))
    caret.line(to: NSPoint(x: size * 0.545, y: size * 0.470))
    caret.line(to: NSPoint(x: size * 0.375, y: size * 0.350))
    glyphInk.setStroke()
    caret.stroke()
}

func drawIcon(size: CGFloat, ink: Ink) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    switch ink {
    case .colour:         drawTile(size: size, palette: colourPalette)
    case .monochromeTile: drawTile(size: size, palette: monochromePalette)
    case .glyph:          drawGlyph(size: size)
    }
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

var glyphSizes: [Int] = []
for pointSize in [16, 32, 128, 256, 512] {
    let ink = inkPolicy.ink(atPointSize: pointSize)
    if case .glyph = ink { glyphSizes.append(pointSize) }
    for scale in [1, 2] {
        let pixels = pointSize * scale
        let suffix = scale == 1 ? "" : "@2x"
        try writePNG(drawIcon(size: CGFloat(pixels), ink: ink), pixels: pixels,
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

let description: String
switch inkPolicy {
case .bySize:
    description = "glyph at \(glyphSizes.map(String.init).joined(separator: "/"))pt, colour above"
case .always(.glyph):
    description = "glyph at every size"
case .always(.monochromeTile):
    description = "single-ink tile at every size"
case .always(.colour):
    description = "colour at every size"
}
print("wrote \(outputPath) — concept 7, Violet Aperture; \(description)")
