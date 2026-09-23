//
//  HandOffTests.swift
//  YatuTests
//
//  The hand-off is a public entry point: any application or web page can invoke
//  `yatu://…`. These tests are mostly about what it *refuses*.
//

import XCTest
@testable import YatuKit
import YatuUpstream

final class HandOffTests: XCTestCase {

    private func parse(_ string: String) -> HandOff.Request? {
        guard let url = URL(string: string) else { return nil }
        return HandOff.request(from: url)
    }

    // MARK: - Round trips

    func testOpenRoundTrips() {
        let request = HandOff.Request.open(role: .terminal, app: nil,
                                           items: [URL(fileURLWithPath: "/tmp/a")],
                                           container: URL(fileURLWithPath: "/tmp"))
        let url = HandOff.url(for: request)
        XCTAssertNotNil(url)
        XCTAssertEqual(HandOff.request(from: url!), request)
    }

    func testSetDefaultRoundTrips() {
        let request = HandOff.Request.setDefault(role: .terminal, app: .iTerm)
        XCTAssertEqual(HandOff.request(from: HandOff.url(for: request)!), request)
    }

    func testSettingsRoundTrips() {
        let request = HandOff.Request.settings(role: .editor)
        XCTAssertEqual(HandOff.request(from: HandOff.url(for: request)!), request)
    }

    func testAPathWithSpacesAndPunctuationSurvives() {
        let awkward = URL(fileURLWithPath: "/tmp/a folder; rm -rf ~/with&chars")
        let url = HandOff.url(for: .open(role: .terminal, app: nil, items: [awkward], container: nil))!
        guard case let .open(_, _, items, _) = HandOff.request(from: url) else {
            return XCTFail("did not parse")
        }
        XCTAssertEqual(items.map(\.path), [awkward.path])
    }

    func testSeveralItemsRoundTrip() {
        // The defect this covers: the contract used to carry one optional URL,
        // so "Send to editor" with three files selected could not express what
        // was asked for and silently sent the folder instead.
        let selected = ["/tmp/one.txt", "/tmp/two.txt", "/tmp/three.txt"]
            .map { URL(fileURLWithPath: $0) }
        let request = HandOff.Request.open(role: .editor, app: .vscode,
                                           items: selected,
                                           container: URL(fileURLWithPath: "/tmp"))
        let url = HandOff.url(for: request)!
        XCTAssertEqual(HandOff.request(from: url), request)

        guard case let .open(_, _, items, _) = HandOff.request(from: url) else {
            return XCTFail("did not parse")
        }
        XCTAssertEqual(items.map(\.path), selected.map(\.path), "order is preserved")
    }

    func testItemsAtTheCapAreAccepted() {
        let items = (0..<HandOff.maximumItems).map { URL(fileURLWithPath: "/tmp/\($0)") }
        let url = HandOff.url(for: .open(role: .editor, app: nil, items: items, container: nil))!
        guard case let .open(_, _, parsed, _) = HandOff.request(from: url) else {
            return XCTFail("the cap itself should be accepted")
        }
        XCTAssertEqual(parsed.count, HandOff.maximumItems)
    }

    func testTooManyItemsAreRefusedRatherThanTruncated() {
        // Refused, not truncated: acting on part of a request is worse than
        // refusing it, and only a sender that is not the extension can get here.
        let query = (0...HandOff.maximumItems)
            .map { "item=/tmp/\($0)" }
            .joined(separator: "&")
        XCTAssertNil(parse("yatu://open?role=editor&" + query))
    }

    // MARK: - What it refuses

    func testWrongSchemeIsRefused() {
        XCTAssertNil(parse("https://open?role=terminal&item=/tmp"))
        XCTAssertNil(parse("file:///tmp"))
    }

    func testUnknownHostIsRefused() {
        XCTAssertNil(parse("yatu://execute?role=terminal&item=/tmp"))
        XCTAssertNil(parse("yatu://?role=terminal&item=/tmp"))
    }

