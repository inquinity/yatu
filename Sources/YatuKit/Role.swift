//
//  Role.swift
//  YatuKit
//
//  Yatu ships one codebase and two executables, differing only in the role they
//  ask the shared code for. See docs/YATU-PLAN.md §4.1.
//

import Foundation
import YatuUpstream

public enum Role: String, CaseIterable, Sendable {
    /// Opens the folder you are looking at in a terminal. Ships in 1.0.
    case terminal
    /// Opens the items you have selected in an editor. Built and tested, not shipped in 1.0.
    case editor

    /// The bundle identifier of the app that plays this role.
    ///
    /// These are literals rather than a lookup of the running bundle: the value
    /// is also what `bin/build.sh` stamps into Info.plist, and a mismatch
    /// between the two is a build error worth catching in tests.
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

    /// The upstream catalog type this role draws from.
    public var appType: AppType {
        switch self {
        case .terminal: return .terminal
        case .editor:   return .editor
        }
    }
}
