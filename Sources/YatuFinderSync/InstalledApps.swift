//
//  InstalledApps.swift
//  YatuFinderSync
//
//  Which catalog entries are installed, and their icons, prepared before any
//  click. `menu(for:)` is synchronous and Finder waits on it, so nothing slow
//  may happen there: resolving thirteen bundle identifiers and decoding their
//  icons on the click made the first menu arrive late and reflow as rows
//  resized (docs/FINDER-TOOLBAR-ICONS.md §6.7).
//
//  Two things fix that, both learned by measuring rather than guessing:
//  icons are drawn into a bitmap here, because NSWorkspace hands back a lazily
//  decoded image whose first *draw* loads it; and the resolved list is written
//  to this extension's own cache directory, because Finder starts extensions on
//  demand and otherwise the first menu after every login pays full price.
//

import AppKit
import YatuKit
import YatuUpstream

final class InstalledApps {

    static let shared = InstalledApps()

    struct Snapshot {
        var terminals: [(SupportedApps, URL)] = []
        var editors: [(SupportedApps, URL)] = []
        var isEmpty: Bool { terminals.isEmpty && editors.isEmpty }
    }

    private let queue = DispatchQueue(label: "com.altmansoftwaredesign.yatu.installed")
    private var snapshot = Snapshot()
    private var icons: [String: NSImage] = [:]

    private init() {
        if let remembered = Self.loadRemembered() { snapshot = remembered }
    }

    /// The answer, resolving synchronously if nothing is known yet. One slow
    /// menu is better than a menu that is wrong or that reflows while open.
    func current() -> Snapshot {
        var result = queue.sync { snapshot }
        if result.isEmpty {
            result = Self.resolveNow()
            queue.sync { snapshot = result }
            Self.remember(result)
        }
        return result
    }

    func icon(for applicationURL: URL) -> NSImage? {
        if let cached = queue.sync(execute: { icons[applicationURL.path] }) { return cached }
        let rendered = Self.rasterise(NSWorkspace.shared.icon(forFile: applicationURL.path))
        queue.sync { icons[applicationURL.path] = rendered }
        return rendered
    }

    /// Refresh off the click path. Installing a terminal while Finder runs is
    /// rare, but the answer should not be wrong until the next login.
    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let fresh = Self.resolveNow()
            self.queue.sync { self.snapshot = fresh }
            Self.remember(fresh)
        }
    }

    // MARK: - Resolution

    private static func resolveNow() -> Snapshot {
        var snapshot = Snapshot()
        snapshot.terminals = Catalog.apps(for: .terminal).compactMap { app in
            Launcher.applicationURL(for: app).map { (app, $0) }
        }
        snapshot.editors = Catalog.apps(for: .editor).compactMap { app in
            Launcher.applicationURL(for: app).map { (app, $0) }
        }
        return snapshot
    }

    /// NSWorkspace's icon decodes lazily; drawing it once here moves that cost
    /// off the click and fixes the height of every row before the menu opens.
    private static func rasterise(_ icon: NSImage) -> NSImage {
        let side = 16
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side * 2, pixelsHigh: side * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return icon }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: side * 2, height: side * 2))
        NSGraphicsContext.restoreGraphicsState()
        let flattened = NSImage(size: NSSize(width: side, height: side))
        flattened.addRepresentation(rep)
        return flattened
    }

    // MARK: - Remembering between launches

    private static var cacheFile: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("installed-apps.json")
    }

    private static func remember(_ snapshot: Snapshot) {
        guard let cacheFile else { return }
        let payload = [
            "terminals": Dictionary(snapshot.terminals.map { ($0.0.name, $0.1.path) },
                                    uniquingKeysWith: { first, _ in first }),
            "editors": Dictionary(snapshot.editors.map { ($0.0.name, $0.1.path) },
                                  uniquingKeysWith: { first, _ in first }),
        ]
        try? JSONEncoder().encode(payload).write(to: cacheFile)
    }

    private static func loadRemembered() -> Snapshot? {
        guard let cacheFile, let data = try? Data(contentsOf: cacheFile),
              let stored = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return nil }

        // Remembered, not trusted: an entry still has to be a catalog case for
        // its role, and the bundle still has to be there.
        func revive(_ key: String, _ role: Role) -> [(SupportedApps, URL)] {
            (stored[key] ?? [:]).compactMap { name, path in
                guard let app = Catalog.app(named: name, for: role),
                      FileManager.default.fileExists(atPath: path) else { return nil }
                return (app, URL(fileURLWithPath: path))
            }
        }
        var snapshot = Snapshot()
        snapshot.terminals = revive("terminals", .terminal)
        snapshot.editors = revive("editors", .editor)
        return snapshot.isEmpty ? nil : snapshot
    }
}
