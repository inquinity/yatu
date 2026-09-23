//
//  CatalogRoundTripTests.swift
//  YatuTests
//
//  A menu item that does nothing when clicked has more than one cause. The
//  wiring was one (see MenuBuilderTests); the other is a name that does not
//  survive the trip.
//
//  Every menu item carries an app's name into a `yatu://` URL, and the app
//  resolves that name back through `Catalog`, which is an allowlist. If any
//  catalog entry's name fails to round-trip — an entry whose `name` differs
//  from what `SupportedApps.from(name:)` matches, a duplicate, a name that
//  percent-encodes badly — that item silently does nothing, and it would do so
//  only for the one app nobody tested.
//
//  The catalog is upstream's and changes without us (docs/UPSTREAM.md), so this
//  sweeps all of it rather than sampling. It is the test that turns "upstream
//  added a terminal" from a silent failure into a red build.
//

import XCTest
@testable import YatuKit
import YatuUpstream

final class CatalogRoundTripTests: XCTestCase {

    func testEveryCatalogEntryResolvesBackToItself() {
        for role in Role.allCases {
            for app in Catalog.apps(for: role) {
                XCTAssertEqual(Catalog.app(named: app.name, for: role), app,
                               "\(app.name) does not resolve back to itself in the \(role.rawValue) catalog")
            }
        }
    }

    func testEveryCatalogEntrySurvivesAUrlRoundTrip() {
        for role in Role.allCases {
            for app in Catalog.apps(for: role) {
                // "Send to editor → X", the shape that was broken in shipping
                // code for a different reason.
                let open = HandOff.Request.open(role: role, app: app,
                                                items: [URL(fileURLWithPath: "/tmp/file.txt")],
                                                container: URL(fileURLWithPath: "/tmp"))
                guard let url = HandOff.url(for: open) else {
                    return XCTFail("no URL for \(app.name)")
                }
                XCTAssertEqual(HandOff.request(from: url), open,
                               "\(app.name) does not survive the URL round trip")

                // "Set default → X".
                let setDefault = HandOff.Request.setDefault(role: role, app: app)
                guard let defaultURL = HandOff.url(for: setDefault) else {
                    return XCTFail("no URL for \(app.name)")
                }
                XCTAssertEqual(HandOff.request(from: defaultURL), setDefault,
                               "\(app.name) does not survive the URL round trip")
            }
        }
    }

    func testCatalogNamesAreUniqueWithinARole() {
        // Two entries sharing a name would make one of them unreachable: the
        // allowlist resolves a name to the first match, so the other's menu
        // item would quietly act as the first.
        for role in Role.allCases {
            let names = Catalog.apps(for: role).map { $0.name.lowercased() }
            XCTAssertEqual(Set(names).count, names.count,
                           "duplicate name in the \(role.rawValue) catalog")
        }
    }

    func testTheRolesDoNotOverlap() {
        // An app in both catalogs could be set as a terminal default from the
        // editor half of the menu, which is the confusion the allowlist exists
        // to prevent.
        let terminals = Set(Catalog.apps(for: .terminal))
        let editors = Set(Catalog.apps(for: .editor))
        XCTAssertTrue(terminals.isDisjoint(with: editors))
    }

    func testEveryMenuItemForAFullyInstalledMachineProducesARequest() {
        // The worst case: everything upstream knows about is installed. Every
        // item the menu offers must lead to a request.
        let terminals = Catalog.apps(for: .terminal)
            .map { ($0, URL(fileURLWithPath: "/Applications/\($0.name).app")) }
        let editors = Catalog.apps(for: .editor)
            .map { ($0, URL(fileURLWithPath: "/Applications/\($0.name).app")) }

        for role in Role.allCases {
            let items = MenuModel.items(for: role,
                                        installedTerminals: terminals,
                                        installedEditors: editors)
            for item in items {
                switch item.kind {
                case .header, .separator:
                    XCTAssertNil(MenuModel.request(for: item, role: role,
                                                   selection: [], container: nil))
                default:
                    let request = MenuModel.request(for: item, role: role, selection: [],
                                                    container: URL(fileURLWithPath: "/tmp"))
                    XCTAssertNotNil(request, "'\(item.title)' produces no request")
                    // And it must survive the wire, or the click is lost there.
                    if let request, let url = HandOff.url(for: request) {
                        XCTAssertEqual(HandOff.request(from: url), request,
                                       "'\(item.title)' does not survive the URL round trip")
                    } else {
                        XCTFail("'\(item.title)' produced no URL")
                    }
                }
            }
        }
    }
}
