//
//  AboutWindow.swift
//  YatuKit
//
//  The about box, as a window and nothing more. Same shape as SettingsWindow
//  and for the same reason: see the note there, and LaunchCoordinator.
//

import AppKit
import SwiftUI

enum AboutWindow {

    /// Build the window. The caller shows it and owns it.
    ///
    /// No role parameter: an about box is about the application, not about one
    /// of the two roles it plays, which is why the coordinator keys it on
    /// nothing but its kind.
    static func make() -> NSWindow {
        // OK closes the window hosting this view — which does not exist yet, so
        // the closure asks for it when pressed rather than capturing it. Weakly,
        // or the window would keep itself alive through its own content view.
        let hosting = NSHostingController(rootView: AboutView(dismiss: {}))
        hosting.rootView = AboutView(dismiss: { [weak hosting] in
            hosting?.view.window?.performClose(nil)
        })

        let window = NSWindow(contentViewController: hosting)
        window.title = "About \(Role.terminal.displayName)"
        // No minimise: an about box is answered, not parked.
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
