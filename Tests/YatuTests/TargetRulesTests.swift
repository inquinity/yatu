//
//  TargetRulesTests.swift
//  YatuTests
//
//  The behavioural rules from docs/ROADMAP.md §4.1, one test each.
//

import XCTest
@testable import YatuKit
import YatuUpstream

/// A Finder that answers whatever the test says it does.
struct StubFinder: FinderQuerying {
    var selection: [URL] = []
    var windowTarget: URL?
    func selectedItems() -> [URL] { selection }
    func frontWindowTarget() -> URL? { windowTarget }
}

final class TargetRulesTests: XCTestCase {

    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("YatuTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func makeFile(_ name: String, executable: Bool = false) throws -> URL {
        let url = sandbox.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = sandbox.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Rule 3, terminal: always an existing directory

    func testDirectoryOfADirectoryIsItself() throws {
        let folder = try makeDirectory("project")
        XCTAssertEqual(FinderTarget.directory(for: folder)?.path, folder.resolvingSymlinksInPath().path)
    }

    func testDirectoryOfAFileIsItsParent() throws {
        let file = try makeFile("notes.txt")
        XCTAssertEqual(FinderTarget.directory(for: file)?.path,
                       sandbox.resolvingSymlinksInPath().path)
    }

    func testSymlinkToAFileIsTreatedAsAFile() throws {
        let target = try makeFile("real.txt")
        let link = sandbox.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(FinderTarget.directory(for: link)?.path,
                       sandbox.resolvingSymlinksInPath().path)
    }

    /// An .app is a directory on disk. Handing one to a terminal is how an
    /// "open here" turns into an "execute this".
    func testApplicationBundleYieldsItsParentNotItself() throws {
        let bundle = try makeDirectory("Calculator.app")
        XCTAssertEqual(FinderTarget.directory(for: bundle)?.path,
                       sandbox.resolvingSymlinksInPath().path)
    }

    func testCommandFileYieldsItsParent() throws {
        let script = try makeFile("payload.command", executable: true)
        XCTAssertEqual(FinderTarget.directory(for: script)?.path,
                       sandbox.resolvingSymlinksInPath().path)
    }

    func testMissingPathResolvesToNothing() {
        XCTAssertNil(FinderTarget.directory(for: sandbox.appendingPathComponent("gone")))
    }

    // MARK: - Rule 3, editor: files yes, executables and bundles no

    func testEditorKeepsOrdinaryFiles() throws {
        let file = try makeFile("readme.md")
        XCTAssertEqual(FinderTarget.editableItems(from: [file]).count, 1)
    }

    func testEditorDropsApplicationBundles() throws {
        let bundle = try makeDirectory("Calculator.app")
        let plain = try makeFile("plain.txt")
        let kept = FinderTarget.editableItems(from: [bundle, plain])
        XCTAssertEqual(kept.map(\.lastPathComponent), ["plain.txt"])
    }

    /// Relaxed 2026-09-18: an editor is opened *with* the file, so it is edited
    /// rather than run, and refusing executables blocked ordinary scripts.
    func testEditorKeepsExecutableScripts() throws {
        let script = try makeFile("run.sh", executable: true)
        let command = try makeFile("deploy.command", executable: true)
        let kept = FinderTarget.editableItems(from: [script, command])
        XCTAssertEqual(kept.map(\.lastPathComponent), ["run.sh", "deploy.command"])
    }

    /// The terminal rule is unchanged: an executable is still never a target.
    func testTerminalStillRefusesExecutablesAsTargets() throws {
        let script = try makeFile("run.sh", executable: true)
        XCTAssertEqual(FinderTarget.directory(for: script)?.path,
                       sandbox.resolvingSymlinksInPath().path)
    }

    // MARK: - Rule 4: nothing usable means the Desktop

    func testDesktopIsBuiltAsAFilePathNotParsed() {
        XCTAssertTrue(FinderTarget.desktop.isFileURL)
        XCTAssertEqual(FinderTarget.desktop.lastPathComponent, "Desktop")
    }

    func testNoFinderWindowFallsBackToTheDesktop() {
        let resolved = FinderTarget.resolve(for: .terminal, using: StubFinder())
        XCTAssertEqual(resolved, [FinderTarget.desktop])
    }

    /// A view with no filesystem target — Recents, AirDrop, a search — answers
    /// with nothing usable rather than crashing, which is finding L3.
    func testUnusableTargetFallsBackToTheDesktop() {
        let stub = StubFinder(selection: [], windowTarget: URL(fileURLWithPath: "/does/not/exist"))
        XCTAssertEqual(FinderTarget.resolve(for: .terminal, using: stub), [FinderTarget.desktop])
    }

    func testSelectedFileGivesTheTerminalItsParentFolder() throws {
        let file = try makeFile("main.swift")
        let stub = StubFinder(selection: [file])
        XCTAssertEqual(FinderTarget.resolve(for: .terminal, using: stub).map(\.path),
                       [sandbox.resolvingSymlinksInPath().path])
    }

    /// A terminal opens at one directory. With several items selected there is
    /// no non-arbitrary way to choose between them, so the container wins.
    func testSeveralSelectedItemsGiveTheTerminalTheContainingFolder() throws {
        let first = try makeDirectory("alpha")
        let second = try makeDirectory("beta")
        let container = try makeDirectory("container")
        let stub = StubFinder(selection: [first, second], windowTarget: container)
        XCTAssertEqual(FinderTarget.resolve(for: .terminal, using: stub).map(\.lastPathComponent),
                       ["container"])
    }

    /// One selected folder still names the place.
    func testOneSelectedFolderGivesTheTerminalThatFolder() throws {
        let folder = try makeDirectory("projects")
        let container = try makeDirectory("container")
        let stub = StubFinder(selection: [folder], windowTarget: container)
        XCTAssertEqual(FinderTarget.resolve(for: .terminal, using: stub).map(\.lastPathComponent),
                       ["projects"])
    }

    /// The editor is unaffected: order does not matter when opening documents.
    func testSeveralSelectedItemsStillReachTheEditor() throws {
        let a = try makeFile("a.txt"), b = try makeFile("b.txt")
        let stub = StubFinder(selection: [a, b], windowTarget: sandbox)
        XCTAssertEqual(FinderTarget.resolve(for: .editor, using: stub).map(\.lastPathComponent),
                       ["a.txt", "b.txt"])
    }

    func testEditorReceivesTheSelectedItemsThemselves() throws {
        let first = try makeFile("a.txt")
        let second = try makeFile("b.txt")
        let stub = StubFinder(selection: [first, second])
        XCTAssertEqual(FinderTarget.resolve(for: .editor, using: stub).map(\.lastPathComponent),
                       ["a.txt", "b.txt"])
    }
}
