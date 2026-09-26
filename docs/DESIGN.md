# Yatu — design record

> **The record of why Yatu is built the way it is, not the plan.** Source comments cite it by
> section (§3 findings, §4.1 rules, §5 settings, §9 the extension). What is next is in
> [ROADMAP.md](ROADMAP.md). The longer, dated history of each decision is in git: this file was
> 840 lines until 2026-09-25.

## 1. Decisions

| Item | Decision |
|---|---|
| Name | **Yatu** ("Yet Another Terminal Utility" as a tagline, never the name). No trademark search, deliberately: a DIY project, not a defended name. A forced rename would cost a new bundle id, preferences domain and toolbar re-add |
| Bundle id | `com.altmansoftwaredesign.yatu` (dev: `….yatu.dev`); extension `….yatu.findersync` |
| Cask | `yatu` in `inquinity/homebrew-tap`; `openinterminal-lite-inquinity` stays there for older Macs and coexists (different bundle id and preferences domain) |
| Team | `45GJWJVQN2` (Altman Software Design, LLC), Developer ID, notarized |
| Minimum macOS | **13.0** (§8.2) |
| Structure | A Swift package with no dependencies and no Xcode project; `bin/build.sh` assembles the bundle |
| Toolbar button | A Finder Sync extension inside the app (§9) |
| Editor role | In `YatuKit`, reached from the extension's menu; no separate app (§4.1) |
| Versioning | Ours. Release notes say which OpenInTerminal-Lite version the code came from |

## 2. Why OpenInTerminal was the base

It already had ~43 terminals and editors with bundle ids, ScriptingBridge support for Terminal.app,
and argument templates for kitty, Alacritty, WezTerm and Tabby. Alternatives were rejected:
`cdto` (Objective-C, configured with `defaults write`), `TermHere` (archived), and a handful of
AppleScript or dormant projects. `sozercan/OpenInCode` was the model for the package structure.

Yatu **uses code from OpenInTerminal; it is not a fork** (§9.7). Shipped OpenInTerminal-Lite had
no third-party dependencies, so there is no dependency upkeep to inherit.

## 3. Findings the build had to address

From a security review of upstream's shipped Lite app. All Low, all closed by design:

| # | Finding | Closed by |
|---|---|---|
| L1 | Tampering with preferences turns the notarized app into an arbitrary-app launcher | Catalog allowlist; compiled-in argument templates |
| L2 | Opened paths logged to a world-readable file | `os.Logger`, paths `.private`, no log file |
| L3 | Force-casts in the Finder query crash on Recents, AirDrop, search | `FinderTarget`, no force-casts |
| L4 | Unstripped binaries embed build paths | `strip -x` in `bin/build.sh` (SwiftPM embeds none to begin with) |
| L5 | Empty terminal name runs `open -a ""` | Validation and re-prompt |

Preserved as regression tests: no injection across ~50 hostile launches; selected
`.command` files, executables and `.app` bundles are never executed; hardened runtime, one
entitlement, no network.

Findings in what Yatu does not ship (upstream's full app and Finder extension: F1 High, F2–F6
Medium/Low) are upstream's, not Yatu's — see M6.

## 4. Architecture

```
Package.swift                 YatuKit + YatuUpstream libraries, two executables, no dependencies
Sources/YatuTerminal/         entry point: ⌥ → settings, else open the terminal
Sources/YatuFinderSync/       the Finder toolbar button (§9); sandboxed, executes nothing
Sources/YatuKit/              everything the app owns
  Yatu.swift                    run loop; LaunchCoordinator, the one NSApplicationDelegate
  HandOff.swift                 strict parser for the public yatu:// scheme
  RequestHandler.swift          applies a hand-off's request, treating it as untrusted
  FinderTarget.swift            Finder query; always resolves to a directory
  Launcher.swift                NSWorkspace launch; compiled-in argument templates
  Settings.swift  Role.swift    allowlisted choice per role
  Catalog.swift  CatalogCorrections.swift   the app list, and verified fixes to it
  MenuModel.swift  MenuBuilder.swift        the extension's menu, testable without Finder
  SettingsWindow/View.swift  AboutWindow/View.swift  the two windows
  Brand.swift  Version.swift  Log.swift
Sources/YatuUpstream/         three vendored upstream files plus Model.swift (App/AppType, no behaviour)
Tests/YatuTests/              rules, hand-off, catalog, menu, request handler, launch lifetime, brand
Resources/                    Info plists, entitlements, icon, the toolbar symbol
bin/  docs/  justfile         build, notarize, package, release, attack matrix; docs
```

Nothing in `Sources/YatuUpstream/` is edited to make Yatu work; new behaviour goes in `YatuKit`.
Of upstream's `App.swift` only the dependency-free `App`/`AppType` declarations could be lifted,
because its `Openable` extension reaches the whole framework, including the three components Yatu
replaces (L1–L3).

