//
//  AboutView.swift
//  YatuKit
//
//  The About box.
//
//  The icon carries the brand and the violet is on the name. That is bolder
//  than most Mac about panels, which leave the name in the label colour — but
//  the name is the one piece of text here that is Yatu rather than about Yatu,
//  so it is the piece worth colouring. The URL stays an ordinary link, because
//  a link that is not link-coloured is a link people do not click.
//
//  Built plain first and branded second, deliberately: the menu path is where
//  this app's real bugs have lived, and an item that draws correctly and does
//  nothing looks exactly like one that works. The click, the window and the
//  dismiss were proven before any of this was added.
//

import AppKit
import SwiftUI

struct AboutView: View {

    /// Called when OK is pressed. The window controller owns what that means.
    let dismiss: () -> Void

    private var repositoryURL: URL { URL(string: "https://github.com/inquinity/yatu")! }

    /// The real app icon when running from a bundle. Outside one — a unit test,
    /// or the executable straight out of .build — this is the generic
    /// application icon, which is the right thing to show rather than nothing.
    private var icon: NSImage { NSApp.applicationIconImage ?? NSImage() }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)      // the name below says it

            StrokedText(Role.terminal.displayName,
                        size: 30, weight: .semibold,
                        fill: Brand.violetResolved, stroke: .white,
                        strokeWidth: 6)

            Link(repositoryURL.absoluteString, destination: repositoryURL)
                .font(.callout)

            VStack(spacing: 2) {
                Text("Version \(Version.short)")
                Text("Build \(Version.build)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("OK", action: dismiss)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
        .padding(.vertical, 26)
        .frame(minWidth: 320)
    }
}

/// Text drawn with an outline outside the letterform.
///
/// SwiftUI has no text stroke. The obvious AppKit spelling — a NEGATIVE
/// `.strokeWidth`, meaning fill *and* stroke — is wrong here: that stroke is
/// centred on the glyph path, so half of it lands INSIDE the letter and eats
/// the fill. At 9% the purple was visibly being chewed away.
///
/// Drawing it twice fixes that. Stroke-only underneath, fill on top: the fill
/// covers the inner half, only the outer half shows, and the letterform keeps
/// its full weight. The width is a percentage of the point size, so the band
/// stays proportional if the type size changes.
///
/// A second, outer band was tried — black, then the icon's deep violet — and
/// dropped. Three concentric bands on 30pt type read as a sticker rather than
/// as a name.
private struct StrokedText: NSViewRepresentable {

    let string: String
    let size: CGFloat
    let weight: NSFont.Weight
    let fill: NSColor
    let stroke: NSColor
    /// Band width as a percentage of the point size. Half of it is visible,
    /// the fill covering the rest.
    let strokeWidth: CGFloat

    init(_ string: String, size: CGFloat, weight: NSFont.Weight,
         fill: NSColor, stroke: NSColor, strokeWidth: CGFloat) {
        self.string = string
        self.size = size
        self.weight = weight
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
    }

    func makeNSView(context: Context) -> StrokedLabel {
        StrokedLabel()
    }

    func updateNSView(_ view: StrokedLabel, context: Context) {
        view.configure(string: string,
                       font: NSFont.systemFont(ofSize: size, weight: weight),
                       fill: fill, stroke: stroke, strokeWidth: strokeWidth)
    }
}

/// The two-pass draw. A view rather than an NSTextField because a text field
/// draws its string once, and this needs it drawn twice.
private final class StrokedLabel: NSView {

    private var string = ""
    private var font = NSFont.systemFont(ofSize: 30)
    private var fill = NSColor.labelColor
    private var stroke = NSColor.white
    private var strokeWidth: CGFloat = 6

    func configure(string: String, font: NSFont,
                   fill: NSColor, stroke: NSColor, strokeWidth: CGFloat) {
        self.string = string
        self.font = font
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        // Measured with the stroke applied: the band makes the text wider than
        // the fill alone, and a size taken without it clips the edges.
        let size = NSAttributedString(string: string, attributes: [
            .font: font, .strokeWidth: strokeWidth,
        ]).size()
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !string.isEmpty else { return }
        // Centred in the view's own bounds rather than drawn at its origin.
        // SwiftUI sizes this view to the column, which the URL below makes
        // wider than the name -- drawing at the origin left-aligned it while
        // everything around it was centred.
        let measured = NSAttributedString(string: string, attributes: [
            .font: font, .strokeWidth: strokeWidth,
        ]).size()
        let origin = NSPoint(x: (bounds.width - measured.width) / 2,
                             y: (bounds.height - measured.height) / 2)
        NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: NSColor.clear,
            .strokeColor: stroke,
            .strokeWidth: strokeWidth,
        ]).draw(at: origin)
        NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: fill,
        ]).draw(at: origin)
    }
}
