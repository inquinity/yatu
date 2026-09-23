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
        // One selected item names a place; several do not, so the container
        // wins. The same rule the app applies, and the reason it is applied
        // here too is that only the extension can see the selection.
        let selection = controller.selectedItemURLs() ?? []
        let item = selection.count == 1 ? selection[0] : nil
        let container = controller.targetedURL()

        guard NSEvent.modifierFlags.contains(.option) else {
            send(.open(role: role, app: nil, item: item, container: container))
            return nil          // no menu: one click, one action
        }

        return optionMenu(item: item, container: container)
    }

    private func optionMenu(item: URL?, container: URL?) -> NSMenu {
        let installed = InstalledApps.shared.current()
        let menu = NSMenu(title: "Yatu")
        menu.autoenablesItems = false

        for descriptor in MenuModel.items(for: role,
                                          installedTerminals: installed.terminals,
                                          installedEditors: installed.editors) {
            switch descriptor.kind {
            case .separator:
                menu.addItem(.separator())
            case .header:
                let header = NSMenuItem(title: descriptor.title, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            default:
                let menuItem = NSMenuItem(title: descriptor.title,
                                          action: #selector(chose(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.isEnabled = true
                menuItem.indentationLevel = 0
                menuItem.image = descriptor.applicationURL.flatMap { InstalledApps.shared.icon(for: $0) }
                menuItem.representedObject = Choice(descriptor: descriptor, item: item, container: container)
                menu.addItem(menuItem)
            }
        }
        return menu
    }

    /// What a menu item stands for, carried until the user picks it.
    private final class Choice: NSObject {
        let descriptor: MenuModel.Item
        let item: URL?
        let container: URL?
        init(descriptor: MenuModel.Item, item: URL?, container: URL?) {
            self.descriptor = descriptor
            self.item = item
            self.container = container
        }
    }

    @objc private func chose(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? Choice,
              let request = MenuModel.request(for: choice.descriptor, role: role,
                                              selection: choice.item, container: choice.container)
        else { return }
        send(request)
    }

    /// Hand off and return. menu(for:) is synchronous and Finder waits on it,
    /// so launching the app on this thread left an empty menu frame drawn while
    /// it waited.
    private func send(_ request: HandOff.Request) {
        guard let url = HandOff.url(for: request) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.open(url)
        }
    }
}

@_silgen_name("NSExtensionMain") func NSExtensionMain() -> Int32
exit(NSExtensionMain())
