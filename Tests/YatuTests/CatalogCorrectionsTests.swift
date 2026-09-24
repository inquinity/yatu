//
//  CatalogCorrectionsTests.swift
//  YatuTests
//
//  The corrections are a small map that is easy to get wrong in ways nothing
//  would notice: a correction that is itself stale, one that shadows an entry
//  upstream has since fixed, or one added for an app whose identifier was only
//  guessed at. These tests are the guardrail on the map, not on the launcher.
//

import XCTest
@testable import YatuKit
import YatuUpstream

final class CatalogCorrectionsTests: XCTestCase {

    func testEveryCorrectionActuallyChangesSomething() {
        // A correction equal to the catalog's own value is dead weight, and
        // signals that upstream has fixed the entry and we should drop ours.
        for (app, corrected) in CatalogCorrections.bundleIdentifiers {
            XCTAssertNotEqual(corrected, app.bundleId,
                              "\(app.name): the catalog now agrees; remove this correction")
        }
    }

    func testCorrectionsLookLikeBundleIdentifiers() {
        for (app, corrected) in CatalogCorrections.bundleIdentifiers {
            XCTAssertFalse(corrected.isEmpty, "\(app.name): empty correction")
            XCTAssertTrue(corrected.contains("."),
                          "\(app.name): '\(corrected)' is not a reverse-DNS identifier")
            XCTAssertFalse(corrected.hasPrefix("/"),
                           "\(app.name): '\(corrected)' is a path, not an identifier")
            XCTAssertEqual(corrected.trimmingCharacters(in: .whitespacesAndNewlines), corrected,
                           "\(app.name): stray whitespace")
        }
    }

    func testCorrectionsOnlyCoverEntriesTheCatalogHas() {
        let known = Set(Role.allCases.flatMap { Catalog.apps(for: $0) })
        for app in CatalogCorrections.bundleIdentifiers.keys {
            XCTAssertTrue(known.contains(app),
                          "\(app.name) is corrected but is not in either role's catalog")
        }
    }

    func testTheLookupPrefersACorrectionAndFallsBackOtherwise() {
        XCTAssertEqual(Catalog.bundleIdentifier(for: .xcode), "com.apple.dt.Xcode")
        XCTAssertEqual(Catalog.bundleIdentifier(for: .warp), "dev.warp.Warp-Stable")
        // Untouched entries pass straight through.
        XCTAssertEqual(Catalog.bundleIdentifier(for: .terminal), SupportedApps.terminal.bundleId)
        XCTAssertEqual(Catalog.bundleIdentifier(for: .iTerm), SupportedApps.iTerm.bundleId)
    }

    func testTheKnownStaleEntriesAreTheOnesWeVerified() {
        // Recorded so a future reader knows what was checked and what was not.
        // com.sublimetext.3 is also suspected stale but was NOT verified — no
        // installed copy to check against — so it is deliberately not corrected.
        XCTAssertEqual(Set(CatalogCorrections.bundleIdentifiers.keys), Set([.xcode, .warp]),
                       "add a verification date in CatalogCorrections.swift before changing this")
    }
}
