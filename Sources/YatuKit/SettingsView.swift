//
//  SettingsView.swift
//  YatuKit
//
//  The feature OpenInTerminal-Lite does not have: a way to change your mind.
//  See docs/YATU-PLAN.md §5.
//
//  What it must not offer is a free-text command or application path. That is
//  finding L1, and the catalog is the fix: every row here is a `SupportedApps`
//  case, so choosing is picking from a list, never typing a path.
//

import AppKit
import SwiftUI
import YatuUpstream

/// One row: a catalog entry, and where it turned out to be (if anywhere).
struct CatalogRow: Identifiable {
    let app: SupportedApps
    let url: URL?
    var id: String { app.rawValue }
    var isInstalled: Bool { url != nil }

    var icon: NSImage? {
        guard let url else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

final class SettingsViewModel: ObservableObject {

    let role: Role
    @Published private(set) var chosen: SupportedApps?
    @Published private(set) var installed: [CatalogRow] = []
    @Published private(set) var missing: [CatalogRow] = []

    private let settings: Settings

    init(role: Role, settings: Settings = Settings()) {
        self.role = role
        self.settings = settings
        self.chosen = settings.chosenApp(for: role)
        reload()
    }

    func reload() {
        let rows = Catalog.apps(for: role).map {
            CatalogRow(app: $0, url: Launcher.applicationURL(for: $0))
        }
        installed = rows.filter(\.isInstalled)
        missing = rows.filter { !$0.isInstalled }
    }

    func choose(_ app: SupportedApps) {
        guard settings.setChosenApp(app, for: role) else { return }
        chosen = app
    }

    var chosenRow: CatalogRow? {
        installed.first { $0.app == chosen } ?? missing.first { $0.app == chosen }
    }

    /// §5: name the bundle that will actually launch, so what happens next is
    /// never a surprise.
    func revealChosenInFinder() {
        guard let url = chosenRow?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct SettingsView: View {

    @ObservedObject var model: SettingsViewModel

    var body: some View {
        // The footer sits outside the Form: the catalog scrolls, and the
        // version and source stay visible. §5 asks for them to be there, and
        // buried under a dozen uninstalled terminals is not there.
        VStack(spacing: 0) {
            catalogForm
            Divider()
            footer
        }
        .frame(width: 420, height: 520)
    }

    private var catalogForm: some View {
        Form {
            Section("Chosen") {
                if let row = model.chosenRow, let url = row.url {
                    LabeledContent(row.app.name) {
                        Button("Reveal in Finder") { model.revealChosenInFinder() }
                    }
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if let chosen = model.chosen {
                    LabeledContent(chosen.name) {
                        Text("not installed")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nothing chosen yet — pick one below.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Installed") {
                ForEach(model.installed) { row in
                    rowView(row, enabled: true)
                }
            }

            if !model.missing.isEmpty {
                Section("Not installed") {
                    ForEach(model.missing) { row in
                        rowView(row, enabled: false)
                    }
                }
            }

        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.role.displayName) \(Version.short) (\(Version.build))")
                if let upstream = Version.upstreamVersion {
                    Text("Based on OpenInTerminal-Lite \(upstream)")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Link("Source", destination: URL(string: "https://github.com/inquinity/yatu")!)
        }
        .font(.caption)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func rowView(_ row: CatalogRow, enabled: Bool) -> some View {
        Button {
            model.choose(row.app)
        } label: {
            HStack(spacing: 8) {
                if let icon = row.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    // Keep the text aligned with the installed rows above.
                    Color.clear.frame(width: 18, height: 18)
                }
                Text(row.app.name)
                Spacer()
                if model.chosen == row.app {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? .primary : .secondary)
        .opacity(enabled ? 1 : 0.55)
    }
}