    func testUnknownOrMissingRoleIsRefused() {
        XCTAssertNil(parse("yatu://open?item=/tmp"))
        XCTAssertNil(parse("yatu://open?role=root&item=/tmp"))
        XCTAssertNil(parse("yatu://open?role=&item=/tmp"))
    }

    func testOpenWithNothingToOpenIsRefused() {
        XCTAssertNil(parse("yatu://open?role=terminal"))
    }

    /// Finding L1 at the URL boundary: a crafted URL may not name an arbitrary
    /// application any more than a crafted preference may.
    func testOpenNamingAnAppOutsideTheCatalogIsRefused() {
        XCTAssertNil(parse("yatu://open?role=terminal&app=Calculator&item=/tmp"))
        XCTAssertNil(parse("yatu://open?role=terminal&app=/Applications/Calculator.app&item=/tmp"))
        // An editor is not a terminal, even though both are in the catalog.
        XCTAssertNil(parse("yatu://open?role=terminal&app=Xcode&item=/tmp"))
    }

    func testSetDefaultOutsideTheCatalogIsRefused() {
        XCTAssertNil(parse("yatu://set-default?role=terminal&app=Calculator"))
        XCTAssertNil(parse("yatu://set-default?role=terminal&app=Xcode"))
        XCTAssertNil(parse("yatu://set-default?role=terminal"))
    }

    func testAnAppWithinTheRolesCatalogIsAccepted() {
        XCTAssertEqual(parse("yatu://open?role=terminal&app=iTerm&item=/tmp"),
                       .open(role: .terminal, app: .iTerm,
                             items: [URL(fileURLWithPath: "/tmp")], container: nil))
    }
}

final class MenuModelTests: XCTestCase {

    private let terminals: [(SupportedApps, URL)] = [
        (.terminal, URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")),
        (.iTerm, URL(fileURLWithPath: "/Applications/iTerm.app")),
    ]
    private let editors: [(SupportedApps, URL)] = [
        (.vscode, URL(fileURLWithPath: "/Applications/Visual Studio Code.app")),
    ]

    func testTheMenuNamesWhatItDoes() {
        let items = MenuModel.items(for: .terminal,
                                    installedTerminals: terminals, installedEditors: editors)
        // The wording has to carry what a checkmark would: the extension cannot
        // read the current default, so "Set default…" is the only signal that
        // these items set rather than open.
        XCTAssertEqual(items.first?.title, "Set default terminal program")
        XCTAssertTrue(items.contains { $0.title == "Send to editor" })
        XCTAssertEqual(items.last?.title, "Settings…")
    }

    func testHeadersAndSeparatorsAreNotChoosable() {
        let items = MenuModel.items(for: .terminal,
                                    installedTerminals: terminals, installedEditors: editors)
        for item in items where !item.isEnabled {
            XCTAssertNil(MenuModel.request(for: item, role: .terminal, selection: [], container: nil))
        }
    }

    /// The asymmetry that matters: a terminal item sets the default and opens
    /// nothing; an editor item opens once and changes nothing.
    func testTerminalItemsSetTheDefaultAndEditorItemsOpen() {
        let items = MenuModel.items(for: .terminal,
                                    installedTerminals: terminals, installedEditors: editors)
        let folder = URL(fileURLWithPath: "/tmp/project")

        let terminalItem = items.first { $0.title == "iTerm" }!
        XCTAssertEqual(MenuModel.request(for: terminalItem, role: .terminal,
                                         selection: [folder], container: nil),
                       .setDefault(role: .terminal, app: .iTerm))

        let editorItem = items.first { $0.title == "Visual Studio Code" }!
        XCTAssertEqual(MenuModel.request(for: editorItem, role: .terminal,
                                         selection: [folder], container: nil),
                       .open(role: .editor, app: .vscode, items: [folder], container: nil))
    }

    func testNothingInstalledStillOffersSettings() {
        let items = MenuModel.items(for: .terminal, installedTerminals: [], installedEditors: [])
        XCTAssertEqual(items.map(\.title), ["Settings…"])
    }
}
