//
//  Settings.swift
//  YatuKit
//
//  The chosen application, per role.
//
//  What is stored is a catalog *name* and nothing else. It is validated against
//  the catalog for that role on every read, so a tampered or stale preferences
//  file can only ever produce "no choice yet" — never a path, never an
//  arbitrary application, never an editor in the terminal's slot (finding L1).
//

import Foundation
import YatuUpstream

/// The little of `UserDefaults` this needs, so tests never touch a real
/// preferences domain. Running the suite against `UserDefaults(suiteName:)`
/// leaves an empty plist behind for every suite it creates, which is precisely
/// the hygiene this app is supposed to keep.
public protocol PreferenceStore {
    func stringValue(forKey key: String) -> String?
    func setStringValue(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
}

extension UserDefaults: PreferenceStore {
    public func stringValue(forKey key: String) -> String? { string(forKey: key) }
    public func setStringValue(_ value: String, forKey key: String) { set(value, forKey: key) }
    public func removeValue(forKey key: String) { removeObject(forKey: key) }
}

public struct Settings {

    private let store: PreferenceStore

    public init(store: PreferenceStore = UserDefaults.standard) {
        self.store = store
    }

    /// The chosen app for this role, or nil if nothing valid is stored.
    public func chosenApp(for role: Role) -> SupportedApps? {
        guard let stored = store.stringValue(forKey: role.preferenceKey) else { return nil }
        guard let app = Catalog.app(named: stored, for: role) else {
            // Not a silent drop: this is what a tampered domain looks like.
            Log.settings.error("stored \(role.preferenceKey, privacy: .public) is not in the catalog; ignoring it")
            return nil
        }
        return app
    }

    /// Record a choice. Only a catalog entry for this role can be stored.
    @discardableResult
    public func setChosenApp(_ app: SupportedApps, for role: Role) -> Bool {
        guard Catalog.app(named: app.name, for: role) != nil else {
            Log.settings.error("refused to store \(app.name, privacy: .public) for \(role.rawValue, privacy: .public)")
            return false
        }
        store.setStringValue(app.name, forKey: role.preferenceKey)
        return true
    }

    public func clearChosenApp(for role: Role) {
        store.removeValue(forKey: role.preferenceKey)
    }
}