### 4.1 Behavioural rules

Each has a unit test. One codebase serves two **roles** — terminal and editor — that differ in
their catalog, their target and their preference key. The editor role receives the selected items
themselves; the terminal role receives a folder.

1. **The chosen app must exist in the catalog; resolution is by bundle id, never by name.**
   A bundle id is *not* a trust signal: a bundle planted in `~/Downloads` claiming another app's
   identifier resolves without write access to `/Applications` (tested, `LAUNCH-SECURITY.md`).
   Resolving by identifier is right because it finds an app wherever it lives; what stops an
   impostor is **Gatekeeper**. Identifiers are also unreliable — `com.apple.Xcode` and `dev.warp`
   were verifiably stale — so corrections live in `CatalogCorrections.swift`, and the bar for adding
   one is verification against the real application.
2. **Catalog entries without a bundle id** (GitHub Desktop, Fork) resolve by an explicit
   `/Applications` path or are dropped.
3. **A path handed to a terminal is always an existing directory** — never a file, a symlink to a
   file, or an `.app`/`.command` bundle. One selected item names that directory. Several selected
   items are ignored in favour of the folder being viewed, since choosing the "first" would depend
   on selection order the user cannot see. The **editor** role takes all selected items, executable
   files included (opening a document is the point) but not `.app` bundles. An editor is opened
   *with* the file through `NSWorkspace.open(_:withApplicationAt:)`, so a `.command` is edited, not
   run. The per-role rule is applied only in `FinderTarget.resolve`.
4. **No Finder window, or a view with no filesystem target → `~/Desktop`**, built with
   `URL(fileURLWithPath:)`.
5. **Argument templates are compiled-in constants.** Nothing from preferences reaches an argument
   vector except the catalog identifier.
6. **No file logging**; paths are `.private` in `os.Logger`.
7. **Terminal.app keeps the ScriptingBridge path**, the way to hand it a folder without a shell.

## 5. The settings window

The feature OpenInTerminal-Lite lacks, and the reason this is a product rather than a patch.

- **Opening it:** ⌥-click the toolbar button, `yatu --settings`, or a first run with no valid choice.
- **Contents:** the **installed** terminals with real icons; the current choice; a **Reveal in
  Finder** line naming the resolved bundle, so the user sees exactly what will launch; a footer
  reading `1.0.2 build 1`. Uninstalled apps are not listed (1.0.2 removed the dimmed rows); the
  full list is the README's **Supported terminals and editors**, which the window links to. The
  "based on OpenInTerminal-Lite X" credit is not in the window — it belongs in the README and
  release notes.
- **Must never** offer a free-text command or app path. That is L1; if a terminal is missing, the
  answer is a catalog entry in a release.
- **A window/tab choice was dropped.** Upstream's way needs a second permission grant (System
  Events keystrokes); the other way builds a shell string from a folder path, the injection shape
  this project exists to avoid. Terminals have their own "new windows/tabs open with" preference,
  which `open` already honours.

## 6. Conventions

- `docs/UPSTREAM.md` is the source of truth for what code comes from OpenInTerminal, the licence
  and attribution obligations, and how catalog changes are noticed.
- Credit is worded **uses code from**, never "fork of", in `README.md`, `CLAUDE.md` and anything public.
- Two repositories: `inquinity/yatu` is the product; `~/dev/oss/openinterminal` is a separate
  clone with the only `upstream` remote. Nothing for one lands in the other.
- Short-lived topic branches merged `--no-ff`; **never rebase `main`**; merge commits follow
  Conventional Commits.
- Public-repo writing: refer to upstream issues by full URL or `GH-287`, never a bare `#287`.
- **No invented dot-directories.** A leading dot means a tool owns it. Visibility and git are
  separate decisions: `security-review/` is visible and git-ignored.
- Anything touching the launch path or the `yatu://` handler gets a security review.

## 7. History worth keeping

Milestones M0–M5 (scaffolding, identity, the app, the release pipeline, distribution) are done;
1.0.0 shipped 2026-09-24 and the sequence is in git and `release-notes/`. Kept here are the
decisions that were reversed or dropped, and why.

**M1 — Identity.** A flat `.icns` drawn by `bin/make-icon.swift`, never an Icon Composer bundle.
Copyright reads "© 2026 Altman Software Design, LLC — portions © 2019 Jianing Wang (MIT)" and the
MIT text ships in the bundle. The icon is a folder with a prompt caret in violet, chosen because
every neighbouring toolbar app uses a terminal-window motif and a folder is the one shape none do.

