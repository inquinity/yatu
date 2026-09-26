//
//  MenuModel.swift
//  YatuKit
//
//  What the extension's ⌥-click menu contains, as data.
//
//  Built here rather than in the extension so it can be tested without Finder,
//  without a menu, and without a running extension host. The extension turns
//  these descriptors into NSMenuItems and nothing else.
//
//  The menu deliberately cannot show which app is currently chosen: a sandboxed
//  extension cannot read the app's preferences, and Yatu does not use an app
//  group (docs/ROADMAP.md §9.1). The wording carries what a checkmark would —
//  "Set default terminal program" says these items set something, they do not
//  open anything.
//

import Foundation
import YatuUpstream

public enum MenuModel {

    public struct Item: Equatable {
        public enum Kind: Equatable {
            /// A disabled caption introducing the items below it.
            case header
            case separator
            /// Choosing this makes the app the role's default.
            case setDefault(SupportedApps)
            /// Choosing this opens the selection in that editor, once.
            case sendToEditor(SupportedApps)
            case settings
            case about
        }

        public let title: String
        public let kind: Kind
        /// Where the app was found, for the icon. Nil for headers and separators.
        public let applicationURL: URL?

        public init(title: String, kind: Kind, applicationURL: URL? = nil) {
            self.title = title
            self.kind = kind
            self.applicationURL = applicationURL
        }

        public var isEnabled: Bool {
            switch kind {
            case .header, .separator: return false
            default: return true
            }
        }
    }

    /// The menu for a role, given what is installed.
    ///
    /// `installed` is passed in rather than looked up so this stays pure: the
    /// extension resolves the catalog once, caches it, and hands the answer
    /// here. Nothing in this function touches the filesystem.
    public static func items(for role: Role,
                             installedTerminals: [(SupportedApps, URL)],
                             installedEditors: [(SupportedApps, URL)]) -> [Item] {
        var items: [Item] = []

        if !installedTerminals.isEmpty {
            items.append(Item(title: "Set default terminal program", kind: .header))
            for (app, location) in installedTerminals {
                items.append(Item(title: app.name, kind: .setDefault(app), applicationURL: location))
            }
        }

        if !installedEditors.isEmpty {
            if !items.isEmpty { items.append(Item(title: "", kind: .separator)) }
            items.append(Item(title: "Send to editor", kind: .header))
            for (app, location) in installedEditors {
                items.append(Item(title: app.name, kind: .sendToEditor(app), applicationURL: location))
            }
        }

        if !items.isEmpty { items.append(Item(title: "", kind: .separator)) }
        items.append(Item(title: "Settings…", kind: .settings))
        // "About Yatu" rather than "About": the menu belongs to Finder's
        // toolbar, not to Yatu's own menu bar, so the app has to name itself.
        items.append(Item(title: "About \(Role.terminal.displayName)", kind: .about))
        return items
    }

    /// The request a chosen item stands for, or nil if it is not choosable.
    ///
    /// The Finder coordinates are passed in because only the extension knows
    /// them at the moment of the click. Note the asymmetry, which is deliberate:
    /// a terminal item **sets the default** and opens nothing, while an editor
    /// item **opens once** and changes nothing.
    public static func request(for descriptor: Item,
                               role: Role,
                               selection: [URL],
                               container: URL?) -> HandOff.Request? {
        switch descriptor.kind {
        case let .setDefault(app):
            // The role comes from the app, not from the caller. Pairing the
            // caller's role with the descriptor's app can emit a request the
            // app's allowlist then rejects -- and a rejected request is a menu
            // item that silently does nothing, which is the failure this path
            // has already produced twice.
            return .setDefault(role: Role(owning: app.type), app: app)
        case let .sendToEditor(app):
            return .open(role: Role(owning: app.type), app: app,
                         items: selection, container: container)
        case .settings:
            return .settings(role: role)
        case .about:
            return .about(role: role)
        case .header, .separator:
            return nil
        }
    }
}
