//
//  Catalog.swift
//  YatuKit
//
//  A role-filtered view of `SupportedApps`, the list of apps Yatu can open.
//

import Foundation

public enum Catalog {

    /// Every app we support for this role, in catalog order.
    public static func apps(for role: Role) -> [SupportedApps] {
        switch role {
        case .terminal: return SupportedApps.terminals
        case .editor:   return SupportedApps.editors
        }
    }

    /// Resolve a stored preference value to a catalog entry.
    ///
    /// Returns nil for anything not in the catalog for this role — which is the
    /// allowlist that closes finding L1: a tampered preference naming a path,
    /// an arbitrary app, or an editor in the terminal's slot resolves to
    /// nothing rather than to something launchable.
    public static func app(named name: String, for role: Role) -> SupportedApps? {
        guard let candidate = SupportedApps.from(name: name) else { return nil }
        guard candidate.type == role.appType else { return nil }
        return candidate
    }
}
