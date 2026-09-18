#!/usr/bin/env swift
//
//  make-concepts.swift
//  Render Yatu's icon concept board.
//
//  These are controlled source art, not exploration renders: each concept is
//  drawn from geometry, so the one that is chosen is already production art and
//  needs no redrawing. Run this, look at the two boards, pick a number.
//
//  Usage: docs/icon-concepts/make-concepts.swift [output directory]
//

import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath:
    CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/icon-concepts")

// MARK: - Palette

struct Palette {
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let mark: NSColor
    let accent: NSColor
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

// MARK: - Concepts

struct Concept {
    let slug: String
    let name: String
    let note: String
    let palette: Palette
    let draw: (CGFloat, Palette) -> Void
}

/// The macOS app-icon shape: a continuous rounded square with a soft vertical
/// gradient. Every concept shares it so the comparison is about the mark.
func drawBackground(size: CGFloat, palette: Palette) {
    let inset = size * 0.085
    let bounds = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let body = NSBezierPath(roundedRect: bounds, xRadius: size * 0.225, yRadius: size * 0.225)
    NSGradient(colors: [palette.backgroundTop, palette.backgroundBottom])?.draw(in: body, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    body.lineWidth = max(1, size * 0.005)
    body.stroke()
}

/// A folder silhouette: body plus raised left tab. Used by several concepts.
func folderPath(size: CGFloat, inset: CGFloat) -> NSBezierPath {
    let width = size - inset * 2
    let bodyHeight = width * 0.66
    let bottom = (size - bodyHeight) / 2 - size * 0.02
    let tabHeight = width * 0.11
    let tabWidth = width * 0.40
    let corner = size * 0.055

    let path = NSBezierPath()
    path.move(to: NSPoint(x: inset, y: bottom + corner))
    path.appendArc(withCenter: NSPoint(x: inset + corner, y: bottom + corner),
                   radius: corner, startAngle: 180, endAngle: 270)
    path.line(to: NSPoint(x: inset + width - corner, y: bottom))
    path.appendArc(withCenter: NSPoint(x: inset + width - corner, y: bottom + corner),
                   radius: corner, startAngle: 270, endAngle: 360)
    path.line(to: NSPoint(x: inset + width, y: bottom + bodyHeight - corner))
    path.appendArc(withCenter: NSPoint(x: inset + width - corner, y: bottom + bodyHeight - corner),
                   radius: corner, startAngle: 0, endAngle: 90)
    path.line(to: NSPoint(x: inset + tabWidth, y: bottom + bodyHeight))
    path.line(to: NSPoint(x: inset + tabWidth - tabHeight * 0.9, y: bottom + bodyHeight + tabHeight))
    path.line(to: NSPoint(x: inset + corner, y: bottom + bodyHeight + tabHeight))
    path.appendArc(withCenter: NSPoint(x: inset + corner, y: bottom + bodyHeight + tabHeight - corner),
                   radius: corner, startAngle: 90, endAngle: 180)
    path.close()
    return path
}

let concepts: [Concept] = [

    Concept(
        slug: "01-folder-prompt",
        name: "Folder Prompt",
        note: "The folder tab is bitten into a caret. One silhouette says both words.",
        palette: Palette(backgroundTop: rgb(64, 84, 178), backgroundBottom: rgb(38, 52, 124),
                         mark: rgb(248, 250, 255), accent: rgb(120, 228, 178))
    ) { size, palette in
        let folder = folderPath(size: size, inset: size * 0.235)
        palette.mark.setFill()
        folder.fill()

        // The caret is cut out of the folder body, so it survives as negative
        // space when the whole mark collapses to a silhouette.
        let caret = NSBezierPath()
        caret.lineWidth = size * 0.075
        caret.lineCapStyle = .round
        caret.lineJoinStyle = .round
        caret.move(to: NSPoint(x: size * 0.395, y: size * 0.560))
        caret.line(to: NSPoint(x: size * 0.510, y: size * 0.452))
        caret.line(to: NSPoint(x: size * 0.395, y: size * 0.344))
        palette.backgroundBottom.setStroke()
        caret.stroke()
    },

    Concept(
        slug: "02-aperture",
        name: "Aperture",
        note: "A square opening with a solid caret inside. Reads as a button, which is what it is.",
        palette: Palette(backgroundTop: rgb(38, 42, 52), backgroundBottom: rgb(20, 22, 28),
                         mark: rgb(246, 247, 250), accent: rgb(255, 178, 84))
    ) { size, palette in
        let ringInset = size * 0.265
        let ring = NSBezierPath(roundedRect:
            NSRect(x: ringInset, y: ringInset, width: size - ringInset * 2, height: size - ringInset * 2),
            xRadius: size * 0.075, yRadius: size * 0.075)
        ring.lineWidth = size * 0.070
        palette.mark.setStroke()
        ring.stroke()

        let caret = NSBezierPath()
        caret.lineWidth = size * 0.070
        caret.lineCapStyle = .round
        caret.lineJoinStyle = .round
        caret.move(to: NSPoint(x: size * 0.430, y: size * 0.585))
        caret.line(to: NSPoint(x: size * 0.560, y: size * 0.500))
        caret.line(to: NSPoint(x: size * 0.430, y: size * 0.415))
        palette.accent.setStroke()
        caret.stroke()
    },

    Concept(
        slug: "03-doorway",
        name: "Doorway",
        note: "A folder with a lit slot: the terminal as a way in, not as a window.",
        palette: Palette(backgroundTop: rgb(46, 116, 96), backgroundBottom: rgb(22, 74, 62),
                         mark: rgb(244, 248, 245), accent: rgb(255, 214, 112))
    ) { size, palette in
        let folder = folderPath(size: size, inset: size * 0.235)
        palette.mark.setFill()
        folder.fill()

        let slotWidth = size * 0.105
        let slot = NSBezierPath(roundedRect:
            NSRect(x: size * 0.500 - slotWidth / 2, y: size * 0.330,
                   width: slotWidth, height: size * 0.250),
            xRadius: slotWidth / 2, yRadius: slotWidth / 2)
        palette.accent.setFill()
        slot.fill()
    },

    Concept(
        slug: "04-descent",
        name: "Descent",
        note: "Two chevrons aimed into the corner — cd, without a folder drawn at all.",
        palette: Palette(backgroundTop: rgb(120, 66, 168), backgroundBottom: rgb(74, 38, 118),
                         mark: rgb(248, 245, 255), accent: rgb(150, 232, 210))
    ) { size, palette in
        func chevron(offset: CGFloat, color: NSColor) {
            let path = NSBezierPath()
            path.lineWidth = size * 0.080
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: size * 0.330 + offset, y: size * 0.635))
            path.line(to: NSPoint(x: size * 0.500 + offset, y: size * 0.465))
            path.line(to: NSPoint(x: size * 0.330 + offset, y: size * 0.295))
            color.setStroke()
            path.stroke()
        }
        chevron(offset: size * 0.145, color: palette.accent)
        chevron(offset: 0, color: palette.mark)
    },

