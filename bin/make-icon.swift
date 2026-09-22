#!/usr/bin/env swift
//
//  make-icon.swift
//  Generate Yatu's AppIcon.icns.
//
//  The mark is a folder with a prompt caret inside it: Yatu opens a terminal *at
//  a folder*, and nothing else in a Finder toolbar is a folder. Every neighbour
//  (OpenInTerminal, OpenInTerminal-Lite, Go2Shell) is a terminal-window motif
//  with a prompt in it, and an aperture-with-caret was the same silhouette.
//  Chosen 2026-09-21; it replaces concept 7's aperture, and keeps its palette.
//
//  The .icns is deliberately NOT one drawing at ten sizes:
//
//    16pt and 32pt   a template glyph, one ink on transparent — what the Finder
//                    toolbar and list views draw
//    128pt and up    the colour tile — what the Dock, Get Info and Quick Look draw
//
//  Both are the same drawing. The tile is the glyph's folder in white, filled
//  black, with an amber caret, on a violet field; the glyph is that folder in
//  one grey ink with nothing behind it.
//
//  A Finder toolbar is a row of outline glyphs, and a colour tile in it looks
//  wrong. Upstream's icon is monochrome at every size, which is right for the
//  toolbar and wrong for the Dock. macOS picks a representation by size, so one
//  bundle can be both. The glyph cannot adapt to a dark toolbar — macOS does not
//  tint an app icon the way it tints a real template image — so its ink is a mid
//  grey chosen to stay legible on both.
//
//  A flat .icns, written from PNGs via iconutil — the only format that allows
//  different artwork by size. It is NOT Apple's documented implementation for
//  macOS 26 and later, which is an Icon Composer (.icon) document; see
//  docs/FINDER-TOOLBAR-ICONS.md. (An earlier version of this comment said Icon
//  Composer "stopped rendering" on 26.6. That was wrong: the GH-283 fix removed
//  duplicate icon sources, not the format.)
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

// MARK: - Palettes

struct TilePalette {
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    /// The folder's outline.
    let outline: NSColor
    /// What the folder is filled with.
    let inside: NSColor
    let caret: NSColor
}

let colourPalette = TilePalette(
    backgroundTop: rgb(120, 66, 168), backgroundBottom: rgb(74, 38, 118),
    outline: rgb(246, 247, 250), inside: rgb(14, 15, 19), caret: rgb(255, 178, 84))

let monochromePalette = TilePalette(
    backgroundTop: rgb(70, 74, 82), backgroundBottom: rgb(70, 74, 82),
    outline: .white, inside: rgb(70, 74, 82), caret: rgb(152, 156, 164))

/// Mid grey: an app icon is not tinted by the system, so one value has to work
/// on a light toolbar and a dark one.
let glyphInk = rgb(94, 98, 106)

// MARK: - The mark

/// A folder outline on a `z` x `z` canvas: body, and a raised tab at the left.
func folderOutline(_ z: CGFloat) -> NSBezierPath {
    let left = z * 0.12, right = z * 0.88
    let bottom = z * 0.20, bodyTop = z * 0.70, tabTop = z * 0.80
    let radius = z * 0.07

    let path = NSBezierPath()
    path.move(to: NSPoint(x: left, y: bottom + radius))
    path.appendArc(withCenter: NSPoint(x: left + radius, y: bottom + radius),
                   radius: radius, startAngle: 180, endAngle: 270)
    path.line(to: NSPoint(x: right - radius, y: bottom))
    path.appendArc(withCenter: NSPoint(x: right - radius, y: bottom + radius),
                   radius: radius, startAngle: 270, endAngle: 360)
    path.line(to: NSPoint(x: right, y: bodyTop - radius))
    path.appendArc(withCenter: NSPoint(x: right - radius, y: bodyTop - radius),
                   radius: radius, startAngle: 0, endAngle: 90)
    path.line(to: NSPoint(x: z * 0.52, y: bodyTop))
    path.line(to: NSPoint(x: z * 0.45, y: tabTop))
    path.line(to: NSPoint(x: left + radius, y: tabTop))
    path.appendArc(withCenter: NSPoint(x: left + radius, y: tabTop - radius),
                   radius: radius, startAngle: 90, endAngle: 180)
    path.close()
    return path
}

/// The folder and its caret, scaled about the canvas centre by `scale`.
///
/// The caret is set low and left in the folder's body, not centred in it. The
/// stroke width is given in canvas units, so a caller that scales the mark down
/// must pass a proportionally heavier line to keep the same optical weight.
func drawFolderMark(z: CGFloat, scale: CGFloat, lineWidth: CGFloat,
                    outline: NSColor, inside: NSColor?, caret: NSColor) {
    NSGraphicsContext.current?.saveGraphicsState()
    defer { NSGraphicsContext.current?.restoreGraphicsState() }

    let centre = z * 0.5
    let transform = NSAffineTransform()
    transform.translateX(by: centre, yBy: centre)
    transform.scale(by: scale)
    transform.translateX(by: -centre, yBy: -centre)
    transform.concat()

    let folder = folderOutline(z)
    if let inside {
        inside.setFill()
        folder.fill()
    }
    folder.lineWidth = lineWidth
    folder.lineJoinStyle = .round
    folder.lineCapStyle = .round
    outline.setStroke()
    folder.stroke()

    let mark = NSBezierPath()
    mark.lineWidth = lineWidth
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    mark.move(to: NSPoint(x: z * 0.36, y: z * 0.575))
    mark.line(to: NSPoint(x: z * 0.49, y: z * 0.465))
    mark.line(to: NSPoint(x: z * 0.36, y: z * 0.355))
    caret.setStroke()
    mark.stroke()
}

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

    // Scaled to sit inside the tile with margin; the line is heavier in canvas
    // units so its optical weight on the tile is ~0.06 of the icon.
    let scale: CGFloat = 0.66
    drawFolderMark(z: size, scale: scale, lineWidth: size * 0.06 / scale,
                   outline: palette.outline, inside: palette.inside, caret: palette.caret)
}

/// The glyph: the same folder and caret, one ink, no tile, at full canvas
/// because there is no tile to sit inside.
func drawGlyph(size: CGFloat) {
    // A proportional stroke is ~1.2px at 16px, where the caret is only a few
    // pixels tall and disappears into two grey dots. A floor keeps it a caret.
    let lineWidth = max(size * 0.075, 1.8)
    drawFolderMark(z: size, scale: 1, lineWidth: lineWidth,
                   outline: glyphInk, inside: nil, caret: glyphInk)
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
print("wrote \(outputPath) — folder and caret; \(description)")
