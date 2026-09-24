//
//  Yatu.swift
//  YatuKit
//
//  The entry point the executable shares with the Finder extension's hand-offs.
//
//  There are three ways in, and the app cannot tell them apart before it is
//  running, because a hand-off arrives as an Apple Event just after launch
//  rather than as an argument:
//
//    * the extension handed something over          (yatu:// URL)
//    * the settings window was asked for            (--settings, or ⌥)
//    * the app itself was opened                    (Dock, Spotlight, or the
//                                                    app dragged into a toolbar)
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

        // §5: a Finder toolbar app has no menu bar, so ⌥ is the discoverable
        // way in. --settings is the same door, for scripting and the cask.
        if arguments.contains("--settings") || NSEvent.modifierFlags.contains(.option) {
            SettingsWindow.run(role: role, settings: settings)
        }

        LaunchCoordinator.run(role: role, settings: settings)
    }
}

/// Works out, once the app is running, which of the three launches this is.
final class LaunchCoordinator: NSObject, NSApplicationDelegate {

    private let role: Role
    private let settings: Settings
    private var handled = false

    /// How long to wait for a hand-off before concluding there is not one.
    /// AppKit delivers the URL around `applicationDidFinishLaunching`; this is
    /// the margin, and it is only ever paid when the app was opened directly.
    private static let handOffGrace: TimeInterval = 0.35

    private static var retained: AnyObject?

    private init(role: Role, settings: Settings) {
        self.role = role
        self.settings = settings
    }

    static func run(role: Role, settings: Settings) -> Never {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let coordinator = LaunchCoordinator(role: role, settings: settings)
        application.delegate = coordinator
        retained = coordinator          // NSApplication does not retain its delegate
        application.run()
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOffGrace) { [self] in
            guard !handled else { return }
            handled = true
            openedDirectly()
        }
    }

    /// The extension handed something over. Anything on this machine can invoke
    /// the scheme, so an unrecognised URL is dropped rather than interpreted.
    func application(_ application: NSApplication, open urls: [URL]) {
        handled = true
        guard let request = urls.compactMap(HandOff.request(from:)).first else {
            Log.launch.error("ignored an unrecognised URL")
            exit(1)
        }
        act(on: request)
    }

    /// Opened from the Dock, Spotlight, or the app dragged into a toolbar —
    /// still supported. Ask Finder directly.
    private func openedDirectly() {
        guard let app = settings.chosenApp(for: role) else {
            SettingsWindow.run(role: role, settings: settings)
        }
        let targets = FinderTarget.resolve(for: role, using: FinderScriptingQuery())
        launch(app, targets)
    }

    private func act(on request: HandOff.Request) {
        switch RequestHandler.handle(request, settings: settings) {
        case .showSettings(let role):
            SettingsWindow.run(role: role, settings: settings)
        case .nothingToDo(let reason):
            FileHandle.standardError.write(Data("\(reason)\n".utf8))
            exit(1)
        case .launched, .defaultChanged:
            finish()
        }
    }

    private func launch(_ app: SupportedApps, _ targets: [URL]) -> Never {
        do {
            try Launcher.launch(app, with: targets)
        } catch {
            Log.launch.error("launch failed: \(String(describing: error), privacy: .public)")
            FileHandle.standardError.write(Data("\(role.displayName): \(error)\n".utf8))
            exit(1)
        }
        finish()
    }

    /// NSWorkspace hands off to LaunchServices asynchronously; give it a moment
    /// before the process goes away.
    private func finish() -> Never {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        exit(0)
    }
}
