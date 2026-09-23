#!/usr/bin/env swift
//
//  make-symbol.swift
//  Generate Yatu's custom SF Symbol: a folder with a prompt caret inside it.
//
//  The mark is the one chosen 2026-09-21 (plan §8.6) — Yatu opens a terminal
//  *at a folder*, and nothing else in a Finder toolbar is a folder. This is the
//  toolbar half of it; `bin/make-icon.swift` draws the app icon.
//
//  ## Why this is generated rather than drawn
//
//  A Finder Sync extension's toolbar image should be a template image with the
//  system's own metrics: correct optical size next to Finder's View and Arrange
//  controls, correct stroke weight at every symbol weight, and tinting that
//  follows the toolbar. A hand-drawn glyph has to guess all three, and the
//  prototype's did — small in its box yet heavy in stroke.
//
//  So the caret is placed into Apple's *exported* `folder` template, which
//  carries the canvas, the capline and baseline, the per-weight left and right
//  margins, and the folder itself at Ultralight, Regular and Black. Everything
//  this script decides is measured off that template rather than assumed:
//
//    * the pen width, read off the folder's own wall by rasterising it
//    * the interior void, found as the largest empty rectangle inside the
//      outline, which is where a caret can go without touching a wall
//
//  The caret is a stroked polyline converted to a filled outline, because
//  symbol templates carry fills and never strokes. It is injected into the
//  folder's own layer class, so the result stays a single-layer monochrome
//  symbol — what a template image wants to be.
//
//  ## The input is not in this repository
//
//  `folder.svg` is Apple's artwork, exported from SF Symbols.app, and is not
//  redistributed here. To regenerate:
//
//    1. Install SF Symbols (`brew install --cask sf-symbols`).
//    2. Search `folder`, select the plain folder, File > Export Template,
//       choose Static, and save it somewhere.
//    3. bin/make-symbol.swift <that file> <output.svg>
//
//  See docs/BUILDING.md. The generated symbol IS redistributed, and is governed
//  by Apple's SF Symbols licence rather than Yatu's MIT licence; the carve-out
//  is stated in README.md and docs/UPSTREAM.md.
//
//  Usage: bin/make-symbol.swift <folder-template.svg> <output.svg>
//
//  Tunables, as environment variables, so a change of mind costs one run:
//    CARET_HEIGHT  caret span as a fraction of the interior height (0.72)
//    CARET_WIDTH   caret width as a fraction of its own height     (0.62)
//    CARET_DX      nudge within the interior, in template units    (0)
//    CARET_DY      ditto, vertically                               (0)
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - Tunables

func tunable(_ name: String, _ fallback: CGFloat) -> CGFloat {
    guard let raw = ProcessInfo.processInfo.environment[name],
          let value = Double(raw) else { return fallback }
    return CGFloat(value)
}

/// 0.60 is timid at Regular; 0.84 merges into the walls at Black. 0.72 is
/// present at Regular and still clear of the walls at Black.
let heightFraction = tunable("CARET_HEIGHT", 0.72)
let widthRatio     = tunable("CARET_WIDTH", 0.62)
let offsetX        = tunable("CARET_DX", 0)
let offsetY        = tunable("CARET_DY", 0)

/// A static template carries these three; the system interpolates the rest.
let weights = ["Ultralight-S", "Regular-S", "Black-S"]

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - SVG paths

/// Parse the absolute M/L/C/Z subset Apple's symbol templates emit.
func parsePath(_ d: String) -> CGMutablePath {
    let path = CGMutablePath()
    var start = CGPoint.zero
    var command: Character = "M"
    var numbers: [CGFloat] = []

    func flush() {
        guard !numbers.isEmpty || command == "Z" || command == "z" else { return }
        switch command {
        case "M":
            var i = 0
            while i + 1 < numbers.count {
                let point = CGPoint(x: numbers[i], y: numbers[i + 1])
                if i == 0 { path.move(to: point); start = point } else { path.addLine(to: point) }
                i += 2
            }
        case "L":
            var i = 0
            while i + 1 < numbers.count {
                path.addLine(to: CGPoint(x: numbers[i], y: numbers[i + 1])); i += 2
            }
        case "C":
            var i = 0
            while i + 5 < numbers.count {
                path.addCurve(to: CGPoint(x: numbers[i + 4], y: numbers[i + 5]),
                              control1: CGPoint(x: numbers[i], y: numbers[i + 1]),
                              control2: CGPoint(x: numbers[i + 2], y: numbers[i + 3]))
                i += 6
            }
        case "Z", "z":
            path.closeSubpath()
            path.move(to: start)
        default:
            die("unsupported path command '\(command)' in the template")
        }
        numbers.removeAll()
    }

    var token = ""
    func takeNumber() {
        guard !token.isEmpty else { return }
        guard let value = Double(token) else { die("not a number: '\(token)'") }
        numbers.append(CGFloat(value))
        token = ""
    }

    for character in d {
        if character.isLetter {
            takeNumber(); flush(); command = character
        } else if character == "-" && !token.isEmpty && token.last != "e" && token.last != "E" {
            // A minus with digits behind it starts the next number: "10-5".
            takeNumber(); token = "-"
        } else if character == "," || character == " " {
            takeNumber()
        } else {
            token.append(character)
        }
    }
    takeNumber(); flush()
    return path
}

