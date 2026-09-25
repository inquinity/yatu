//
//  LaunchLifetimeTests.swift
//  YatuTests
//
//  The app must have exactly one NSApplicationDelegate, call NSApplication.run()
//  exactly once, and let exactly one object answer yatu:// URLs.
//
//  These are asserted against the source because there is nowhere else to assert
//  them. Breaking any of the three produces a fault that exists only in a
//  running app, that depends on Apple Event timing, and that presents as a dead
//  menu item — 1.0.1 shipped all three at once and the symptom was "About works,
//  then doesn't, then does". No unit test can reach that; a test that the
//  structure permitting it is absent can.
//
//  The precedent is BrandTests, which parses bin/make-icon.swift for the same
//  reason: the thing worth checking is not reachable from a running test.
//

import XCTest
@testable import YatuKit

final class LaunchLifetimeTests: XCTestCase {

    /// Every Swift file in Sources, by path, found relative to this file so the
    /// test does not care where it is run from.
    private func sources() throws -> [(path: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)      // Tests/YatuTests/…
            .deletingLastPathComponent()                // Tests/YatuTests
            .deletingLastPathComponent()                // Tests
            .deletingLastPathComponent()                // repo root
            .appendingPathComponent("Sources")

        guard let walker = FileManager.default.enumerator(at: root,
                                                         includingPropertiesForKeys: nil)
        else { throw XCTSkip("could not read \(root.path)") }

        var found: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            found.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        XCTAssertFalse(found.isEmpty, "found no sources under \(root.path)")
        return found
    }

    /// Which files contain `needle`, ignoring comments — every rule here is
    /// *described* in a comment somewhere, which would otherwise match.
    private func files(containing needle: String) throws -> [String] {
        try sources().filter { file in
            file.text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") && !$0.hasPrefix("*") }
                .contains { $0.contains(needle) }
        }.map(\.path)
    }

    func testOnlyOneTypeIsTheApplicationDelegate() throws {
        XCTAssertEqual(try files(containing: "NSApplicationDelegate"), ["Yatu.swift"],
                       """
                       Exactly one object may be the app delegate, and it is \
                       LaunchCoordinator. A window that installs its own displaces it, \
                       and the displaced delegate is the one that knows how to route a \
                       yatu:// URL.
                       """)
    }

    func testTheRunLoopIsStartedInExactlyOnePlace() throws {
        XCTAssertEqual(try files(containing: "application.run()"), ["Yatu.swift"],
                       """
                       NSApplication.run() is called once per process. Calling it again \
                       re-enters the run loop and does not re-post \
                       applicationDidFinishLaunching, so a window built there is built \
                       only sometimes.
                       """)
    }

    func testOnlyTheCoordinatorAnswersURLs() throws {
        XCTAssertEqual(try files(containing: "open urls: [URL]"), ["Yatu.swift"],
                       """
                       A second application(_:open:) is worse than none: the window \
                       controllers' copies raised their own window and discarded the \
                       request, so a click for a terminal produced the about box.
                       """)
    }

    func testTheApplicationDelegateIsAssignedInExactlyOnePlace() throws {
        XCTAssertEqual(try files(containing: "application.delegate ="), ["Yatu.swift"],
                       "the delegate is installed once, at launch, and never swapped")
        XCTAssertEqual(try files(containing: "NSApp.delegate ="), [],
                       "the delegate is installed once, at launch, and never swapped")
    }

    /// The window factories must not reach for the shared application: a window
    /// that focuses or terminates the app is deciding something only the
    /// coordinator can know, which is what else is on screen.
    func testWindowFactoriesDoNotTouchTheSharedApplication() throws {
        for factory in ["SettingsWindow.swift", "AboutWindow.swift"] {
            let text = try XCTUnwrap(try sources().first { $0.path == factory }?.text,
                                     "\(factory) is missing")
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") }
                .joined(separator: "\n")
            for forbidden in ["NSApp.", "NSApplication.shared"] where code.contains(forbidden) {
                XCTFail("\(factory) touches \(forbidden); showing and focusing belong to LaunchCoordinator")
            }
        }
    }
}
