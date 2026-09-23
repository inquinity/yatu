//
//  main.swift
//  YatuFinderSync — Yatu's Finder toolbar button.
//
//  This extension reports what Finder is showing and stops. It resolves no
//  targets, applies no rules, launches nothing and executes nothing; the app
//  does all of that, with the rules in YatuKit that are already tested. That
//  division is deliberate: upstream's extension runs an installed AppleScript,
//  which is where finding F1 lives, and nothing here can reach that shape.
//
//  It exists because a plain application dragged into Finder's toolbar is drawn
//  as its app icon, which cannot be a template, is restyled by the four icon
//  styles and is desaturated in an inactive window. An extension supplies a
//  template image the system tints. See docs/FINDER-TOOLBAR-ICONS.md §6.
//
//  Behaviour, settled by prototype (§6.7 of the same document):
//    click    performs the action
//    ⌥ click  opens the menu
//  Both arrive at menu(for:), which the system calls on the click itself.
//

import AppKit
import FinderSync
import YatuKit
import YatuUpstream

@objc(YatuFinderSync)
final class YatuFinderSync: FIFinderSync {

    /// This extension is the terminal button. The editor role is reached from
    /// its menu rather than from a second toolbar item.
    private let role = Role.terminal

    override init() {
        super.init()
        // targetedURL() answers nothing for a folder the extension does not
        // observe, and "open a terminal here" has to work anywhere.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        InstalledApps.shared.refresh()
    }

    // MARK: - The toolbar item

    override var toolbarItemName: String { "Yatu" }
    override var toolbarItemToolTip: String { "Open a terminal here — ⌥ for options" }

    override var toolbarItemImage: NSImage { ToolbarGlyph.image }

    // MARK: - The click

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .toolbarItemMenu else { return nil }

        let controller = FIFinderSyncController.default()
        // Report the whole selection and decide nothing.
        //
        // This used to collapse a multiple selection to nil right here, before
        // the role was known, on the grounds that a terminal opens at exactly
        // one place. That is true of the terminal and false of the editor,
        // which is handed everything you selected -- so "Send to editor" with
        // three files selected sent the folder instead of the files. The rule
        // is per-role, it already exists in FinderTarget.resolve, and this is
        // the wrong side of the boundary to apply it: the extension's whole job
        // is to report what Finder shows.
        let selection = Array((controller.selectedItemURLs() ?? []).prefix(HandOff.maximumItems))
        let container = controller.targetedURL()

        Log.finder.info(
            "toolbar click: \(selection.count) selected, container \(container == nil ? "none" : "resolved", privacy: .public)")

        guard NSEvent.modifierFlags.contains(.option) else {
            send(.open(role: role, app: nil, items: selection, container: container))
            return nil          // no menu: one click, one action
        }

        return optionMenu(selection: selection, container: container)
    }

    /// What each menu item in the menu currently on screen stands for, indexed
    /// by the item's tag. Rebuilt every time the menu is built; a menu is modal
    /// and there is only ever one, so there is nothing to race with.
    private var pending: [Choice] = []

    private func optionMenu(selection: [URL], container: URL?) -> NSMenu {
        let installed = InstalledApps.shared.current()
        let built = MenuBuilder.build(
            items: MenuModel.items(for: role,
                                   installedTerminals: installed.terminals,
                                   installedEditors: installed.editors),
            action: #selector(chose(_:)),
            image: { InstalledApps.shared.icon(for: $0) })

        // The tags MenuBuilder assigned index into this, in the same order.
        pending = built.actionable.map {
            Choice(descriptor: $0, selection: selection, container: container)
        }
        return built.menu
    }

    /// What a menu item stands for, carried until the user picks it.
    private final class Choice: NSObject {
        let descriptor: MenuModel.Item
        let selection: [URL]
        let container: URL?
        init(descriptor: MenuModel.Item, selection: [URL], container: URL?) {
            self.descriptor = descriptor
            self.selection = selection
            self.container = container
        }
    }

    @objc func chose(_ sender: NSMenuItem) {
        // The extension logged nothing at all until 2026-09-23, which made a
        // menu item that quietly did nothing almost impossible to diagnose:
        // every `guard ... else { return }` below is a silent failure, and the
        // app never hears about it because no URL is sent.
        guard pending.indices.contains(sender.tag) else {
            Log.launch.error(
                "menu item '\(sender.title, privacy: .public)' has tag \(sender.tag) with \(self.pending.count) pending")
            return
        }
        let choice = pending[sender.tag]
        guard let request = MenuModel.request(for: choice.descriptor, role: role,
                                              selection: choice.selection, container: choice.container)
        else {
            Log.launch.error("no request for menu item '\(sender.title, privacy: .public)'")
            return
        }
        Log.launch.info("chose '\(sender.title, privacy: .public)'")
        send(request)
    }

    /// Hand off and return. menu(for:) is synchronous and Finder waits on it,
    /// so launching the app on this thread left an empty menu frame drawn while
    /// it waited.
    private func send(_ request: HandOff.Request) {
        guard let url = HandOff.url(for: request) else {
            Log.launch.error("could not build a URL for \(String(describing: request), privacy: .public)")
            return
        }
        // Host and role only: the query carries filesystem paths (rule 6).
        Log.launch.info("handing off yatu://\(url.host() ?? "?", privacy: .public)")
        DispatchQueue.global(qos: .userInitiated).async {
            let opened = NSWorkspace.shared.open(url)
            if !opened {
                Log.launch.error("NSWorkspace refused to open the yatu:// URL")
            }
        }
    }
}

@_silgen_name("NSExtensionMain") func NSExtensionMain() -> Int32
exit(NSExtensionMain())