/// SVG `d` for a CGPath, absolute commands only.
func svgData(_ path: CGPath) -> String {
    var out = ""
    func number(_ value: CGFloat) -> String {
        let rounded = (value * 10000).rounded() / 10000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
    }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:    out += "M\(number(points[0].x)) \(number(points[0].y))"
        case .addLineToPoint: out += "L\(number(points[0].x)) \(number(points[0].y))"
        case .addQuadCurveToPoint:
            out += "Q\(number(points[0].x)) \(number(points[0].y))"
            out += " \(number(points[1].x)) \(number(points[1].y))"
        case .addCurveToPoint:
            out += "C\(number(points[0].x)) \(number(points[0].y))"
            out += " \(number(points[1].x)) \(number(points[1].y))"
            out += " \(number(points[2].x)) \(number(points[2].y))"
        case .closeSubpath:   out += "Z"
        @unknown default:     break
        }
    }
    return out
}

// MARK: - Reading the template

struct SymbolTemplate {
    let source: String

    init(contentsOf path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            die("cannot read \(path)")
        }
        guard text.contains("<g id=\"Symbols\">") else {
            die("\(path) is not an SF Symbols template (no Symbols group)")
        }
        source = text
    }

    /// The `<g id="<weight>">…</g>` block for one weight.
    func group(_ weight: String) -> Substring {
        guard let symbols = source.range(of: "<g id=\"Symbols\">") else { die("no Symbols group") }
        let tail = source[symbols.lowerBound...]
        guard let start = tail.range(of: "<g id=\"\(weight)\"") else {
            die("template has no \(weight) box — export a Static template")
        }
        let body = tail[start.lowerBound...]
        guard let end = body.range(of: "\n  </g>") else { die("\(weight) box is not closed") }
        return body[..<end.upperBound]
    }

    /// Every `<path …/>` in that weight, as (class, d).
    func paths(_ weight: String) -> [(cls: String, d: String)] {
        var result: [(String, String)] = []
        var rest = group(weight)
        while let open = rest.range(of: "<path") {
            rest = rest[open.upperBound...]
            guard let close = rest.range(of: "/>") else { break }
            let element = rest[..<close.lowerBound]
            defer { rest = rest[close.upperBound...] }
            // ' d="' with the leading space on purpose: `id="…"` ends in `d="`.
            guard let dRange = element.range(of: " d=\"") else { continue }
            let afterD = element[dRange.upperBound...]
            guard let dEnd = afterD.range(of: "\"") else { continue }
            var cls = ""
            if let cRange = element.range(of: "class=\"") {
                let afterClass = element[cRange.upperBound...]
                if let classEnd = afterClass.range(of: "\"") {
                    cls = String(afterClass[..<classEnd.lowerBound])
                }
            }
            result.append((cls, String(afterD[..<dEnd.lowerBound])))
        }
        return result
    }
}

// MARK: - Measuring a drawn shape

struct Measurement {
    let bounds: CGRect
    /// The pen the shape was drawn with, in template units.
    let penWidth: CGFloat
    /// The largest empty rectangle enclosed by the shape.
    let interior: CGRect
}

