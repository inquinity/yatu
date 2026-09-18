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
            print("\(role.displayName) \(Version.short) (\(Version.build))")
            exit(0)
        }

        if arguments.contains("--identity") {
            print("role:       \(role.rawValue)")
            print("name:       \(role.displayName)")
            print("bundle id:  \(role.bundleIdentifier)")
            print("catalog:    \(Catalog.apps(for: role).count) apps")
            exit(0)
        }

        let settings = Settings()

        // The settings window arrives in M2c; until then an explicit request for
        // it says so rather than silently doing nothing.
        if arguments.contains("--settings") {
            FileHandle.standardError.write(Data("the settings window is not built yet (M2c)\n".utf8))
            exit(1)
        }

        guard let app = settings.chosenApp(for: role) else {
            // First run, or a stored choice that is no longer valid. The picker
            // is part of the settings window, so for now say what is missing
            // rather than guessing an application on the user's behalf.
            FileHandle.standardError.write(Data(
                "No \(role.rawValue) chosen yet. Choose one with the settings window (M2c).\n".utf8))
            exit(1)
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
