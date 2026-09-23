//
//  MenuBuilderTests.swift
//  YatuTests
//
//  These exist because of a bug that shipped, was reported verified, and did
//  nothing wrong that could be seen: every item in the option-click menu drew
//  correctly, enabled, and did nothing at all when clicked. The menu crosses a
//  process boundary into Finder, and the item carried a `target` and a
//  `representedObject` that cannot cross it.
//
//  None of that is visible in a screenshot, and no test touched it — the
//  extension is an executable target, so nothing could import it. The wiring
//  now lives in `MenuBuilder`, and the invariants it has to hold are asserted
//  rather than described in a comment.
//

import AppKit
import XCTest
@testable import YatuKit
import YatuUpstream

final class MenuBuilderTests: XCTestCase {

    @objc private func stubAction(_ sender: Any?) {}

    private var action: Selector { #selector(stubAction(_:)) }

    /// `MenuModel` wants each installed app paired with where it is; the path
    /// is only used for an icon, so a plausible one is enough here.
    private func installed(_ apps: [SupportedApps]) -> [(SupportedApps, URL)] {
        apps.map { ($0, URL(fileURLWithPath: "/Applications/\($0.name).app")) }
    }

    private func build(terminals: [SupportedApps] = [.iTerm, .ghostty],
                       editors: [SupportedApps] = [.vscode, .emacs],
                       role: Role = .terminal) -> MenuBuilder.Built {
        MenuBuilder.build(items: MenuModel.items(for: role,
                                                 installedTerminals: installed(terminals),
                                                 installedEditors: installed(editors)),
                          action: action)
    }

    // MARK: - The two that broke

    func testNoActionableItemCarriesATarget() {
        // The bug. A target points into this process; Finder draws the menu in
        // its own, so the action is never delivered and the click is silently
        // dropped. Nil target means the responder chain, which is how
        // FIFinderSync gets it back to us.
        //
        // `built` is bound to a local on purpose. NSMenuItem.target is a WEAK
        // reference, so iterating `build().menu.items` directly lets the menu
        // deallocate inside the expression, every target reads back nil, and
        // this test passes whatever the builder does. It was written that way
        // first, and a mutation that set a target did not fail it.
        let built = build()
        let actionable = built.menu.items.filter { $0.action != nil }
        XCTAssertFalse(actionable.isEmpty, "the fixture should produce actionable items")
        for item in actionable {
            XCTAssertNil(item.target,
                         "'\(item.title)' has a target, which cannot cross into Finder")
        }
        withExtendedLifetime(built) {}
    }

    func testNoItemCarriesARepresentedObject() {
        // The second fault, which was waiting behind the first: a custom class
        // in representedObject is not decodable by Finder, so even a delivered
        // action would have found nothing.
        let built = build()
        for item in built.menu.items {
            XCTAssertNil(item.representedObject,
                         "'\(item.title)' carries an object that cannot cross into Finder")
        }
        withExtendedLifetime(built) {}
    }

    // MARK: - The tag contract

    func testEveryActionableItemsTagIndexesItsDescriptor() {
        let built = build()
        let actionable = built.menu.items.filter { $0.action != nil }
        XCTAssertEqual(actionable.count, built.actionable.count)
        for item in actionable {
            XCTAssertTrue(built.actionable.indices.contains(item.tag),
                          "'\(item.title)' has tag \(item.tag), out of range")
            XCTAssertEqual(item.title, built.actionable[item.tag].title,
                           "tag \(item.tag) points at the wrong descriptor")
        }
    }

    func testTagsAreUniqueAndContiguousFromZero() {
        let built = build()
        let tags = built.menu.items.filter { $0.action != nil }.map(\.tag)
        XCTAssertFalse(tags.isEmpty, "the fixture should produce actionable items")
        XCTAssertEqual(tags.sorted(), Array(0..<tags.count))
    }

    func testHeadersAndSeparatorsAreNotActionable() {
        let built = build()
        for item in built.menu.items where item.action == nil {
            XCTAssertFalse(item.isEnabled && !item.isSeparatorItem && item.action != nil)
        }
        // Nothing that cannot be chosen may occupy a tag slot.
        XCTAssertFalse(built.actionable.contains { descriptor in
            if case .header = descriptor.kind { return true }
            if case .separator = descriptor.kind { return true }
            return false
        })
    }

    func testHeadersAreDisabledAndAutoenablingIsOff() {
        let built = build()
        XCTAssertFalse(built.menu.autoenablesItems,
                       "Finder does not run our validation; enablement must be stated")
        let headers = built.menu.items.filter { $0.action == nil && !$0.isSeparatorItem }
        XCTAssertFalse(headers.isEmpty, "the fixture should produce headers")
        for header in headers {
            XCTAssertFalse(header.isEnabled, "'\(header.title)' should not be selectable")
        }
    }

    // MARK: - Every item leads somewhere

    func testEveryActionableItemProducesARequest() {
        // A menu item that cannot become a request is one that does nothing
        // when clicked — the same symptom, from a different cause.
        let built = build()
        for descriptor in built.actionable {
            XCTAssertNotNil(
                MenuModel.request(for: descriptor, role: .terminal,
                                  selection: [], container: URL(fileURLWithPath: "/tmp")),
                "'\(descriptor.title)' is clickable but produces no request")
        }
    }

    func testAnEmptyCatalogStillOffersSettings() {
        // Nothing installed is not an error: the menu must still be usable.
        let built = MenuBuilder.build(
            items: MenuModel.items(for: .terminal, installedTerminals: [], installedEditors: []),
            action: action)
        XCTAssertEqual(built.actionable.count, 1)
        XCTAssertTrue(built.menu.items.contains { $0.action != nil })
    }
}
