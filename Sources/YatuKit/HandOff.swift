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

    /// What the extension is asking the app to do.
    public enum Request: Equatable {
        /// Open at whatever these Finder coordinates mean. `app` nil means the
        /// role's stored default — a plain toolbar click. A named app is a
        /// one-off from the menu ("Send to editor → …") and does not change
        /// what is stored.
        case open(role: Role, app: SupportedApps?, item: URL?, container: URL?)
        /// Make this catalog entry the role's default. The app owns preferences.
        case setDefault(role: Role, app: SupportedApps)
        /// Show the settings window.
        case settings(role: Role)
    }

    // MARK: - Building (the extension's side)

    public static func url(for request: Request) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        var items: [URLQueryItem] = []

        switch request {
        case let .open(role, app, item, container):
            components.host = "open"
            items.append(URLQueryItem(name: "role", value: role.rawValue))
            if let app { items.append(URLQueryItem(name: "app", value: app.name)) }
            if let item { items.append(URLQueryItem(name: "item", value: item.path)) }
            if let container { items.append(URLQueryItem(name: "container", value: container.path)) }
        case let .setDefault(role, app):
            components.host = "set-default"
            items.append(URLQueryItem(name: "role", value: role.rawValue))
            items.append(URLQueryItem(name: "app", value: app.name))
        case let .settings(role):
            components.host = "settings"
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

        guard let roleName = value("role"), let role = Role(rawValue: roleName) else { return nil }

        switch host {
        case "open":
            // A path is data, not a promise: it is turned into a file URL here
            // and judged by FinderTarget's rules later.
            let item = value("item").map { URL(fileURLWithPath: $0) }
            let container = value("container").map { URL(fileURLWithPath: $0) }
            guard item != nil || container != nil else { return nil }
            // An app may be named, but only one from this role's catalog. A URL
            // naming anything else is rejected outright rather than ignored.
            var app: SupportedApps?
            if let requested = value("app") {
                guard let allowed = Catalog.app(named: requested, for: role) else { return nil }
                app = allowed
            }
            return .open(role: role, app: app, item: item, container: container)

        case "set-default":
            guard let name = value("app"), let app = Catalog.app(named: name, for: role)
            else { return nil }
            return .setDefault(role: role, app: app)

        case "settings":
            return .settings(role: role)

        default:
            return nil
        }
    }
}
