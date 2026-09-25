//
//  SettingsWindow.swift
//  YatuKit
//
//  The settings window, as a window and nothing more.
//
//  This used to be an entry point: `run(role:settings:)` installed its own
//  NSApplicationDelegate, called NSApplication.run() and never returned. That is
//  what broke the menu. A process has one delegate and one run loop, and a
//  window is not entitled to either — see LaunchCoordinator in Yatu.swift, which
//  is the only thing in this app that owns them.
//
//  Nothing here touches NSApp: showing, focusing and closing are the
//  coordinator's business, because only the coordinator knows what else is on
//  screen and whether the process should still be alive.
//

import AppKit
import SwiftUI

enum SettingsWindow {

    /// Build the window. The caller shows it and owns it.
    static func make(role: Role, settings: Settings) -> NSWindow {
        let model = SettingsViewModel(role: role, settings: settings)
        let hosting = NSHostingController(rootView: SettingsView(model: model))

        let window = NSWindow(contentViewController: hosting)
        window.title = "\(role.displayName) Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // The coordinator keeps a reference and decides when this goes away.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