**M2 — Release gates for 1.0.0**, closed 2026-09-24: unit tests, `bin/attack-matrix.sh --live`
against the installed build (no execution, nothing selected ran), the `yatu://` security review
(no High or Critical; L1 and F1 closed) and the Gatekeeper assessment in `LAUNCH-SECURITY.md`.
The attack matrix detects by **canary** — every hostile name embeds a command that writes a file,
so the verdict is whether one exists, not whether escaping looks right.

**M3 — Migration from OpenInTerminal-Lite: built, then dropped 2026-09-24.** It read the old
preference on first launch and adopted the terminal choice. It worked, and was not worth it: it
saves one click, once, for about one person, against a permanent branch in the launch path, a file
of untrusted-input handling and a foreign preference domain to read correctly forever.

**M4 — Build and release.** `bin/build.sh --release` signs by *team*, refuses a dirty tree and then
asserts what it produced (strict verification, exact designated requirement, hardened runtime, no
`get-task-allow`). `bin/notarize.sh` requires `Accepted`. `bin/release.sh` is dry by default,
verifies the artifact was built from the commit being tagged, reads the sha256 back from the
*downloaded* asset, audits the cask and verifies the signed tag. Version bumping stays a separate
step (`bin/ver`).

**M5 — Distribution.** Caught while releasing: `gh release create` resolved the repository to
upstream because an `upstream` remote survived the fork cut. It is removed from this clone.

**M6 — Contributing findings upstream: dropped 2026-09-25.** Yatu is independent; what
OpenInTerminal does is not its concern. Yatu is not exposed to the findings (F1, upstream's
extension handing a *file* to a terminal when a sandboxed stat fails, is closed here by
construction, §9.1). A static read found the code path still present upstream; it was not
reproduced. `fix/sandbox-command-injection` was already merged and fixed a different class. A
licence change upstream would not reach the vendored files, which are MIT at the commits in their
headers. Kept: PR GH-287 as it stands, and `bin/check-upstream.sh`. Revisit only if Yatu comes to
depend on more of upstream or a defect turns up in a vendored file.

**M6a — A separate editor app: dropped 2026-09-23** in favour of the extension's menu (§9).
`Role.editor` stays; `Role.editor.bundleIdentifier` names a bundle that does not exist and is kept
as the role's stable identity.

**M7 — optional:** an App Sandbox spike for the app itself; several folders each in a tab; a
Services entry. See [ROADMAP.md](ROADMAP.md).

## 8. Questions

**8.2 Minimum macOS — 13.0 (Ventura).** Xcode 27's SDK floor is 12.0, so this is a product
choice. 13.0 buys `.formStyle(.grouped)`, `LabeledContent` and `NavigationStack` for the settings
window; 12.0 would have cost hand-rolled layout to regain 2015-era hardware that can still run
upstream's 10.13-target build. Neither version receives Apple security updates as of 2026-09.

**8.6 Icon — a folder with a prompt caret ("Violet Folder"), colour at every size.** Seven concepts
were drawn; an aperture won on 2026-09-18 and was replaced on 2026-09-21 because beside the real
toolbar art of its neighbours it was the same silhouette, and colour does not survive at toolbar
size or when the window is inactive. Differentiation has to come from silhouette. The app icon was
briefly a true template glyph at small sizes; that was reversed 2026-09-23, because the Finder Sync
extension draws its own template symbol and never asks for the app icon, so the size split only
made Yatu the one grey outline in a list of colour tiles. The glyph, where drawn, has a stroke floor
of 1.8px — at 16px a proportional stroke collapses the caret into two dots. Facts:
[FINDER-TOOLBAR-ICONS.md](FINDER-TOOLBAR-ICONS.md).

**Other settled questions.** Two repositories, no rename: `inquinity/OpenInTerminal` is not a GitHub
fork and PR GH-287 is open from it, so renaming would move that PR's head repository. Signed
annotated tags (SSH-signed). The rest of upstream's tree was kept, then removed (§9.7). The old cask
stays in the tap.

## 9. The Finder Sync extension

An application dragged into Finder's toolbar is drawn as its **app icon**, which cannot be a
template, is restyled by the four icon styles and is desaturated when the window is inactive. An
extension supplies a **template image** the system tints, appears in the customisation palette by
name, and is unaffected by all of that. A prototype showed a single click can still act.
Evidence: [FINDER-TOOLBAR-ICONS.md](FINDER-TOOLBAR-ICONS.md) §6.

### 9.1 Shape

```
Yatu.app
├── Contents/MacOS/YatuTerminal           unsandboxed; owns preferences and every rule
├── Contents/PlugIns/YatuFinderSync.appex sandboxed; reports context, executes nothing
└── Contents/Resources/Assets.car         app icon and the toolbar symbol
```

