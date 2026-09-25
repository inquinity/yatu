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

        // §5: a Finder toolbar app has no menu bar, so ⌥ is the discoverable
        // way in. --settings is the same door, for scripting and the cask.
        //
        // This used to call SettingsWindow.run here and never reach the
        // coordinator, which meant a ⌥-launched process had no delegate able to
        // answer a later yatu:// URL. It is now one flag on one coordinator.
        let wantsSettings = arguments.contains("--settings")
            || NSEvent.modifierFlags.contains(.option)

        LaunchCoordinator.run(role: role, settings: Settings(), opensSettings: wantsSettings)
    }
}

/// The app delegate, for the whole life of the process.
///
/// ## One delegate, one run loop
///
/// Both of those are singular, and the version of this file that shipped in
/// 1.0.1 treated them as reusable. `SettingsWindow.run` and `AboutWindow.run`
/// each assigned `NSApp.delegate` and called `NSApplication.run()` a second
/// time, re-entrantly, from inside `application(_:open:)` — which is itself
/// running inside the first `run()`. Three separate faults came out of that,
/// and all three were visible to the user:
///
///  * **The window did not appear.** Those controllers built their window in
///    `applicationDidFinishLaunching`, a notification already posted for this
///    process. Whether it arrived a second time depended on whether the URL
///    reached the app before or after the first one — so About worked, then
///    failed, then worked.
///  * **The wrong thing happened.** Once the delegate had been displaced, the
///    next toolbar click was delivered to the *window's* controller, whose
///    `application(_:open:)` raised its own window and discarded the request.
///    Clicking for a terminal produced the about box.
///  * **A request could kill a window.** `nothingToDo` called `exit(1)`
///    unconditionally.
///
/// So: this object is the only NSApplicationDelegate, `run()` is called exactly
/// once, windows are built by factories and owned here, and the process lives
/// exactly as long as there is a window on screen. `LaunchLifetimeTests` asserts
/// the first two of those against the source, because nothing else can — the
/// failure only exists in a running app, and it looks like a dead menu item.
///
/// The shape is OpenInTerminal's: one delegate installed once, window
/// presentation as a method on it, and the activation policy flipped around the
/// window rather than the app shouting `activate(ignoringOtherApps:)` at a
/// permanent accessory.
final class LaunchCoordinator: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let role: Role
    private let settings: Settings
    /// A ⌥-launch or `--settings`: show settings rather than wait for a URL.
    private let opensSettings: Bool

    /// Set once this launch has been accounted for, by whichever path got there
    /// first. Only the grace timer reads it.
    private var launchHandled = false

    /// Set when the grace timer concluded there was no hand-off and acted on the
    /// direct-open path. A URL arriving after that is *this* launch reported
    /// late, not a second request, and acting on it would do the work twice.
    private var actedWithoutHandOff = false

    /// How long to wait for a hand-off before concluding there is not one.
    /// AppKit delivers the URL around `applicationDidFinishLaunching`; this is
    /// the margin, and it is only ever paid when the app was opened directly.
    private static let handOffGrace: TimeInterval = 0.35

    private static var retained: AnyObject?

    private init(role: Role, settings: Settings, opensSettings: Bool) {
        self.role = role
        self.settings = settings
        self.opensSettings = opensSettings
    }

    static func run(role: Role, settings: Settings, opensSettings: Bool) -> Never {
        let application = NSApplication.shared
        // Accessory until something needs showing; `show` promotes to .regular.
        application.setActivationPolicy(.accessory)
        let coordinator = LaunchCoordinator(role: role, settings: settings,
                                            opensSettings: opensSettings)
        application.delegate = coordinator
        retained = coordinator          // NSApplication does not retain its delegate
        application.run()               // exactly once, for the life of the process
        exit(0)
    }

    // MARK: - Working out which launch this is

    func applicationDidFinishLaunching(_ notification: Notification) {
        if opensSettings {
            launchHandled = true
            show(.settings(role))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOffGrace) { [self] in
            guard !launchHandled else { return }
            launchHandled = true
            actedWithoutHandOff = true
            openedDirectly()
        }
    }

    /// The extension handed something over. Anything on this machine can invoke
    /// the scheme, so an unrecognised URL is dropped rather than interpreted.
    ///
    /// This runs for every URL the process is ever given, not just the first,
    /// and it routes on what the URL says — never on what happens to be on
    /// screen. That distinction is the whole bug this class documents.
    func application(_ application: NSApplication, open urls: [URL]) {
        launchHandled = true
        guard !actedWithoutHandOff else {
            Log.launch.notice("a hand-off arrived after the direct-open path had acted; ignoring it")
            return
        }
        guard let request = urls.compactMap(HandOff.request(from:)).first else {
            Log.launch.error("ignored an unrecognised URL")
            finish(status: 1)
            return
        }
        act(on: request)
    }

    /// Opened again — from the Dock, or `open -a Yatu.app` — while this process
    /// is still alive. There is no URL, so `application(_:open:)` never sees it,
    /// and without this the second open of a live Yatu does nothing at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launchHandled = true
        if flag {
            raiseWindows()
        } else {
            openedDirectly()
        }
        return true
    }

    /// Opened from the Dock, Spotlight, or the app dragged into a toolbar —
    /// still supported. Ask Finder directly.
    private func openedDirectly() {
        guard let app = settings.chosenApp(for: role) else {
            show(.settings(role))
            return
        }
        launch(app, FinderTarget.resolve(for: role, using: FinderScriptingQuery()))
    }

    private func act(on request: HandOff.Request) {
        switch RequestHandler.handle(request, settings: settings) {
        case .showSettings(let role):
            show(.settings(role))
        case .showAbout:
            show(.about)
        case .nothingToDo(let reason):
            FileHandle.standardError.write(Data("\(reason)\n".utf8))
            finish(status: 1)
        case .launched, .defaultChanged:
            finish()
        }
    }

    private func launch(_ app: SupportedApps, _ targets: [URL]) {
        do {
            try Launcher.launch(app, with: targets)
        } catch {
            Log.launch.error("launch failed: \(String(describing: error), privacy: .public)")
            FileHandle.standardError.write(Data("\(role.displayName): \(error)\n".utf8))
            return finish(status: 1)
        }
        finish()
    }

    // MARK: - Windows

    /// What a window shows. Settings is per-role; an about box is the
    /// application's, so it is keyed on nothing else. Identity by *what it
    /// shows* rather than by object, so a second request raises the window
    /// already up instead of stacking another one behind it — which is what
    /// OpenInTerminal's `showPreferencesWindow` does, and the one thing there
    /// not worth copying.
    private enum WindowID: Hashable {
        case settings(Role)
        case about
    }

    private var windows: [WindowID: NSWindow] = [:]

    private func show(_ id: WindowID) {
        if windows[id] == nil {
            let fresh: NSWindow
            switch id {
            case .settings(let role): fresh = SettingsWindow.make(role: role, settings: settings)
            case .about:              fresh = AboutWindow.make()
            }
            fresh.delegate = self
            windows[id] = fresh
        }
        guard let window = windows[id] else { return }

        // .regular while anything is on screen. An accessory app has no Dock
        // tile and no menu bar, so its window is hard to get back to the moment
        // anything else is clicked; promoting for as long as the window lives
        // is both more correct and cheaper than repeatedly shouting
        // `activate(ignoringOtherApps:)` at a permanent accessory.
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func raiseWindows() {
        NSApp.setActivationPolicy(.regular)
        windows.values.forEach { $0.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Lifetime

    /// This request is carried out. The process exits only if nothing is on
    /// screen: a window outlives the request that opened it, so a toolbar click
    /// arriving while the about box is up opens a terminal *and leaves the about
    /// box where it was*.
    private func finish(status: Int32 = 0) {
        guard windows.isEmpty else { return }
        // NSWorkspace hands off to LaunchServices asynchronously; give it a
        // moment before the process goes away.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        exit(status)
    }

    /// The last window closing is how this app is finished with, whether that
    /// was an OK button or a close box.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== closing }
        guard windows.isEmpty else { return }
        NSApp.setActivationPolicy(.accessory)
        // Deferred: terminating from inside windowWillClose tears down a window
        // that is still in the middle of closing.
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
