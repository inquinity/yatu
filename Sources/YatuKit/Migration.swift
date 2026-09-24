//
//  Migration.swift
//  YatuKit
//
//  Adopting a choice already made in OpenInTerminal-Lite or OpenInEditor-Lite.
//
//  Yatu replaces a toolbar button people have been clicking for years. Someone
//  who already told OpenInTerminal-Lite to use iTerm should not have to tell
//  Yatu the same thing, and should certainly not be met by a settings window on
//  first click. This reads the old choice once and adopts it.
//
//  ## Rules
//
//  * **Never overwrite.** A role Yatu already has a setting for is left alone,
//    so this is safe to run on every launch and cannot undo a later change.
//  * **Validated, not trusted.** The old value goes through `Settings`, which
//    checks it against the catalog for that role. A foreign preference domain
//    is input like any other — anyone who can write it could otherwise choose
//    what Yatu launches, which is finding L1 wearing a different coat.
//  * **Read-only, and leaves nothing behind.** `CFPreferencesCopyAppValue`
//    reads another application's domain without creating one. `UserDefaults(suiteName:)`
//    would register a domain as a side effect of asking, which is exactly the
//    hygiene this app is supposed to keep.
//  * **The old app is not touched.** Its preferences stay where they are, so
//    both can be installed at once and OpenInTerminal-Lite keeps working. That
//    matters: the old cask is deliberately staying in the tap for older Macs.
//

import Foundation
import YatuUpstream

public enum Migration {

    /// Where a predecessor stored its choice.
    struct LegacyChoice {
        let role: Role
        let domain: String
        let key: String
        /// For the log, and for the person reading it later.
        let application: String
    }

    static let legacyChoices = [
        LegacyChoice(role: .terminal,
                     domain: "wang.jianing.app.OpenInTerminal-Lite",
                     key: "LiteDefaultTerminal",
                     application: "OpenInTerminal-Lite"),
        LegacyChoice(role: .editor,
                     domain: "wang.jianing.app.OpenInEditor-Lite",
                     key: "LiteDefaultEditor",
                     application: "OpenInEditor-Lite"),
    ]

    /// Read a value from another application's preference domain.
    ///
    /// Read-only by construction: this cannot create the domain, unlike
    /// `UserDefaults(suiteName:)`.
    public static func readLegacyValue(domain: String, key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
    }

    /// Adopt any predecessor choice Yatu does not already have one for.
    ///
    /// - Parameter read: injected so the suite never touches a real domain.
    /// - Returns: what was adopted, for the caller to report or test.
    @discardableResult
    public static func adoptLegacyChoices(
        into settings: Settings,
        read: (String, String) -> String? = readLegacyValue) -> [Role: SupportedApps]
    {
        var adopted: [Role: SupportedApps] = [:]

        for legacy in legacyChoices {
            // Never overwrite a choice Yatu already has.
            guard settings.chosenApp(for: legacy.role) == nil else { continue }
            guard let stored = read(legacy.domain, legacy.key), !stored.isEmpty else { continue }

            guard let app = Catalog.app(named: stored, for: legacy.role) else {
                // Upstream allowed an empty or stale value here (finding L5);
                // it must not become Yatu's problem.
                Log.settings.notice(
                    "ignored \(legacy.application, privacy: .public)'s \(legacy.role.rawValue, privacy: .public) choice: not in the catalog")
                continue
            }

            guard settings.setChosenApp(app, for: legacy.role) else { continue }
            adopted[legacy.role] = app
            Log.settings.notice(
                "adopted \(legacy.role.rawValue, privacy: .public) default \(app.name, privacy: .public) from \(legacy.application, privacy: .public)")
        }
        return adopted
    }
}
