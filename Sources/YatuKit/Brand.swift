//
//  Brand.swift
//  YatuKit
//
//  The one colour Yatu owns.
//
//  ## Why these numbers appear twice
//
//  The icon's palette lives in `bin/make-icon.swift`, which is a standalone
//  script rather than part of this package — it cannot import YatuKit, and
//  YatuKit cannot import it. So the value is written down in both places, which
//  is exactly the kind of duplication that drifts silently.
//
//  `BrandTests` closes that: it parses the palette out of bin/make-icon.swift
//  and fails if these stop agreeing. The duplication stays, the drift does not.
//

import AppKit
import SwiftUI

public enum Brand {

    /// The top of the app icon's violet gradient, which is the value the eye
    /// reads as "Yatu". The bottom of that gradient, rgb(74, 38, 118), is too
    /// dark to use as a foreground colour.
    static let violetLight = NSColor(srgbRed: 120 / 255, green: 66 / 255, blue: 168 / 255, alpha: 1)

    /// Lifted for dark mode. The tile violet is legible against white and muddy
    /// against near-black, and an accent that cannot be read is not an accent.
    static let violetDark = NSColor(srgbRed: 178 / 255, green: 136 / 255, blue: 226 / 255, alpha: 1)

    /// The accent as an NSColor, resolved against whichever appearance is
    /// current. AppKit drawing needs this rather than the SwiftUI wrapper.
    static let violetResolved = NSColor(name: "YatuViolet") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? violetDark : violetLight
    }

    /// The accent, for SwiftUI.
    public static let violet = Color(nsColor: violetResolved)
}
