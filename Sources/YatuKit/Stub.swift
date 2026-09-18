//
//  Stub.swift
//  YatuKit
//
//  M1 placeholder. The real entry points arrive in M2b; this exists so that M1's
//  identity work has a bundle to verify against — an app you can double-click,
//  inspect with plutil, and watch NOT create a preferences domain.
//
//  Delete this file when Launcher and SettingsWindow land.
//

import Foundation
import os

public enum Stub {

    private static let log = Logger(subsystem: "com.altmansoftwaredesign.yatu", category: "stub")

    /// Handle the arguments M1 can honestly answer, then exit.
    public static func run(role: Role) -> Never {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--version") {
            print("\(role.displayName) \(Version.short) (\(Version.build))")
            exit(0)
        }

        if arguments.contains("--identity") {
            print("role:       \(role.rawValue)")
            print("name:       \(role.displayName)")
            print("bundle id:  \(role.bundleIdentifier)")
            print("catalog:    \(Catalog.apps(for: role).count) apps")
            exit(0)
        }

        // Launched with no arguments — from Finder's toolbar, or by double-click.
        // There is nothing to do yet, and doing nothing silently is the correct
        // behaviour for a stub: it must not touch preferences or launch anything.
        log.info("\(role.displayName, privacy: .public) stub launched; no behaviour until M2b")
        FileHandle.standardError.write(
            Data("\(role.displayName) \(Version.short) — not yet implemented (M1 stub)\n".utf8))
        exit(0)
    }
}
