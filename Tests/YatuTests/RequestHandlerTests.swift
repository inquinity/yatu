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

    func testOpenUsesTheStoredDefault() throws {
        settings.setChosenApp(.iTerm, for: .terminal)
        _ = handle(.open(role: .terminal, app: nil, item: nil, container: sandbox))
        XCTAssertEqual(launched.first?.0, .iTerm)
        // Compared as paths: a directory URL may or may not carry a trailing
        // slash depending on how it was resolved, and that is not a difference
        // worth failing on.
        XCTAssertEqual(launched.first?.1.map(\.path),
                       [sandbox.resolvingSymlinksInPath().path])
    }

    func testOpenWithNothingChosenDoesNothing() {
        guard case .nothingToDo = handle(.open(role: .terminal, app: nil, item: nil, container: sandbox))
        else { return XCTFail("should not launch") }
        XCTAssertTrue(launched.isEmpty)
    }

    /// A named app is a one-off: it launches, and the stored default is untouched.
    func testANamedAppDoesNotChangeTheDefault() throws {
        settings.setChosenApp(.terminal, for: .terminal)
        _ = handle(.open(role: .terminal, app: .iTerm, item: nil, container: sandbox))
        XCTAssertEqual(launched.first?.0, .iTerm)
        XCTAssertEqual(settings.chosenApp(for: .terminal), .terminal, "the default moved")
    }

    /// The rules run here, not in the extension: a file yields its parent.
    func testAFileReportedByTheExtensionYieldsItsParent() throws {
        settings.setChosenApp(.iTerm, for: .terminal)
        let file = sandbox.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: file)

        _ = handle(.open(role: .terminal, app: nil, item: file, container: sandbox))
        XCTAssertEqual(launched.first?.1.map(\.lastPathComponent),
                       [sandbox.resolvingSymlinksInPath().lastPathComponent])
    }

    /// And a path that no longer exists falls back rather than being passed on.
    func testAVanishedPathFallsBack() throws {
        settings.setChosenApp(.iTerm, for: .terminal)
        let gone = sandbox.appendingPathComponent("not-there")
        _ = handle(.open(role: .terminal, app: nil, item: gone, container: nil))
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
