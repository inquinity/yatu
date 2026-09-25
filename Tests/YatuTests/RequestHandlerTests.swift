//
//  RequestHandlerTests.swift
//  YatuTests
//
//  What the app does with a hand-off. The launcher is injected, so these run
//  without opening anything.
//

import XCTest
@testable import YatuKit
import YatuUpstream

final class RequestHandlerTests: XCTestCase {

    private var store: MemoryStore!
    private var settings: Settings!
    private var launched: [(SupportedApps, [URL])] = []
    private var sandbox: URL!

    override func setUpWithError() throws {
        store = MemoryStore()
        settings = Settings(store: store)
        launched = []
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("YatuHandOff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func handle(_ request: HandOff.Request) -> RequestHandler.Outcome {
        RequestHandler.handle(request, settings: settings) { app, targets in
            self.launched.append((app, targets))
        }
    }

    func testTheEditorIsGivenEverySelectedFile() throws {
        // The rule (plan §4.1 rule 3): a terminal opens at exactly one place,
        // so it ignores a multiple selection; an editor is handed all of them,
        // where order does not matter. This failed for two months because the
        // extension collapsed the selection before the role was known.
        let files = try (0..<3).map { index -> URL in
            let file = sandbox.appendingPathComponent("file\(index).txt")
            try "contents".write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        _ = handle(.open(role: .editor, app: .vscode, items: files, container: sandbox))
        XCTAssertEqual(launched.first?.0, .vscode)
        XCTAssertEqual(launched.first?.1.map(\.lastPathComponent).sorted(),
                       files.map(\.lastPathComponent).sorted())
    }

    func testATerminalStillIgnoresAMultipleSelection() throws {
        let files = try (0..<3).map { index -> URL in
            let file = sandbox.appendingPathComponent("file\(index).txt")
            try "contents".write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        settings.setChosenApp(.iTerm, for: .terminal)
        _ = handle(.open(role: .terminal, app: nil, items: files, container: sandbox))
        XCTAssertEqual(launched.first?.1.map(\.path), [sandbox.path],
                       "several selected items mean the folder being viewed, not one of them")
    }

    /// A stand-in for Finder, so the fallback can be tested without one.
    private struct StubFinder: FinderQuerying {
        let selection: [URL]
        let window: URL?
        func selectedItems() -> [URL] { selection }
        func frontWindowTarget() -> URL? { window }
    }

    func testAnEmptyContextAsksFinderDirectly() throws {
        // The iCloud Drive case. The extension reports nothing because
        // FIFinderSyncController.targetedURL() answers nil there, and the app
        // -- which can reach Finder over ScriptingBridge, as the Cmd-drag path
        // always could -- asks for itself.
        settings.setChosenApp(.iTerm, for: .terminal)
        var asked = false
        let outcome = RequestHandler.handle(
            .open(role: .terminal, app: nil, items: [], container: nil),
            settings: settings,
            launch: { app, targets in self.launched.append((app, targets)) },
            askFinder: {
                asked = true
                return StubFinder(selection: [], window: self.sandbox)
            })
        XCTAssertTrue(asked, "an empty context must fall back to asking Finder")
        XCTAssertEqual(launched.first?.1.map(\.path), [sandbox.path])
        if case .nothingToDo = outcome { XCTFail("should have launched") }
    }

    func testAReportedContextDoesNotAskFinder() {
        // The common path must not pay for the fallback.
        settings.setChosenApp(.iTerm, for: .terminal)
        var asked = false
        _ = RequestHandler.handle(
            .open(role: .terminal, app: nil, items: [], container: sandbox),
            settings: settings,
            launch: { app, targets in self.launched.append((app, targets)) },
            askFinder: { asked = true; return StubFinder(selection: [], window: nil) })
        XCTAssertFalse(asked, "Finder was reported; there is nothing to ask")
        XCTAssertEqual(launched.first?.1.map(\.path), [sandbox.path])
    }

    func testOpenUsesTheStoredDefault() throws {
        settings.setChosenApp(.iTerm, for: .terminal)
        _ = handle(.open(role: .terminal, app: nil, items: [], container: sandbox))
        XCTAssertEqual(launched.first?.0, .iTerm)
        // Compared as paths: a directory URL may or may not carry a trailing
        // slash depending on how it was resolved, and that is not a difference
        // worth failing on.
        XCTAssertEqual(launched.first?.1.map(\.path),
                       [sandbox.resolvingSymlinksInPath().path])
    }

    func testOpenWithNothingChosenDoesNothing() {
        guard case .nothingToDo = handle(.open(role: .terminal, app: nil, items: [], container: sandbox))
        else { return XCTFail("should not launch") }
        XCTAssertTrue(launched.isEmpty)
    }

    /// A named app is a one-off: it launches, and the stored default is untouched.
    func testANamedAppDoesNotChangeTheDefault() throws {
        settings.setChosenApp(.terminal, for: .terminal)
        _ = handle(.open(role: .terminal, app: .iTerm, items: [], container: sandbox))
        XCTAssertEqual(launched.first?.0, .iTerm)
        XCTAssertEqual(settings.chosenApp(for: .terminal), .terminal, "the default moved")
    }

    /// The rules run here, not in the extension: a file yields its parent.
    func testAFileReportedByTheExtensionYieldsItsParent() throws {
        settings.setChosenApp(.iTerm, for: .terminal)
        let file = sandbox.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: file)

        _ = handle(.open(role: .terminal, app: nil, items: [file], container: sandbox))
        XCTAssertEqual(launched.first?.1.map(\.lastPathComponent),
                       [sandbox.resolvingSymlinksInPath().lastPathComponent])
    }

    /// And a path that no longer exists falls back rather than being passed on.
    func testAVanishedPathFallsBack() throws {
        settings.setChosenApp(.iTerm, for: .terminal)
        let gone = sandbox.appendingPathComponent("not-there")
        _ = handle(.open(role: .terminal, app: nil, items: [gone], container: nil))
        XCTAssertEqual(launched.first?.1.map(\.path), [FinderTarget.desktop.path])
    }

    func testSetDefaultIsStoredAndLaunchesNothing() {
        XCTAssertEqual(handle(.setDefault(role: .terminal, app: .iTerm)),
                       .defaultChanged(.terminal, .iTerm))
        XCTAssertEqual(settings.chosenApp(for: .terminal), .iTerm)
        XCTAssertTrue(launched.isEmpty)
    }

    func testSettingsJustAsksForTheWindow() {
        XCTAssertEqual(handle(.settings(role: .terminal)), .showSettings(.terminal))
        XCTAssertTrue(launched.isEmpty)
    }
}
