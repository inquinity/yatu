//
//  Version.swift
//  YatuKit
//
//  Version values come from the bundle at runtime, and from the VERSION file at
//  build time (bin/ver reads it, bin/build.sh stamps it). A binary run outside a
//  bundle — a unit test, or the executable straight out of .build — reports
//  "0.0.0-dev" rather than guessing.
//

import Foundation

public enum Version {

    /// CFBundleShortVersionString, e.g. "1.0.0".
    public static let short: String =
        bundleValue("CFBundleShortVersionString") ?? "0.0.0-dev"

    /// CFBundleVersion, e.g. "1".
    public static let build: String =
        bundleValue("CFBundleVersion") ?? "0"

    /// The commit bin/build.sh stamped into the bundle, when there is one.
    public static var buildCommit: String? { bundleValue("YatuBuildCommit") }

    /// The OpenInTerminal-Lite version this build is based on.
    public static var upstreamVersion: String? { bundleValue("YatuUpstreamVersion") }

    private static func bundleValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
