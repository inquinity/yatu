//
//  Yatu.swift
//  YatuKit
//
//  The entry point both executables share. They differ only in the role.
//

import AppKit
import Foundation
import YatuUpstream

public enum Yatu {

    public static func run(role: Role) -> Never {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--version") {
            print("\(role.displayName) \(Version.short) build \(Version.build)")
            exit(0)
        }

        if arguments.contains("--identity") {
            let stored = Settings().chosenApp(for: role)
            print("role:       \(role.rawValue)")
            print("name:       \(role.displayName)")
            print("bundle id:  \(role.bundleIdentifier)")
            print("catalog:    \(Catalog.apps(for: role).count) apps")
            print("chosen:     \(stored?.name ?? "(none)")")
            exit(0)
        }

        let settings = Settings()

        // §5: a Finder toolbar app has no menu bar, so ⌥-clicking the button is
        // the discoverable way in. --settings is the same door, for scripting
        // and for the cask's caveat.
        let wantsSettings = arguments.contains("--settings")
            || NSEvent.modifierFlags.contains(.option)

        guard let app = settings.chosenApp(for: role), !wantsSettings else {
            // First run, an invalidated choice, or an explicit request: all
            // three mean "show the picker" rather than guessing on the user's
            // behalf. This call does not return.
            SettingsWindow.run(role: role, settings: settings)
        }

        let targets = FinderTarget.resolve(for: role, using: FinderScriptingQuery())

        do {
            try Launcher.launch(app, with: targets)
        } catch {
            Log.launch.error("launch failed: \(String(describing: error), privacy: .public)")
            FileHandle.standardError.write(Data("\(role.displayName): \(error)\n".utf8))
            exit(1)
        }

        // NSWorkspace's completion handlers run on a background queue; give them
        // a moment to hand off to LaunchServices before the process goes away.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        exit(0)
    }
}
