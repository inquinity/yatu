//
//  SupportedAppsDocTests.swift
//  YatuTests
//
//  Settings used to list every supported app, installed or not, and greyed out
//  the ones you could not pick — a dozen unchoosable rows in the one window
//  whose job is choosing. That list moved to the README, and Settings now says
//  how many exist and links there.
//
//  Which makes the README load-bearing. A name the catalog gained and the README
//  did not is now a link that answers the user's question wrongly, and nothing
//  else would notice: bin/check-upstream.sh compares the catalog to upstream's,
//  not to our documentation.
//

import XCTest
@testable import YatuKit

final class SupportedAppsDocTests: XCTestCase {

    private var readme: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()        // Tests/YatuTests
                .deletingLastPathComponent()        // Tests
                .deletingLastPathComponent()        // repo root
            return try String(contentsOf: root.appendingPathComponent("README.md"),
                              encoding: .utf8)
        }
    }

    /// The comma-separated names under a `**Heading (n)**` line, and the count
    /// that line claims.
    private func listed(under heading: String, in readme: String) throws -> (names: [String], claimed: Int) {
        let lines = readme.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let index = lines.firstIndex(where: { $0.hasPrefix("**\(heading) (") }) else {
            throw XCTSkip("README has no '**\(heading) (n)**' line")
        }
        // "**Terminals (14)**" -> 14
        let claimed = Int(lines[index]
            .drop(while: { $0 != "(" }).dropFirst()
            .prefix(while: { $0 != ")" })) ?? -1

        guard let listLine = lines[(index + 1)...].first(where: { !$0.isEmpty }) else {
            throw XCTSkip("nothing follows '\(heading)'")
        }
        return (listLine.components(separatedBy: ", "), claimed)
    }

    func testTheReadmeListsEveryTerminalAndNoOthers() throws {
        let (names, claimed) = try listed(under: "Terminals", in: try readme)
        let catalog = Catalog.apps(for: .terminal).map(\.name)
        XCTAssertEqual(Set(names), Set(catalog),
                       "README's terminal list and the catalog have diverged")
        XCTAssertEqual(claimed, catalog.count, "the count in the README heading is wrong")
    }

    func testTheReadmeListsEveryEditorAndNoOthers() throws {
        let (names, claimed) = try listed(under: "Editors", in: try readme)
        let catalog = Catalog.apps(for: .editor).map(\.name)
        XCTAssertEqual(Set(names), Set(catalog),
                       "README's editor list and the catalog have diverged")
        XCTAssertEqual(claimed, catalog.count, "the count in the README heading is wrong")
    }

    func testTheReadmePreambleTotalMatchesTheCatalog() throws {
        // The preamble states a total for both roles together, written by hand
        // and nowhere derived. Settings quotes no number of its own -- it links
        // here by name -- so this is the only place the total can go stale.
        let total = Catalog.apps(for: .terminal).count + Catalog.apps(for: .editor).count
        XCTAssertTrue(try readme.contains("These are the \(total) Yatu knows how to"),
                      "the README's total is not \(total)")
    }

    /// The link Settings shows has to land on a heading that exists. GitHub
    /// slugs a heading by lowercasing it and hyphenating the spaces.
    func testSettingsLinksToAHeadingThatExists() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/YatuKit/SettingsView.swift"),
                              encoding: .utf8)

        guard let tail = view.components(separatedBy: "yatu#").dropFirst().first else {
            return XCTFail("SettingsView no longer links into the README")
        }
        let anchor = String(tail.prefix { $0 != "\"" && $0 != ")" })

        let headings = try readme.split(separator: "\n")
            .filter { $0.hasPrefix("## ") }
            .map { $0.dropFirst(3).lowercased().replacingOccurrences(of: " ", with: "-") }
        XCTAssertTrue(headings.contains(String(anchor)),
                      "Settings links to #\(anchor), which is not a heading in the README")
    }
}
