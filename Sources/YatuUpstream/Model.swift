//
//  Model.swift
//  YatuUpstream
//
//  Provenance: this is the dependency-free half of upstream's
//  OpenInTerminalCore/App.swift (Jianing Wang, 2020, MIT) — the `AppType` and
//  `App` declarations, copied verbatim apart from this header.
//
//  It is NOT a copy made for convenience. `SupportedApps.swift` next to it is
//  compiled unchanged and refers to `App` and `AppType` by name, so those types
//  must exist in the same module. Upstream's own App.swift cannot supply them:
//  its `Openable` extension reaches FinderManager, DefaultsManager,
//  ScriptManager, Constants, OITError and logw — that is, the whole of
//  OpenInTerminalCore, including the three pieces Yatu exists to replace
//  (findings L1, L2 and L3 in docs/ROADMAP.md §3).
//
//  Keep this file in step with upstream's declarations on sync. It deliberately
//  carries no behaviour; launching lives in YatuKit.
//

import Foundation

public enum AppType: String, Codable {
    case terminal
    case editor
}

public struct App: Codable {
    public var name: String
    public var path: String?
    public var bundleId: String?
    public var type: AppType

    public init(name: String, type: AppType) {
        self.name = name
        self.type = type
    }
}

extension App: Equatable {
    public static func == (lhs: App, rhs: App) -> Bool {
        return lhs.name == rhs.name && lhs.bundleId == rhs.bundleId
    }
}
