//
//  FinderTarget.swift
//  YatuKit
//
//  What Finder is pointing at, and what we are willing to hand onward.
//
//  Two jobs, deliberately separated so the policy can be tested without a
//  running Finder: `FinderScriptingQuery` does the ScriptingBridge I/O, and the
//  static members below decide what the answer means.
//
//  Rules 3 and 4 (docs/YATU-PLAN.md §4.1).
//

import Foundation
import YatuUpstream
#if canImport(ScriptingBridge)
import ScriptingBridge
#endif

/// The Finder query, behind a protocol so tests can supply an answer.
public protocol FinderQuerying {
    /// URLs of the items selected in the frontmost Finder window.
    func selectedItems() -> [URL]
    /// The folder the frontmost Finder window is showing, if any.
    func frontWindowTarget() -> URL?
}

public enum FinderTarget {

    /// Rule 4: no Finder window, or a view with no filesystem target, means the
    /// Desktop — built with `URL(fileURLWithPath:)`, never parsed from a string.
    public static var desktop: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    }

    /// Rule 3, terminal role: the result is always an existing directory.
    ///
    /// A file yields its parent. A symlink is resolved first, so a symlink *to*
    /// a file is a file. An `.app` bundle is a directory as far as the
    /// filesystem is concerned, and is treated as a file anyway: a terminal
    /// opened inside an application bundle is never what was meant, and handing
    /// one onward is how an "open here" becomes an "execute this".
    public static func directory(for url: URL,
                                 fileManager: FileManager = .default) -> URL? {
        let resolved = URL(fileURLWithPath: url.path).resolvingSymlinksInPath()

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
            return nil
        }
        if !isDirectory.boolValue || isApplicationBundle(resolved) {
            let parent = resolved.deletingLastPathComponent()
            // Guard against a target at the filesystem root resolving to itself.
            return parent.path.isEmpty ? nil : parent
        }
        return resolved
    }

    /// Rule 3, editor role: files are the point, but never an application
    /// bundle and never something the system would execute.
    public static func editableItems(from urls: [URL],
                                     fileManager: FileManager = .default) -> [URL] {
        urls.compactMap { url in
            let resolved = URL(fileURLWithPath: url.path).resolvingSymlinksInPath()

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
                return nil
            }
            if isApplicationBundle(resolved) { return nil }
            // An executable file handed to an "editor" is the shape of finding
            // F1: whatever opens it may run it instead.
            if !isDirectory.boolValue, fileManager.isExecutableFile(atPath: resolved.path) {
                return nil
            }
            return resolved
        }
    }

    /// Bundles macOS will launch rather than browse.
    static func isApplicationBundle(_ url: URL) -> Bool {
        ["app", "command"].contains(url.pathExtension.lowercased())
    }

    /// What this role should be given, or the Desktop if Finder offers nothing.
    public static func resolve(for role: Role,
                               using query: FinderQuerying,
                               fileManager: FileManager = .default) -> [URL] {
        let selection = query.selectedItems()

        switch role {
        case .terminal:
            // A selected item names a place; the window's target is the fallback.
            let candidate = selection.first ?? query.frontWindowTarget()
            guard let candidate,
                  let directory = directory(for: candidate, fileManager: fileManager) else {
                Log.finder.info("no usable Finder target; using the Desktop")
                return [desktop]
            }
            return [directory]

        case .editor:
            let items = editableItems(from: selection, fileManager: fileManager)
            if !items.isEmpty { return items }
            // Nothing openable selected: fall back to the folder being viewed.
            if let target = query.frontWindowTarget(),
               let directory = directory(for: target, fileManager: fileManager) {
                return [directory]
            }
            Log.finder.info("no usable Finder selection; using the Desktop")
            return [desktop]
        }
    }
}

// MARK: - The real query

/// Asks Finder, without a force-cast anywhere.
///
/// Upstream's equivalent force-unwrapped the application, then force-cast the
/// selection to `Array<AnyObject>` and each element to `FinderItem`. Recents,
/// AirDrop and search results do not answer with what that expects, and the app
/// crashed rather than falling back (finding L3).
public struct FinderScriptingQuery: FinderQuerying {

    private static let finderBundleIdentifier = "com.apple.finder"

    public init() {}

    #if canImport(ScriptingBridge)
    private var finder: FinderApplication? {
        guard let application = SBApplication(bundleIdentifier: Self.finderBundleIdentifier) else {
            Log.finder.error("Finder is not scriptable from here")
            return nil
        }
        return application as FinderApplication
    }

    public func selectedItems() -> [URL] {
        guard let finder, let selection = finder.selection, let contents = selection.get() else {
            return []
        }
        // `get()` answers with whatever the current view has. Only an array of
        // items is usable; anything else means "no selection we understand".
        guard let objects = contents as? [AnyObject] else {
            Log.finder.debug("Finder selection was not a list of items")
            return []
        }
        return objects.compactMap(Self.url(of:))
    }

    public func frontWindowTarget() -> URL? {
        guard let finder, let windows = finder.FinderWindows?() else { return nil }
        guard let first = windows.firstObject as? SBObject,
              let window = first as FinderFinderWindow?,
              let target = window.target?.get() as AnyObject? else {
            return nil
        }
        return Self.url(of: target)
    }

    /// A Finder item's `URL` property is a percent-encoded file URL string.
    /// Parsing can fail; upstream force-cast and then force-unwrapped it.
    private static func url(of object: AnyObject) -> URL? {
        guard let item = object as? FinderItem,
              let string = item.URL,
              let url = URL(string: string),
              url.isFileURL else {
            return nil
        }
        return url
    }
    #else
    public func selectedItems() -> [URL] { [] }
    public func frontWindowTarget() -> URL? { nil }
    #endif
}
