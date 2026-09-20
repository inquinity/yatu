//
//  SettingsWindow.swift
//  YatuKit
//
//  The AppKit host for SettingsView.
//
//  A Finder toolbar app has no menu bar of its own and no Dock presence
//  (LSUIElement), so the window has to ask for focus explicitly or it opens
//  behind Finder and looks like nothing happened.
//

import AppKit
import SwiftUI

public enum SettingsWindow {

    /// Show the window and run until it is closed. Never returns.
    public static func run(role: Role, settings: Settings = Settings()) -> Never {
        let application = NSApplication.shared
        // .accessory keeps the app out of the Dock and the ⌘-Tab list while
        // still allowing a window that can become key.
        application.setActivationPolicy(.accessory)

        let controller = WindowController(role: role, settings: settings)
        application.delegate = controller
        // NSApplication does not retain its delegate.
        retained = controller

        application.run()
        exit(0)
    }

    private static var retained: AnyObject?
}

private final class WindowController: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let role: Role
    private let settings: Settings
    private var window: NSWindow?

    init(role: Role, settings: Settings) {
        self.role = role
        self.settings = settings
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = SettingsViewModel(role: role, settings: settings)
        let hosting = NSHostingController(rootView: SettingsView(model: model))

        let window = NSWindow(contentViewController: hosting)
        window.title = "\(role.displayName) Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window is how this app is finished with.
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
