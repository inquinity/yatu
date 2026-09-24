//
//  CatalogCorrections.swift
//  YatuKit
//
//  Bundle identifiers the vendored catalog gets wrong.
//
//  `Sources/YatuUpstream/SupportedApps.swift` comes from OpenInTerminal and is
//  compiled unchanged — never edited to make our code work (docs/UPSTREAM.md).
//  Some of its bundle identifiers are stale, so the correction lives here, on
//  our side of that line, and `Catalog.bundleIdentifier(for:)` applies it.
//
//  ## Why this is not cosmetic
//
//  A wrong identifier means `NSWorkspace.urlForApplication(withBundleIdentifier:)`
//  finds nothing, and resolution falls through to rule 2 — an explicit
//  `/Applications/<name>.app`. That happens to work for a default install and
//  fails for anyone who keeps applications in `~/Applications`, where the app
//  is present but silently unavailable.
//
//  ## The bar for adding an entry
//
//  **Verified against the real application, on a Mac where it is installed.**
//  Not inferred, not remembered, not copied from a web page. `bin/check-upstream.sh`
//  reports when upstream's catalog moves; this file records where it is wrong.
//  An entry without a verification date should be treated as a guess and removed.
//

import Foundation
import YatuUpstream

public enum CatalogCorrections {

    /// Verified replacements, keyed by the catalog entry they correct.
    static let bundleIdentifiers: [SupportedApps: String] = [
        // Xcode has not used `com.apple.Xcode` for many years.
        // Verified 2026-09-24 against /Applications/Xcode.app.
        .xcode: "com.apple.dt.Xcode",

        // The catalog says `dev.warp`, which resolves to nothing.
        // Verified 2026-09-24 against /Applications/Warp.app, installed with
        // `brew install --cask warp` for the check and removed afterwards.
        .warp: "dev.warp.Warp-Stable",
    ]
}

public extension Catalog {

    /// The bundle identifier to resolve this entry by: the corrected one where
    /// we have verified a correction, otherwise the catalog's own.
    static func bundleIdentifier(for app: SupportedApps) -> String {
        CatalogCorrections.bundleIdentifiers[app] ?? app.bundleId
    }
}
