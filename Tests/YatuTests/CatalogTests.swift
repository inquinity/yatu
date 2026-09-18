//
//  CatalogTests.swift
//  YatuTests
//
//  M1 scope: prove the compile set works (upstream's catalog is reachable and
//  filtered correctly) and that identity literals are what the build stamps.
//  The launcher rules get their own tests in M2d.
//

import XCTest
@testable import YatuKit
import YatuUpstream

final class CatalogTests: XCTestCase {

    func testEachRoleOffersOnlyItsOwnAppType() {
        for role in Role.allCases {
            let apps = Catalog.apps(for: role)
            XCTAssertFalse(apps.isEmpty, "\(role) has an empty catalog")
            for app in apps {
                XCTAssertEqual(app.type, role.appType,
                               "\(app.name) is offered for \(role) but is a \(app.type)")
            }
        }
    }

    func testTerminalAndEditorCatalogsDoNotOverlap() {
        let terminals = Set(Catalog.apps(for: .terminal).map(\.name))
        let editors = Set(Catalog.apps(for: .editor).map(\.name))
        XCTAssertTrue(terminals.isDisjoint(with: editors))
    }

    func testCatalogLookupIsCaseInsensitive() {
        XCTAssertEqual(Catalog.app(named: "terminal", for: .terminal), .terminal)
        XCTAssertEqual(Catalog.app(named: "TERMINAL", for: .terminal), .terminal)
    }

    /// Finding L1: a preference value is a name from the catalog, never a path
    /// and never an app of the other role.
    func testLookupRejectsAnythingOutsideTheRolesCatalog() {
        XCTAssertNil(Catalog.app(named: "/Applications/Calculator.app", for: .terminal))
        XCTAssertNil(Catalog.app(named: "", for: .terminal))
        XCTAssertNil(Catalog.app(named: "Calculator", for: .terminal))
        // An editor must not resolve in the terminal's slot, or vice versa.
        XCTAssertNil(Catalog.app(named: "Xcode", for: .terminal))
        XCTAssertNil(Catalog.app(named: "iTerm", for: .editor))
    }

    func testRoleIdentityLiterals() {
        XCTAssertEqual(Role.terminal.bundleIdentifier, "com.altmansoftwaredesign.yatu")
        XCTAssertEqual(Role.editor.bundleIdentifier, "com.altmansoftwaredesign.yatu.editor")
        XCTAssertEqual(Role.terminal.displayName, "Yatu")
        XCTAssertEqual(Role.editor.displayName, "Yatu Edit")
    }
}