**The division is the security property.** The extension resolves nothing, launches nothing and
executes nothing: it reports what Finder is showing over a `yatu://` URL and stops. Directory
resolution, the compiled-in templates and the catalog allowlist stay in `YatuKit`. Upstream's
extension does the opposite — it runs an installed AppleScript, which is where its F1 lives. Ours
closes it by construction. There is no app group, so the extension cannot read preferences; that is
why the menu cannot mark the current default.

### 9.2 Interaction

| Gesture | Behaviour |
|---|---|
| Click | Open the default terminal at the resolved target |
| ⌥-click | Menu: **Set default terminal program** (sets, does not open), **Send to editor**, **Settings…** |

### 9.3 Build and implementation notes

- **Menu:** built as a pure function returning descriptors, so it is testable without Finder.
  `menu(for:)` must do nothing slow; resolution and icons are cached and persisted; the hand-off
  runs off the callback thread. Menu items must set no `target` and carry no custom
  `representedObject`, because both fail to cross the process boundary to Finder: an item then
  draws and highlights correctly and does nothing when clicked. That is the bug class the manual
  checklist exists for.
- **M1b — icons.** The toolbar symbol is `yatu.folder.caret`, a custom SF Symbol derived from
  Apple's exported `folder` template (`bin/make-symbol.swift`) and compiled by `actool`. Caret on the
  folder face beat caret as a corner badge, which collapses to a blob under 24pt. It is Apple-derived
  artwork under Apple's licence. **Open:** the app-icon *format*, `.icns` or Icon Composer `.icon`,
  to be decided on the format's merits now that nothing needs art to vary by size.
- **Build:** `bin/build.sh` assembles and signs the `.appex` before the app with its own
  entitlements, and asserts the extension is sandboxed and the app is not.
- **Cask caveats:** enable the extension in System Settings, then add it via **View → Customize
  Toolbar**, not by ⌘-dragging; `zap` covers the extension's container and caches.

### 9.4 The new risk

A URL scheme is **public**: any application or web page can invoke `yatu://open?path=…`. The app
treats it as untrusted and applies the rules it applies to Finder input, so a terminal still only
receives an existing directory and the target is still only a catalog entry. Reviewed 2026-09-24:
no High or Critical; L1 and F1 confirmed closed. Accepted as Low: `yatu://open` launching a catalog
app at a caller-chosen path, no rate limit, and a narrow TOCTOU between the directory check and
Terminal.app's `open`.

### 9.5 What stays

Dragging the app into the toolbar still works as a fallback. The settings window is unchanged.
Upstream's own extension is not Yatu's; Yatu's is new code.

### 9.6 The catalog deserves no special reverence

`SupportedApps.swift` is one maintainer's list, changed 21 times in three years, almost always to
add an app someone asked for. It is partly wrong (`com.apple.Xcode`, `com.sublimetext.3`), and
Yatu survives that only because `Launcher` falls back to an explicit `/Applications` path. The set
of popular terminals changes slowly, so owning it is a few edits a year. It was vendored verbatim
with the cut, because changing code and its content in one move makes neither reviewable.
`bin/check-upstream.sh` diffs catalog *entries* against upstream's copy, so adopting a change is
already a hand edit, and a judgement call verified against the real app.

### 9.7 Cutting the fork relationship — 2026-09-23

The product compiled **three** upstream files — the catalog and two ScriptingBridge interfaces,
unchanged since 2019 — yet the repository carried **289 unbuilt files**. They were vendored, each
with a provenance header naming the upstream path and commit, and the tree, both Xcode projects and
the root build scripts were deleted (293 files, ~20,300 lines). `bin/check-upstream.sh` was
rewritten to compare catalog entries. The MIT notice and credit are unchanged.

### 9.9 `set-default` over an unauthenticated channel — Low

`yatu://set-default?role=terminal&app=Warp` changes a stored preference on behalf of a caller the
app cannot identify. Any local process or web page can repoint the button at a different
**installed catalog** app. The review first called this Medium; testing the launch path collapsed it
to Low, because the worst case is an app that Gatekeeper blocks, a consent prompt Yatu cannot
answer, or one the user already trusts.

**Sender verification was investigated and withdrawn.** The Apple Event carries the sender's PID,
and it can be held to a code requirement — but the requirement must include `anchor apple generic`
and the team OU to mean anything (an identifier-only one is satisfied by any ad-hoc binary
claiming the identifier), and it cannot work in a development build. Set against a Low finding whose
payoff Gatekeeper already denies, it is not worth the code. Moving the hand-off to XPC would give an
audit token, but reopens the app-group decision in §9.1.

What remains worth doing is behaviour, not security: a notification with an undo and a durable log
entry, so a default never changes unseen. Tracked in [ROADMAP.md](ROADMAP.md).
