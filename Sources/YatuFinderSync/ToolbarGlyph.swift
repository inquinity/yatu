//
//  ToolbarGlyph.swift
//  YatuFinderSync
//
//  The template image the system tints, like Finder's own symbols.
//
//  `yatu.folder.caret` is a custom SF Symbol — a folder with a prompt caret
//  inside it — compiled into this extension's own bundle by bin/build.sh. It
//  derives from Apple's exported `folder` template, so it carries the system's
//  metrics: correct optical size beside Finder's View and Arrange controls,
//  correct stroke weight at every symbol weight, and tinting that follows the
//  toolbar. See bin/make-symbol.swift, and README.md for the licence carve-out.
//
//  This replaced a hand-drawn glyph, which had to guess all three and got them
//  wrong — small in its box yet heavy in stroke — and then a stock
//  `apple.terminal`, which was correct but was not Yatu's mark.
//
//  The extension is sandboxed and can read only its own bundle, which is why
//  the asset catalog is compiled into the .appex rather than into the app.
//

import AppKit

enum ToolbarGlyph {
    /// 18pt matches the system symbols Finder puts either side of us.
    private static let pointSize: CGFloat = 18

    static let image: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let bundle = Bundle(for: YatuFinderSync.self)

        // Fall back rather than ship a blank button: an extension with no
        // toolbar image is indistinguishable from one that failed to load.
        guard let symbol = bundle.image(forResource: "yatu.folder.caret")
            ?? NSImage(systemSymbolName: "folder", accessibilityDescription: "Yatu")
        else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }

        let configured = symbol.withSymbolConfiguration(configuration) ?? symbol
        configured.isTemplate = true
        return configured
    }()
}