    Concept(
        slug: "05-block-cursor",
        name: "Block Cursor",
        note: "One solid cursor on a baseline. The simplest thing that still says terminal.",
        palette: Palette(backgroundTop: rgb(30, 34, 44), backgroundBottom: rgb(16, 18, 24),
                         mark: rgb(124, 236, 168), accent: rgb(96, 104, 126))
    ) { size, palette in
        let block = NSBezierPath(roundedRect:
            NSRect(x: size * 0.370, y: size * 0.455, width: size * 0.260, height: size * 0.230),
            xRadius: size * 0.030, yRadius: size * 0.030)
        palette.mark.setFill()
        block.fill()

        let baseline = NSBezierPath(roundedRect:
            NSRect(x: size * 0.310, y: size * 0.330, width: size * 0.380, height: size * 0.058),
            xRadius: size * 0.029, yRadius: size * 0.029)
        palette.accent.setFill()
        baseline.fill()
    },

    Concept(
        slug: "06-corner-fold",
        name: "Corner Fold",
        note: "A folder with its corner turned back, dark terminal underneath. The most literal.",
        palette: Palette(backgroundTop: rgb(196, 92, 72), backgroundBottom: rgb(148, 56, 46),
                         mark: rgb(250, 244, 238), accent: rgb(32, 34, 42))
    ) { size, palette in
        let inset = size * 0.255
        let width = size - inset * 2
        let height = width * 0.80
        let bottom = (size - height) / 2
        let fold = width * 0.42

        let sheet = NSBezierPath()
        sheet.move(to: NSPoint(x: inset, y: bottom))
        sheet.line(to: NSPoint(x: inset + width, y: bottom))
        sheet.line(to: NSPoint(x: inset + width, y: bottom + height - fold))
        sheet.line(to: NSPoint(x: inset + width - fold, y: bottom + height))
        sheet.line(to: NSPoint(x: inset, y: bottom + height))
        sheet.close()
        palette.mark.setFill()
        sheet.fill()

        let turned = NSBezierPath()
        turned.move(to: NSPoint(x: inset + width - fold, y: bottom + height))
        turned.line(to: NSPoint(x: inset + width - fold, y: bottom + height - fold))
        turned.line(to: NSPoint(x: inset + width, y: bottom + height - fold))
        turned.close()
        palette.accent.setFill()
        turned.fill()

        let caret = NSBezierPath()
        caret.lineWidth = size * 0.055
        caret.lineCapStyle = .round
        caret.lineJoinStyle = .round
        caret.move(to: NSPoint(x: inset + width * 0.17, y: bottom + height * 0.62))
        caret.line(to: NSPoint(x: inset + width * 0.34, y: bottom + height * 0.44))
        caret.line(to: NSPoint(x: inset + width * 0.17, y: bottom + height * 0.26))
        palette.accent.setStroke()
        caret.stroke()
    },
]

