//
//  RequestHandler.swift
//  YatuKit
//
//  Carrying out a hand-off from the Finder extension.
//
//  Everything the extension reports is untrusted: it arrives over a public URL
//  scheme that any application or web page can invoke. Nothing here takes a
//  path at its word. `FinderTarget` applies exactly the rules it applies to
//  Finder's own answers — a terminal is only ever handed an existing directory,
//  an .app bundle is never a target — and `Catalog` is the allowlist for which
//  application may be launched at all.
//

import Foundation
import YatuUpstream

public enum RequestHandler {

    public enum Outcome: Equatable {
        case launched(SupportedApps, [URL])
        case defaultChanged(Role, SupportedApps)
        case showSettings(Role)
        /// Understood, but there is nothing to act on.
        case nothingToDo(String)
    }

    /// A Finder context reported by the extension, replayed through the same
    /// protocol the app uses for its own queries. The extension resolves
    /// nothing, so the rules run here and only here.
    private struct ReportedContext: FinderQuerying {
        let items: [URL]
        let container: URL?
        func selectedItems() -> [URL] { items }
        func frontWindowTarget() -> URL? { container }
    }

    @discardableResult
    public static func handle(_ request: HandOff.Request,
                              settings: Settings = Settings(),
                              launch: (SupportedApps, [URL]) throws -> Void = Launcher.launch,
                              askFinder: () -> FinderQuerying = { FinderScriptingQuery() })
        -> Outcome
    {
        switch request {
        case let .open(role, requestedApp, items, container):
            // An explicitly named app is a one-off; otherwise the stored
            // default. Either way it came through the catalog allowlist.
            guard let app = requestedApp ?? settings.chosenApp(for: role) else {
                Log.launch.info("hand-off for \(role.rawValue, privacy: .public) with nothing chosen")
                return .nothingToDo("no \(role.rawValue) chosen yet")
            }
            // The per-role rule lives in FinderTarget and only there: the
            // terminal ignores a multiple selection in favour of the container,
            // the editor takes all of it.
            //
            // When the extension reported nothing at all, ask Finder directly
            // instead. The extension's view is narrower than AppleScript's: in
            // an iCloud Drive window FIFinderSyncController.targetedURL()
            // returns nil, while Finder answers the same question happily over
            // ScriptingBridge — which is why the Cmd-drag path could always
            // open iCloud Drive when the toolbar button could not.
            let context: FinderQuerying = items.isEmpty && container == nil
                ? askFinder()
                : ReportedContext(items: items, container: container)
            let targets = FinderTarget.resolve(for: role, using: context)
            do {
                try launch(app, targets)
                return .launched(app, targets)
            } catch {
                Log.launch.error("hand-off launch failed: \(String(describing: error), privacy: .public)")
                return .nothingToDo("could not launch \(app.name)")
            }

        case let .setDefault(role, app):
            guard settings.setChosenApp(app, for: role) else {
                return .nothingToDo("refused \(app.name) for \(role.rawValue)")
            }
            // Not logged here: Settings.setChosenApp logs the write itself, so
            // every path that changes the preference leaves one trace, not one
            // per caller.
            return .defaultChanged(role, app)

        case let .settings(role):
            return .showSettings(role)
        }
    }
}