func measure(_ path: CGPath, samplesPerUnit: CGFloat = 8) -> Measurement {
    let box = path.boundingBox
    let width = Int((box.width * samplesPerUnit).rounded(.up)) + 2
    let height = Int((box.height * samplesPerUnit).rounded(.up)) + 2
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        die("could not allocate a \(width)×\(height) raster")
    }
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // Symbol space is y-down and a CGContext is y-up: flip, or every vertical
    // measurement comes back mirrored.
    context.translateBy(x: 1 - box.minX * samplesPerUnit,
                        y: CGFloat(height) - 1 + box.minY * samplesPerUnit)
    context.scaleBy(x: samplesPerUnit, y: -samplesPerUnit)
    context.setFillColor(gray: 1, alpha: 1)
    context.addPath(path)
    context.fillPath()

    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height)
    func ink(_ x: Int, _ y: Int) -> Bool { pixels[y * width + x] > 127 }

    // Pen width: the narrowest ink run entering from the left, sampled at three
    // heights. One sample is not enough — a plus read at mid height returns its
    // whole width, because the horizontal bar spans it.
    var pen = Int.max
    for fraction in [0.25, 0.5, 0.75] {
        let row = Int(Double(height) * fraction)
        var run = 0, x = 0
        while x < width && !ink(x, row) { x += 1 }
        while x < width && ink(x, row) { run += 1; x += 1 }
        if run > 0 { pen = min(pen, run) }
    }
    if pen == Int.max { pen = 0 }

    // Largest empty rectangle, by the usual histogram sweep. Only rectangles
    // that touch no raster edge count, so the space outside the folder loses.
    var heights = [Int](repeating: 0, count: width)
    var best = (area: 0, x0: 0, y0: 0, x1: 0, y1: 0)
    for y in 0..<height {
        for x in 0..<width { heights[x] = ink(x, y) ? 0 : heights[x] + 1 }
        var stack: [(start: Int, height: Int)] = []
        for x in 0...width {
            let current = x == width ? 0 : heights[x]
            var start = x
            while let top = stack.last, top.height >= current {
                stack.removeLast()
                let y0 = y - top.height + 1
                let enclosed = top.start > 0 && x < width && y0 > 0 && y < height - 1
                let area = top.height * (x - top.start)
                if enclosed && area > best.area { best = (area, top.start, y0, x, y) }
                start = top.start
            }
            if current > 0 { stack.append((start, current)) }
        }
    }
    func unit(_ pixel: Int, _ origin: CGFloat) -> CGFloat {
        (CGFloat(pixel) - 1) / samplesPerUnit + origin
    }
    let interior = CGRect(x: unit(best.x0, box.minX), y: unit(best.y0, box.minY),
                          width: CGFloat(best.x1 - best.x0) / samplesPerUnit,
                          height: CGFloat(best.y1 - best.y0) / samplesPerUnit)
    return Measurement(bounds: box, penWidth: CGFloat(pen) / samplesPerUnit, interior: interior)
}

// MARK: - The caret

/// A chevron drawn as a stroked polyline, converted to a filled outline.
func caret(center: CGPoint, halfHeight: CGFloat, halfWidth: CGFloat, pen: CGFloat) -> CGPath {
    let line = CGMutablePath()
    line.move(to: CGPoint(x: center.x - halfWidth, y: center.y - halfHeight))
    line.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y))
    line.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y + halfHeight))
    return line.copy(strokingWithWidth: pen, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("""
    Usage: \(URL(fileURLWithPath: arguments[0]).lastPathComponent) <folder-template.svg> <output.svg>

    Export the template first: SF Symbols > search `folder` > select the plain
    folder > File > Export Template > Static. See docs/BUILDING.md.
    """)
    exit(arguments.count == 2 && (arguments[1] == "-h" || arguments[1] == "--help") ? 0 : 2)
}

let template = SymbolTemplate(contentsOf: arguments[1])
var result = template.source

for weight in weights {
    let elements = template.paths(weight)
    guard let folder = elements.first else { die("\(weight) has no path") }
    let shape = measure(parsePath(folder.d))
    guard shape.interior.width > 0, shape.penWidth > 0 else {
        die("could not measure the folder in \(weight)")
    }

    let halfHeight = shape.interior.height * heightFraction / 2
    let mark = caret(center: CGPoint(x: shape.interior.midX + offsetX,
                                     y: shape.interior.midY + offsetY),
                     halfHeight: halfHeight,
                     halfWidth: halfHeight * widthRatio,
                     pen: shape.penWidth)

    // Same layer class as the folder: one layer, monochrome, which is what a
    // template image wants to be.
    guard let end = result.range(of: "\n  </g>",
                                 range: result.range(of: "<g id=\"\(weight)\"")!.lowerBound..<result.endIndex)
    else { die("\(weight) box is not closed") }
    result.insert(contentsOf: "\n   <path class=\"\(folder.cls)\" d=\"\(svgData(mark))\"/>",
                  at: end.lowerBound)

    print(String(format: "%-14@ pen %5.2f   caret %5.2f × %-5.2f   interior %.2f × %.2f",
                 weight as NSString, shape.penWidth,
                 halfHeight * 2 * widthRatio, halfHeight * 2,
                 shape.interior.width, shape.interior.height))
}

// Provenance travels with the file: it is redistributed, and it is not ours
// to relicense. See README.md and docs/UPSTREAM.md.
let provenance = """
<!--
  yatu.folder.caret — Yatu's toolbar symbol.

  DERIVED FROM APPLE'S `folder` SF SYMBOL. The canvas, guides, margins and the
  folder outline at each weight are Apple's, exported from SF Symbols.app; the
  caret inside the folder is Yatu's, generated by bin/make-symbol.swift.

  This file is therefore governed by Apple's SF Symbols licence, NOT by the MIT
  licence that covers the rest of Yatu. It is shipped inside a macOS app, which
  is what SF Symbols are licensed for. Do not relicense it, and do not reuse it
  outside an Apple platform.
-->
"""
if let declarationEnd = result.range(of: "?>") {
    result.insert(contentsOf: "\n" + provenance, at: declarationEnd.upperBound)
}

do {
    try result.write(toFile: arguments[2], atomically: true, encoding: .utf8)
} catch {
    die("could not write \(arguments[2]): \(error.localizedDescription)")
}
print("wrote \(arguments[2])")
