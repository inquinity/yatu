//
//  HandOff.swift
//  YatuKit
//
//  The contract between the Finder extension and the app.
//
//  The extension is sandboxed and deliberately knows nothing: it reports what
//  Finder is showing and what the user asked for, then stops. The app — which
//  owns the rules, the catalog and the preferences — decides what that means.
//  This file is the only thing both sides share, so it is the only place the
//  wire format is written down.
//
//  It is also an entry point anything on the machine can reach: a URL scheme is
//  public, and a web page can invoke `yatu://…` as easily as the extension can.
//  So parsing is strict — an unknown host, an unknown role or a missing field
//  is rejected rather than guessed at — and nothing here trusts a path. The
//  paths go on to `FinderTarget`, which applies the same rules it applies to
//  Finder's own answers.
//

import Foundation
import YatuUpstream

public enum HandOff {

    /// The scheme the app registers and the extension opens.
    public static let scheme = "yatu"

    /// The most selected items one request may carry.
    ///
    /// The editor role is handed everything you selected, so this is a list and
    /// not a single path. It is also a public entry point, so it is a *bounded*
    /// list: without a cap, anything on the machine could hand the app an
    /// arbitrarily long URL to parse and an arbitrarily long argument vector to
    /// launch an application with. Selecting more than this in Finder and
    /// sending it to an editor is not a real workflow; being handed 100,000
    /// paths by a web page is a real attack.
    public static let maximumItems = 64

    /// What the extension is asking the app to do.
    public enum Request: Equatable {
        /// Open at whatever these Finder coordinates mean. `app` nil means the
        /// role's stored default — a plain toolbar click. A named app is a
        /// one-off from the menu ("Send to editor → …") and does not change
        /// what is stored.
        case open(role: Role, app: SupportedApps?, items: [URL], container: URL?)
        /// Make this catalog entry the role's default. The app owns preferences.
        case setDefault(role: Role, app: SupportedApps)
        /// Show the settings window.
        case settings(role: Role)
        /// Show the about window.
        case about(role: Role)
    }

    // MARK: - Building (the extension's side)

    public static func url(for request: Request) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        var items: [URLQueryItem] = []

        switch request {
        case let .open(role, app, selected, container):
            components.host = "open"
            items.append(URLQueryItem(name: "role", value: role.rawValue))
            if let app { items.append(URLQueryItem(name: "app", value: app.name)) }
            // Repeated `item=` parameters, in selection order. The order is not
            // meaningful — the rules never pick a "first" — but preserving it
            // keeps the round trip exact and the tests readable.
            for item in selected.prefix(maximumItems) {
                items.append(URLQueryItem(name: "item", value: item.path))
            }
            if let container { items.append(URLQueryItem(name: "container", value: container.path)) }
        case let .setDefault(role, app):
            components.host = "set-default"
            items.append(URLQueryItem(name: "role", value: role.rawValue))
            items.append(URLQueryItem(name: "app", value: app.name))
        case let .settings(role):
            components.host = "settings"
            items.append(URLQueryItem(name: "role", value: role.rawValue))
        case let .about(role):
            components.host = "about"
            items.append(URLQueryItem(name: "role", value: role.rawValue))
        }

        components.queryItems = items
        return components.url
    }

    // MARK: - Parsing (the app's side)

    /// Returns nil for anything that is not a request this app understands.
    ///
    /// Deliberately total and deliberately narrow: every field is checked, and
    /// an app name is resolved through the catalog for that role — the same
    /// allowlist `Settings` uses — so a crafted URL cannot name an arbitrary
    /// application any more than a crafted preference can (finding L1).
    public static func request(from url: URL) -> Request? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host
        else { return nil }

        let query = components.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let found = query.first(where: { $0.name == name })?.value, !found.isEmpty
            else { return nil }
            return found
        }
        func values(_ name: String) -> [String] {
            query.filter { $0.name == name }.compactMap(\.value).filter { !$0.isEmpty }
        }

        guard let roleName = value("role"), let role = Role(rawValue: roleName) else { return nil }

        switch host {
        case "open":
            // A path is data, not a promise: it is turned into a file URL here
            // and judged by FinderTarget's rules later.
            let paths = values("item")
            // Too many is refused outright rather than truncated. Truncating
            // would silently act on part of what was asked for, and the only
            // sender that can exceed the cap is not the extension.
            guard paths.count <= maximumItems else { return nil }
            let selected = paths.map { URL(fileURLWithPath: $0) }
            let container = value("container").map { URL(fileURLWithPath: $0) }
            // Carrying neither is legitimate and means "I could not resolve
            // anything — you ask Finder". This used to be refused, and the
            // refusal was a bug: in an iCloud Drive window
            // FIFinderSyncController.targetedURL() returns nil, so the
            // extension had nothing to send, and the app rejected its own
            // extension's request as unrecognised. The button did nothing.
            //
            // It is not a widening of what a caller can reach: a request that
            // names no path is strictly less capable than one that names any.
            // An app may be named, but only one from this role's catalog. A URL
            // naming anything else is rejected outright rather than ignored.
            var app: SupportedApps?
            if let requested = value("app") {
                guard let allowed = Catalog.app(named: requested, for: role) else { return nil }
                app = allowed
            }
            return .open(role: role, app: app, items: selected, container: container)

        case "set-default":
            guard let name = value("app"), let app = Catalog.app(named: name, for: role)
            else { return nil }
            return .setDefault(role: role, app: app)

        case "settings":
            return .settings(role: role)

        case "about":
            return .about(role: role)

        default:
            return nil
        }
    }
}
