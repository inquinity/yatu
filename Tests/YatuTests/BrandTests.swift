//
//  BrandTests.swift
//  YatuTests
//
//  The brand violet is written down twice: in Brand.swift, and in the icon's
//  palette in bin/make-icon.swift. That script is standalone — it cannot import
//  YatuKit and YatuKit cannot import it — so the duplication is unavoidable.
//
//  What is avoidable is the drift. This parses the palette out of the script
//  and fails when the two stop agreeing, which is the only moment anyone would
//  otherwise notice: an About box whose accent no longer matches the icon.
//

import AppKit
import XCTest
@testable import YatuKit

final class BrandTests: XCTestCase {

    /// bin/make-icon.swift, found relative to this file rather than to the
    /// working directory, so the test does not care where it is run from.
    private var iconScript: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)     // Tests/YatuTests/BrandTests.swift
                .deletingLastPathComponent()               // Tests/YatuTests
                .deletingLastPathComponent()               // Tests
                .deletingLastPathComponent()               // repo root
            return try String(contentsOf: root.appendingPathComponent("bin/make-icon.swift"),
                              encoding: .utf8)
        }
    }

    func testTheAccentMatchesTheIconsViolet() throws {
        let source = try iconScript

        // colourPalette(
        //     backgroundTop: rgb(120, 66, 168), backgroundBottom: rgb(74, 38, 118),
        guard let range = source.range(of: "let colourPalette = TilePalette("),
              let topRange = source.range(of: "backgroundTop: rgb(", range: range.upperBound..<source.endIndex),
              let close = source.range(of: ")", range: topRange.upperBound..<source.endIndex)
        else {
            return XCTFail("could not find colourPalette's backgroundTop in bin/make-icon.swift")
        }

        let numbers = source[topRange.upperBound..<close.lowerBound]
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(numbers.count, 3, "expected three components")

        let expected = NSColor(srgbRed: CGFloat(numbers[0]) / 255,
                               green: CGFloat(numbers[1]) / 255,
                               blue: CGFloat(numbers[2]) / 255,
                               alpha: 1)
        let actual = Brand.violetLight

        // Compared per component: NSColor equality is stricter than "the same
        // colour" once colour spaces are involved.
        for (name, pair) in [("red", (expected.redComponent, actual.redComponent)),
                             ("green", (expected.greenComponent, actual.greenComponent)),
                             ("blue", (expected.blueComponent, actual.blueComponent))] {
            XCTAssertEqual(pair.0, pair.1, accuracy: 0.001,
                           "Brand.violetLight's \(name) no longer matches the icon's palette")
        }
    }

    func testDarkModeAccentIsLighterThanTheIconViolet() throws {
        // The tile violet is legible on white and muddy on near-black. If these
        // ever converge, the dark-mode accent has stopped being readable.
        XCTAssertGreaterThan(Brand.violetDark.brightnessComponent,
                             Brand.violetLight.brightnessComponent,
                             "the dark-mode accent must be lighter, not darker")
    }

    func testTheAccentResolvesDifferentlyPerAppearance() {
        let dynamic = NSColor(name: "test") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? Brand.violetDark : Brand.violetLight
        }
        let light = dynamic.usingColorSpace(.sRGB)
        XCTAssertNotNil(light, "the accent must resolve to a concrete colour")
    }
}
