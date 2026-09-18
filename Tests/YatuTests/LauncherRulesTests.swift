//
//  LauncherRulesTests.swift
//  YatuTests
//

import XCTest
@testable import YatuKit
import YatuUpstream

final class LauncherRulesTests: XCTestCase {

    // MARK: - Rule 5: templates are compiled-in constants

    func testArgumentTemplatesAreFixed() {
        XCTAssertEqual(Launcher.argumentTemplate(for: .alacritty), ["--working-directory"])
        XCTAssertEqual(Launcher.argumentTemplate(for: .wezterm), ["start", "--cwd"])
        XCTAssertEqual(Launcher.argumentTemplate(for: .tabby), ["--directory"])
        XCTAssertEqual(Launcher.argumentTemplate(for: .kitty),
                       ["--single-instance", "--instance-group", "1", "--directory"])
    }

    /// Anything without a template is opened *with* the URL, so no argument
    /// vector is built at all.
    func testAppsWithoutATemplateGetNone() {
        XCTAssertNil(Launcher.argumentTemplate(for: .iTerm))
        XCTAssertNil(Launcher.argumentTemplate(for: .terminal))
        XCTAssertNil(Launcher.argumentTemplate(for: .ghostty))
    }

    /// Nothing a user can write reaches the argument vector: the template is a
    /// function of the catalog case, and the catalog case only.
    func testTemplatesAreIdenticalAcrossCallsAndCarryNoUserInput() {
        for app in SupportedApps.allCases {
            XCTAssertEqual(Launcher.argumentTemplate(for: app), Launcher.argumentTemplate(for: app))
            for token in Launcher.argumentTemplate(for: app) ?? [] {
                XCTAssertTrue(token.hasPrefix("-") || ["start", "1"].contains(token),
                              "unexpected template token '\(token)' for \(app.name)")
            }
        }
    }

    // MARK: - Rules 1 and 2: resolution by bundle id, or an explicit path

    func testTerminalResolvesByBundleIdentifier() {
        // Terminal.app is present on every Mac, so this is safe to assert.
        XCTAssertNotNil(Launcher.applicationURL(for: .terminal))
        XCTAssertEqual(SupportedApps.terminal.bundleId, "com.apple.Terminal")
    }

    func testEntriesWithoutABundleIdAreLookedForAtAnExplicitPath() {
        // GitHub Desktop and Fork ship no bundle id in upstream's catalog.
        XCTAssertTrue(SupportedApps.githubDesktop.bundleId.isEmpty)
        // Absent from /Applications on the test machine, it must resolve to
        // nothing rather than to something else.
        if !FileManager.default.fileExists(atPath: "/Applications/GitHub Desktop.app") {
            XCTAssertNil(Launcher.applicationURL(for: .githubDesktop))
        }
    }

    /// Whatever is or is not installed on the machine running the tests, the
    /// two answers must never disagree — `isInstalled` is what the settings
    /// window will filter the catalog with.
    func testInstalledAgreesWithResolutionForEveryCatalogEntry() {
        for app in SupportedApps.allCases {
            XCTAssertEqual(Launcher.isInstalled(app), Launcher.applicationURL(for: app) != nil,
                           "disagreement for \(app.name)")
        }
    }

    /// An entry that resolves must resolve to an application bundle that is
    /// really there — not to a path assembled from its name.
    func testResolutionOnlyEverYieldsAnExistingBundle() {
        for app in SupportedApps.allCases {
            guard let url = Launcher.applicationURL(for: app) else { continue }
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(app.name) -> \(url.path)")
            XCTAssertEqual(url.pathExtension, "app", "\(app.name) -> \(url.path)")
        }
    }
}

/// An in-memory store, so the suite creates no preferences domain at all.
final class MemoryStore: PreferenceStore {
    private var values: [String: String] = [:]
    func stringValue(forKey key: String) -> String? { values[key] }
    func setStringValue(_ value: String, forKey key: String) { values[key] = value }
    func removeValue(forKey key: String) { values.removeValue(forKey: key) }
}

final class SettingsRulesTests: XCTestCase {

    private var store: MemoryStore!

    override func setUp() {
        store = MemoryStore()
    }

    func testAChoiceRoundTrips() {
        let settings = Settings(store: store)
        XCTAssertTrue(settings.setChosenApp(.iTerm, for: .terminal))
        XCTAssertEqual(settings.chosenApp(for: .terminal), .iTerm)
    }

    /// Finding L1: a tampered preference can only ever mean "no choice".
    func testATamperedValueIsIgnored() {
        store.setStringValue("/Applications/Calculator.app", forKey: Role.terminal.preferenceKey)
        XCTAssertNil(Settings(store: store).chosenApp(for: .terminal))

        store.setStringValue("", forKey: Role.terminal.preferenceKey)
        XCTAssertNil(Settings(store: store).chosenApp(for: .terminal))
    }

    func testAnEditorCannotBeStoredOrReadInTheTerminalSlot() {
        let settings = Settings(store: store)
        XCTAssertFalse(settings.setChosenApp(.xcode, for: .terminal))

        store.setStringValue("Xcode", forKey: Role.terminal.preferenceKey)
        XCTAssertNil(settings.chosenApp(for: .terminal))
    }

    func testTheTwoRolesDoNotShareAKey() {
        let settings = Settings(store: store)
        settings.setChosenApp(.iTerm, for: .terminal)
        settings.setChosenApp(.vscode, for: .editor)
        XCTAssertEqual(settings.chosenApp(for: .terminal), .iTerm)
        XCTAssertEqual(settings.chosenApp(for: .editor), .vscode)
    }

    func testClearingRemovesTheChoice() {
        let settings = Settings(store: store)
        settings.setChosenApp(.iTerm, for: .terminal)
        settings.clearChosenApp(for: .terminal)
        XCTAssertNil(settings.chosenApp(for: .terminal))
    }
}
