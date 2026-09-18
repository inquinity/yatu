//
//  Log.swift
//  YatuKit
//
//  Rule 6: no file logging, and paths are `.private`.
//
//  Upstream wrote every opened path to ~/Library/Logs/logfile-N.log, which is
//  world-readable, generically named, and forgeable line by line (finding L2).
//  os.Logger keeps the same diagnostics without any of that: entries go to the
//  unified log, and a path interpolated as `.private` is redacted unless
//  someone deliberately enables private data on this Mac.
//

import Foundation
import os

public enum Log {

    private static let subsystem = "com.altmansoftwaredesign.yatu"

    /// Resolving what Finder is pointing at.
    public static let finder = Logger(subsystem: subsystem, category: "finder")
    /// Choosing and launching the target application.
    public static let launch = Logger(subsystem: subsystem, category: "launch")
    /// Reading and writing the chosen app.
    public static let settings = Logger(subsystem: subsystem, category: "settings")
}
