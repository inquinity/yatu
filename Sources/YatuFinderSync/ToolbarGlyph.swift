//
//  ToolbarGlyph.swift
//  YatuFinderSync
//
//  The template image the system tints, like Finder's own symbols.
//
//  A hand-drawn glyph has to guess system metrics, weight and optical
//  alignment, and the prototype got all three wrong — small in its box yet
//  heavy in stroke, the opposite of a system symbol. So this uses an SF Symbol
//  and lets the system supply all of it. Yatu's own folder-and-caret mark will
//  replace this as a *custom* symbol (an SVG symbol set compiled by actool),
//  which inherits the same metrics; until that is authored, a stock symbol is
//  correct rather than approximately correct. See plan §9.3, M1b.
//

import AppKit

enum ToolbarGlyph {
    static let image: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "apple.terminal",
                                   accessibilityDescription: "Yatu")?
            .withSymbolConfiguration(configuration)
        else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }
        symbol.isTemplate = true
        return symbol
    }()
}