// MARK: - Rendering

func render(_ concept: Concept, pixels: Int, monochrome: Bool = false) -> NSBitmapImageRep {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    representation.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    let size = CGFloat(pixels)

    // The toolbar draws the icon small and flat; rendering each concept in one
    // ink is the honest test of whether the mark survives that treatment.
    let palette = monochrome
        ? Palette(backgroundTop: rgb(70, 74, 82), backgroundBottom: rgb(70, 74, 82),
                  mark: .white, accent: rgb(150, 154, 162))
        : concept.palette

    drawBackground(size: size, palette: palette)
    concept.draw(size, palette)

    NSGraphicsContext.restoreGraphicsState()
    return representation
}

func writePNG(_ representation: NSBitmapImageRep, to url: URL) throws {
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-concepts", code: 1)
    }
    try data.write(to: url)
}

func label(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular,
           color: NSColor = NSColor(calibratedWhite: 0.14, alpha: 1)) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(at: point)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// Individual concepts at full size.
for concept in concepts {
    try writePNG(render(concept, pixels: 512),
                 to: outputDirectory.appendingPathComponent("\(concept.slug).png"))
}

// Board 1: the concepts side by side at app-icon scale.
do {
    let tile = 200, columns = 3, rows = 2
    let gutter = 34, topMargin = 74, captionHeight = 46
    let width = gutter + columns * (tile + gutter)
    let height = topMargin + rows * (tile + captionHeight + gutter)

    let sheet = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)

    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    label("Yatu — icon concepts", at: NSPoint(x: gutter, y: height - 50), size: 26, weight: .semibold)

    for (index, concept) in concepts.enumerated() {
        let column = index % columns, row = index / columns
        let x = gutter + column * (tile + gutter)
        let y = height - topMargin - (row + 1) * (tile + captionHeight + gutter) + captionHeight + gutter

        let image = NSImage(size: NSSize(width: tile, height: tile))
        image.addRepresentation(render(concept, pixels: tile * 2))
        image.draw(in: NSRect(x: x, y: y, width: tile, height: tile))

        label("\(index + 1). \(concept.name)", at: NSPoint(x: x, y: y - 26), size: 15, weight: .medium)
    }

    NSGraphicsContext.restoreGraphicsState()
    try writePNG(sheet, to: outputDirectory.appendingPathComponent("concept-board.png"))
}

// Board 2: the size that actually decides it — the Finder toolbar button.
do {
    let sizes = [16, 18, 24, 32, 64]
    // Rows must clear the tallest tile plus its caption, or the 64pt column
    // walks into the row above and into the column headers.
    let largestSize = sizes.max() ?? 64
    let rowHeight = largestSize + 54
    let leftMargin = 190, topMargin = 116
    let columnWidth = largestSize + 28
    let groupWidth = sizes.count * columnWidth
    let groupGap = 72
    let width = leftMargin + groupWidth + groupGap + groupWidth + 24
    let height = topMargin + concepts.count * rowHeight + 34

    let sheet = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)

    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    label("Legibility at Finder-toolbar size", at: NSPoint(x: 30, y: height - 46),
          size: 24, weight: .semibold)
    label("in colour", at: NSPoint(x: leftMargin, y: height - topMargin + 44), size: 14, weight: .medium)
    label("flattened to one ink", at: NSPoint(x: leftMargin + groupWidth + groupGap,
                                              y: height - topMargin + 44), size: 14, weight: .medium)

    for (index, concept) in concepts.enumerated() {
        let rowBottom = height - topMargin - (index + 1) * rowHeight + 30
        label("\(index + 1). \(concept.name)",
              at: NSPoint(x: 30, y: CGFloat(rowBottom + largestSize / 2) - 8), size: 14)

        for (column, pointSize) in sizes.enumerated() {
            for (group, monochrome) in [(0, false), (1, true)] {
                let offset = leftMargin + group * (groupWidth + groupGap)
                let x = offset + column * columnWidth
                // Sit every tile on one baseline so the sizes read as a ramp.
                let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
                image.addRepresentation(render(concept, pixels: pointSize * 2, monochrome: monochrome))
                image.draw(in: NSRect(x: x, y: rowBottom, width: pointSize, height: pointSize))
                if index == 0 {
                    label("\(pointSize)pt", at: NSPoint(x: x, y: height - topMargin + 18), size: 11,
                          color: NSColor(calibratedWhite: 0.45, alpha: 1))
                }
            }
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    try writePNG(sheet, to: outputDirectory.appendingPathComponent("concept-board-toolbar-size.png"))
}

print("wrote \(concepts.count) concepts and 2 boards to \(outputDirectory.path)")
