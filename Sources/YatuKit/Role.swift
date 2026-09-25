//
//  Role.swift
//  YatuKit
//
//  Yatu ships one app that plays two roles. A click on the toolbar button opens
//  a terminal; the button's menu carries Send to editor. There used to be a
//  second executable, "Yatu Edit", for the editor role; it was retired on
//  2026-09-23 when the Finder extension made it unnecessary (plan M6a).
//  See docs/ROADMAP.md §4.1 and §9.
//

import Foundation
import YatuUpstream

public enum Role: String, CaseIterable, Sendable {
    /// Opens the folder you are looking at in a terminal. Ships in 1.0.
    case terminal
    /// Opens the items you have selected in an editor. Reached from the Finder
    /// button's menu, not from an app of its own.
    case editor

    /// The bundle identifier associated with this role.
    ///
    /// `.terminal` is the shipping app, and this literal is what
    /// `bin/build.sh` stamps into its Info.plist — a mismatch between the two
    /// is a build error worth catching in tests. `.editor` no longer names a
    /// bundle that exists: it is kept as the role's stable identity, used in
    /// `--identity` output and in the preference domain, and it is the id the
    /// retired "Yatu Edit" app would have had.
    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.altmansoftwaredesign.yatu"
        case .editor:   return "com.altmansoftwaredesign.yatu.editor"
        }
    }

    /// The user-visible app name.
    public var displayName: String {
        switch self {
        case .terminal: return "Yatu"
        case .editor:   return "Yatu Edit"
        }
    }

    /// The preference key holding the chosen app for this role.
    public var preferenceKey: String {
        switch self {
        case .terminal: return "terminal"
        case .editor:   return "editor"
        }
    }

    /// The role that owns this kind of application.
    ///
    /// The inverse of `appType`, and the reason it exists: a request that names
    /// an app must name the role whose catalog contains it, or the app's own
    /// allowlist will reject it on arrival. Deriving the role from the app
    /// makes that impossible to get wrong, rather than merely unlikely.
    public init(owning appType: AppType) {
        switch appType {
        case .terminal: self = .terminal
        case .editor:   self = .editor
        }
    }

    /// The upstream catalog type this role draws from.
    public var appType: AppType {
        switch self {
        case .terminal: return .terminal
        case .editor:   return .editor
        }
    }
}
