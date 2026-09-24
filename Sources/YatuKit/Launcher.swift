//
//  Launcher.swift
//  YatuKit
//
//  Opens the resolved target in the chosen application.
//
//  Rules 1, 2, 5 and 7 (docs/YATU-PLAN.md §4.1).
//

import AppKit
import Foundation
import YatuUpstream
#if canImport(ScriptingBridge)
import ScriptingBridge
#endif

public enum LaunchError: Error, Equatable {
    /// The catalog entry has no bundle id and no application on disk (rule 2).
    case applicationNotInstalled(String)
    /// The system refused to launch it.
    case launchFailed(String)
    /// Terminal.app did not answer over ScriptingBridge (rule 7).
    case scriptingBridgeUnavailable
}

public enum Launcher {

    // MARK: - Argument templates (rule 5)

    /// Compiled-in constants, never read from preferences.
    ///
    /// Upstream stored these as editable strings (`KittyCommand` and friends)
    /// and split them on spaces at launch, so anyone who could write the
    /// preferences domain could choose both the program and its arguments —
    /// finding L1. Here the only thing a preference decides is *which catalog
    /// entry* is used; the argument vector that entry implies is fixed at
    /// compile time.
    static func argumentTemplate(for app: SupportedApps) -> [String]? {
        switch app {
        case .alacritty:
            return ["--working-directory"]
        case .kitty:
            return ["--single-instance", "--instance-group", "1", "--directory"]
        case .wezterm:
            return ["start", "--cwd"]
        case .tabby:
            return ["--directory"]
        default:
            // Everything else is handed the target the ordinary way: the app is
            // opened *with* the URL, no argument vector involved.
            return nil
        }
    }

    // MARK: - Resolution (rules 1 and 2)

    /// Where the application actually is, resolved by bundle id.
    ///
    /// Rule 1: resolution is by bundle id, never by name.
    ///
    /// **Corrected 2026-09-24.** This used to say "a name is a string a user can
    /// control, a bundle id is what LaunchServices indexes", as though the
    /// identifier were a trust signal. It is not: a bundle planted in
    /// ~/Downloads claiming another application's identifier resolves through
    /// this call, with no write access to /Applications needed. That was
    /// tested — see docs/LAUNCH-SECURITY.md.
    ///
    /// Resolving by identifier is still right, because it finds the app
    /// wherever it lives rather than guessing a path. But the thing that stops
    /// a planted impostor is **Gatekeeper**, not this lookup, and the comment
    /// should not imply otherwise.
    /// Rule 2: the handful of catalog entries upstream ships without a bundle
    /// id are looked for at an explicit `/Applications` path, and dropped if
    /// they are not there.
    public static func applicationURL(for app: SupportedApps,
                                      fileManager: FileManager = .default) -> URL? {
        // Corrected where the vendored catalog is known to be wrong, which is
        // why this asks Catalog rather than reading app.bundleId directly.
        let bundleIdentifier = Catalog.bundleIdentifier(for: app)
        if !bundleIdentifier.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        let explicit = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent("\(app.name).app")
        return fileManager.fileExists(atPath: explicit.path) ? explicit : nil
    }

    /// Whether this entry can be offered at all on this Mac.
    public static func isInstalled(_ app: SupportedApps,
                                   fileManager: FileManager = .default) -> Bool {
        applicationURL(for: app, fileManager: fileManager) != nil
    }

    // MARK: - Launching

    public static func launch(_ app: SupportedApps, with targets: [URL]) throws {
        guard !targets.isEmpty else { return }

        // Rule 7: Terminal.app opens a folder through ScriptingBridge. It is the
        // only entry that does, because it is the only one that can be told to
        // open a directory without being handed a shell to run.
        if app == .terminal {
            try launchAppleTerminal(with: targets)
            return
        }

        guard let applicationURL = applicationURL(for: app) else {
            throw LaunchError.applicationNotInstalled(app.name)
        }

        let configuration = NSWorkspace.OpenConfiguration()

        if let template = argumentTemplate(for: app) {
            // These terminals take the directory as an argument rather than as a
            // document, and each wants its own instance.
            configuration.createsNewApplicationInstance = true
            configuration.arguments = template + targets.map(\.path)
            Log.launch.info("launching \(app.name, privacy: .public) with a compiled-in template")
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
                if let error {
                    Log.launch.error("\(app.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        }

        Log.launch.info("opening \(targets.count) item(s) in \(app.name, privacy: .public)")
        NSWorkspace.shared.open(targets, withApplicationAt: applicationURL,
                                configuration: configuration) { _, error in
            if let error {
                Log.launch.error("\(app.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    #if canImport(ScriptingBridge)
    private static func launchAppleTerminal(with targets: [URL]) throws {
        guard let application = SBApplication(bundleIdentifier: SupportedApps.terminal.bundleId),
              let terminal = application as TerminalApplication?,
              let open = terminal.open else {
            throw LaunchError.scriptingBridgeUnavailable
        }
        Log.launch.info("opening \(targets.count) item(s) in Terminal")
        open(targets)
        terminal.activate()
    }
    #else
    private static func launchAppleTerminal(with targets: [URL]) throws {
        throw LaunchError.scriptingBridgeUnavailable
    }
    #endif
}
