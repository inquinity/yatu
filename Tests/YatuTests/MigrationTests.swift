//
//  MigrationTests.swift
//  YatuTests
//
//  The migration reads a preference domain owned by someone else. That is
//  untrusted input, and the tests care most about what it refuses.
//

import XCTest
@testable import YatuKit
import YatuUpstream

final class MigrationTests: XCTestCase {

    private var store: MemoryStore!
    private var settings: Settings!

    override func setUp() {
        store = MemoryStore()
        settings = Settings(store: store)
    }

    /// A stand-in for the old app's domain.
    private func legacy(_ values: [String: String]) -> (String, String) -> String? {
        { domain, key in values["\(domain)/\(key)"] }
    }

    private let terminalDomain = "wang.jianing.app.OpenInTerminal-Lite/LiteDefaultTerminal"
    private let editorDomain = "wang.jianing.app.OpenInEditor-Lite/LiteDefaultEditor"

    // MARK: - What it adopts

    func testAdoptsATerminalChoiceWhenYatuHasNone() {
        let adopted = Migration.adoptLegacyChoices(
            into: settings, read: legacy([terminalDomain: "iTerm"]))
        XCTAssertEqual(adopted[.terminal], .iTerm)
        XCTAssertEqual(settings.chosenApp(for: .terminal), .iTerm)
    }

    func testAdoptsBothRolesIndependently() {
        let adopted = Migration.adoptLegacyChoices(
            into: settings,
            read: legacy([terminalDomain: "Terminal", editorDomain: "Visual Studio Code"]))
        XCTAssertEqual(adopted[.terminal], .terminal)
        XCTAssertEqual(adopted[.editor], .vscode)
    }

    func testTheRealDomainIsWhatTheOldAppActuallyUses() {
        // Recorded from a real installation on 2026-09-24:
        //   $ defaults read wang.jianing.app.OpenInTerminal-Lite
        //   { LiteDefaultTerminal = Terminal; }
        let terminal = Migration.legacyChoices.first { $0.role == .terminal }
        XCTAssertEqual(terminal?.domain, "wang.jianing.app.OpenInTerminal-Lite")
        XCTAssertEqual(terminal?.key, "LiteDefaultTerminal")
    }

    // MARK: - What it refuses

    func testNeverOverwritesAChoiceYatuAlreadyHas() {
        // The rule that makes this safe to run on every launch: a later change
        // by the user must not be undone by an old value lying around.
        settings.setChosenApp(.ghostty, for: .terminal)
        let adopted = Migration.adoptLegacyChoices(
            into: settings, read: legacy([terminalDomain: "iTerm"]))
        XCTAssertTrue(adopted.isEmpty)
        XCTAssertEqual(settings.chosenApp(for: .terminal), .ghostty)
    }

    func testRefusesAValueOutsideTheCatalog() {
        // A foreign domain anyone can write must not choose what Yatu launches.
        let adopted = Migration.adoptLegacyChoices(
            into: settings, read: legacy([terminalDomain: "/bin/sh"]))
        XCTAssertTrue(adopted.isEmpty)
        XCTAssertNil(settings.chosenApp(for: .terminal))
    }

    func testRefusesAnEditorNamedInTheTerminalSlot() {
        let adopted = Migration.adoptLegacyChoices(
            into: settings, read: legacy([terminalDomain: "Emacs"]))
        XCTAssertTrue(adopted.isEmpty)
        XCTAssertNil(settings.chosenApp(for: .terminal))
    }

    func testIgnoresAnEmptyValue() {
        // Upstream's own finding L5: an empty choice ran `open -a ""`.
        let adopted = Migration.adoptLegacyChoices(
            into: settings, read: legacy([terminalDomain: ""]))
        XCTAssertTrue(adopted.isEmpty)
        XCTAssertNil(settings.chosenApp(for: .terminal))
    }

    func testDoesNothingWhenTheOldAppWasNeverUsed() {
        let adopted = Migration.adoptLegacyChoices(into: settings, read: { _, _ in nil })
        XCTAssertTrue(adopted.isEmpty)
        XCTAssertNil(settings.chosenApp(for: .terminal))
        XCTAssertNil(settings.chosenApp(for: .editor))
    }

    func testIsIdempotent() {
        let read = legacy([terminalDomain: "iTerm"])
        XCTAssertEqual(Migration.adoptLegacyChoices(into: settings, read: read)[.terminal], .iTerm)
        // Second run adopts nothing, because Yatu now has its own value.
        XCTAssertTrue(Migration.adoptLegacyChoices(into: settings, read: read).isEmpty)
    }
}
