//
//  SettingsView.swift
//  YatuKit
//
//  The feature OpenInTerminal-Lite does not have: a way to change your mind.
//  See docs/ROADMAP.md §5.
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

    /// How many entries the catalog holds for this role, installed or not.
    /// Shown as a count rather than as rows -- see SettingsView.supportedNote.
    var catalogCount: Int { installed.count + missing.count }

    /// Kept for the chosen app that is no longer on disk: that one has to be
    /// nameable, or a stale preference would show as "nothing chosen yet".
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
        // Height follows the content, within bounds. It was a fixed 520, which
        // was the right size for a window listing the whole catalog; with only
        // the installed apps in it, a Mac with two terminals got a window that
        // was two thirds empty. The floor keeps the footer off the list, and
        // the ceiling keeps a fully-stocked Mac from filling the screen -- past
        // that the Form scrolls, as it always did.
        .frame(width: 420)
        .frame(minHeight: 260, maxHeight: 620)
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

            Section {
                ForEach(model.installed) { row in
                    rowView(row)
                }
            } header: {
                Text("Installed")
            } footer: {
                supportedNote
            }
        }
        .formStyle(.grouped)
    }

    /// Why the list is shorter than the catalog.
    ///
    /// The uninstalled entries used to be a second section, greyed out: a dozen
    /// rows that cannot be chosen, in the one window whose entire job is
    /// choosing. Saying how many are supported answers "where is my terminal"
    /// without spending the window on it, and the README carries the names.
    @ViewBuilder
    private var supportedNote: some View {
        if !model.missing.isEmpty {
            // One string literal, not a concatenation: Text parses markdown from
            // a LocalizedStringKey, and `+`-ing two Strings together produces a
            // plain String, which it renders verbatim -- brackets, URL and all.
            Text("\(model.role.displayName) supports \(model.catalogCount) \(supportedNoun). [See which](https://github.com/inquinity/yatu#supported-terminals-and-editors)")
        }
    }

    private var supportedNoun: String {
        model.role == .terminal ? "terminals" : "editors"
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            // The upstream version this is based on is a credit, and credits
            // belong in the README's acknowledgements and the release notes --
            // not in a settings window opened to change a terminal. It is still
            // stamped into Info.plist as YatuUpstreamVersion.
            Text("\(model.role.displayName) \(Version.short) build \(Version.build)")
            Spacer()
            Link("Source", destination: URL(string: "https://github.com/inquinity/yatu")!)
        }
        .font(.caption)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func rowView(_ row: CatalogRow) -> some View {
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
    }
}
