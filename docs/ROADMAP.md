# Yatu — roadmap

Status: **accepted 2026-09-18**, all questions in §8 answered.
**Shipping. 1.0.2 released 2026-09-25**; M0–M5 are done or deliberately dropped. What remains is
M6 (the upstream contribution track, not started), the app icon *format* in §9, the catalog
question in §9.6, the visible-change notification for `set-default` in §9.9, and a full pass of
`docs/MANUAL-TEST-CHECKLIST.md` §4 — newly owed, because 1.0.2 rewrote the launch path and the
menu that §4 exists to exercise. M7 is optional and unscheduled.
Replaces the earlier `PRIVATE-LABEL-PLAN.md` draft.
Inputs: the security review in `security-review/` (git-excluded), the Belvedere fork
(`~/dev/oss/belvedere`) for fork conventions, and a GitHub survey of comparable apps.

## 1. Decisions taken

| Item | Decision |
|---|---|
| Name | **Yatu** ("Yet Another Terminal Utility" as tagline, never as the name) |
| Bundle id | `com.altmansoftwaredesign.yatu` (dev: `com.altmansoftwaredesign.yatu.dev`) |
| Cask | `yatu` in `inquinity/homebrew-tap` |
| Preferences domain | `com.altmansoftwaredesign.yatu`, standard domain, no app group |
| Team | `45GJWJVQN2` (Altman Software Design, LLC), Developer ID + notarized |
| Minimum macOS | **13.0** (Ventura). Xcode 27's SDK floor is 12.0, so this is our choice, not the toolchain's |
| Functional base | **OpenInTerminal-Lite**, kept as the upstream to merge from |
| Structure | **Swift package**, built into an app bundle by script — modelled on [sozercan/OpenInCode](https://github.com/sozercan/OpenInCode) |
| Headline feature | A **settings window** for choosing the terminal, which OITL lacks |
| Toolbar button | A **Finder Sync extension** inside the app (decided 2026-09-23, §9) |
| Editor role | Kept in `YatuKit` and reached from the extension's menu; **no separate app** (§9) |
| Version line | Ours: `1.0.0` build 1. Release notes say which OpenInTerminal-Lite version it is based on. |

Name screening (2026-09-17): no Homebrew cask or formula, no Mac App Store app, no GitHub
repo or account. Existing uses are three unrelated iOS apps ("Yatu Lite/Pro/Viewer") and a
Chinese materials company. **No trademark search: deliberate.** This is a DIY project, not a
marketed one, and the name is not being defended. The residual risk is a later forced rename,
which would mean a new bundle id, a new preferences domain, fresh Automation prompts and
re-adding the toolbar button — the same work as M1/M3, done again.

## 2. Why not a different base

| Project | Verdict |
|---|---|
| **Ji4n1ng/OpenInTerminal** 7,003★, MIT, 36 commits/12mo | **Functional base.** Already has ~43 terminals and editors with bundle ids, the picker, ScriptingBridge support for Terminal.app, and argument templates for kitty, Alacritty, WezTerm, Tabby. |
| [sozercan/OpenInCode](https://github.com/sozercan/OpenInCode) 917★, MIT, active | **Structural model.** `Package.swift`, two source files, tests, `scripts/build-app.sh` (SwiftPM → `.app`, universal, ad-hoc or Developer ID), a cask-rendering script, CI. Opens VS Code only, so no use functionally. |
| [jbtule/cdto](https://github.com/jbtule/cdto) 2,431★, MIT | No. Objective-C, configured by `defaults write` — the opposite of the GUI we want. Last release 2022. |
| [hbang/TermHere](https://github.com/hbang/TermHere) 107★, Apache-2.0 | No. Archived 2019, Carthage-based. |
| [jakerains/TermHere](https://github.com/jakerains/TermHere) 2★ | No. One day of history, no users. |
| ShellHere, CDHere, `jakshin/*` | No. AppleScript or dormant Objective-C, less capable than what we have. |

**Stack we inherit (verified):** Swift 5, AppKit, ScriptingBridge with generated interfaces
checked in, Xcode 13-era project. **Third-party dependencies in the shipped Lite: none** —
`otool -L` shows only Apple frameworks plus its own Core framework. ShortcutRecorder is
used by the full app only. So dependency upkeep is already near zero, and going to a Swift
package with no dependencies keeps it there: the only maintenance is Apple's (new macOS,
new Xcode rules — which is exactly what the 26.6 icon bug and the macOS 12 floor were).

## 3. Findings the build must address

Detail in `security-review/NOTES.md`. Shipped-app findings, all Low, all fixed by design in §4:

| # | Finding | Fixed by |
|---|---|---|
| L1 | Prefs tampering turns the notarized app into an arbitrary-app launcher (terminal name may be a path; `KittyCommand` and friends are split into `open` arguments) | Allowlist + compiled-in templates (§4 `Launcher`, `Settings`) |
| L2 | Opened paths logged to world-readable `~/Library/Logs/logfile-N.log`, generic name, forgeable lines | `os.Logger`, paths `.private`, no log file |
| L3 | Force-casts in `FinderManager` can crash on Recents/AirDrop/search | Fork-owned `FinderTarget`, no force-casts |
| L4 | Unstripped binaries embed `/Users/robert/...` | Strip in `bin/build.sh`, dSYM kept privately |
| L5 | Empty terminal name runs `open -a ""` | Validation + re-prompt |

Confirmed good, and to be preserved as regression tests: no injection across ~50 hostile
launches; selected `.command`/executables/`.app` never executed; hardened runtime, library
validation, one entitlement, no network.

Build and release findings (S1–S7) are addressed in M4. The unshipped full app's findings
(F1 High, F2–F5 Medium) go upstream in M6 and are not fork work.

## 4. Architecture

A single Swift package. No Xcode project, no workspace, no SPM dependencies.

> **Superseded in part, 2026-09-25.** This section is the original design and is kept as such.
> Since it was written: the fork was cut (§9.7), so `Sources/YatuUpstream/` holds three *vendored*
> files with provenance headers, not symlinks, and there is no `Sync:` merge; the editor executable
> was retired (§4.1, M6a); and `Sources/YatuFinderSync/` (§9), `HandOff.swift`,
> `CatalogCorrections.swift`, `LaunchCoordinator` and the About window were added. The tree below
> omits them. Read the source tree for what exists now.

```
yatu/                            (repo root)
├── Package.swift                library YatuKit + two executables, no dependencies
├── Sources/YatuKit/             everything below except the entry points
├── Sources/YatuTerminal/
│   └── main.swift               entry: ⌥ → settings, else open the terminal
│   (Sources/YatuEditor was retired 2026-09-23; the editor role is reached from
│    the Finder button's menu — M6a)
│   (in YatuKit:)
│   ├── FinderTarget.swift       Finder query; no force-casts; always resolves to a directory
│   ├── Launcher.swift           NSWorkspace launch; compiled-in argument templates
│   ├── Settings.swift           allowlisted app choice, per role; one-time migration from OITL
│   ├── SettingsWindow.swift     the new GUI (§5)
│   ├── AppCatalog.swift         thin wrapper over upstream's SupportedApps, filtered by role
│   └── Log.swift                os.Logger; paths marked .private
├── Sources/YatuUpstream/        vendored OpenInTerminal files, compiled UNCHANGED (see below)
├── Tests/YatuTests/             path resolution, validation, migration, catalog
├── Resources/                   Info.plist, entitlements, icon, terminal icons, strings
├── bin/                         build.sh, publish-release.sh, check-upstream.sh,
│                                attack-matrix.sh, make-icon.swift
├── docs/                        UPSTREAM.md, this plan, MANUAL-TEST-CHECKLIST.md, release-notes/
└── justfile                     just build | test | release <seg> | publish --go
```

**Upstream files compiled unchanged** (symlinked or path-referenced into `Sources/YatuUpstream`):
`OpenInTerminalCore/SupportedApps.swift`, `ScriptingBridge/Finder.swift`,
`ScriptingBridge/Terminal.swift`, and `App.swift` only if the spike shows its dependency
chain can be cut. *(Superseded 2026-09-23: the files are vendored and upstream changes are noticed, not merged — §9.7.)*

**Spike M2a — done 2026-09-18. Outcome: the second option.** `App.swift` cannot be compiled:
its `Openable` extension reaches `FinderManager`, `DefaultsManager`, `ScriptManager`,
`Constants`, `OITError` and `logw` — the whole framework, including the three components Yatu
replaces by design (L1, L2, L3). But `SupportedApps.swift` refers to `App` and `AppType` by name,
so those types must exist in the same module.

The compile set is therefore **`SupportedApps.swift` alone**, symlinked into
`Sources/YatuUpstream/` and compiled unchanged, beside our own `Model.swift` carrying the
dependency-free `App`/`AppType` declarations lifted from upstream's file with provenance in the
header. SwiftPM resolves the symlink, so upstream catalog additions arrive on merge with no diff
to carry. The two ScriptingBridge files join the target when the launcher needs them in M2b.
**No upstream file is edited.**

### 4.1 The editor role

> **Superseded 2026-09-23 (§9, M6a).** There is one app and no editor executable or bundle; the
> editor role is reached from the Finder extension's menu. The table's Editor column describes the
> *role* as `YatuKit` still implements it, and `…yatu.editor` is a stable identity, not a bundle.

Upstream ships two Lite apps — OpenInTerminal-Lite and OpenInEditor-Lite — because a Finder
toolbar button does exactly one thing. Yatu originally planned the same shape: **one codebase, two
executables**, differing only in which role they ask the shared code for.

| | Terminal role | Editor role (no separate app) |
|---|---|---|
| Bundle id | `com.altmansoftwaredesign.yatu` | `com.altmansoftwaredesign.yatu.editor` |
| App name | Yatu | Yatu (the same app, in its editor role) |
| Catalog | `SupportedApps` entries whose type is `.terminal` | the `.editor` entries |
| Target given to the app | the folder (parent folder if a file is selected) | the **selected items themselves**, so the editor opens the file you clicked |
| Preference key | `terminal` | `editor` |

Why build it now rather than later: the difference is one enum and one path rule, so carrying it
costs a few lines and a test, while retrofitting it later means reopening `Launcher`, `Settings`
and the settings window at once. The editor executable is built and unit-tested in CI from M2;
whether it is ever signed, notarized and put in a cask is a separate decision (M5 ships the
terminal app only). Upstream's own `OpenInEditor-Lite/` target stays in the tree, untouched, as
the reference for the behaviour.

**Behavioural rules, each with a unit test:**
1. The chosen terminal must exist in the catalog; resolution is by bundle id, never by name.

   **Corrected 2026-09-24: a bundle id is not a trust signal.** The rationale used to be "a name is
   a string a user can control, a bundle id is what LaunchServices indexes", which implies a
   guarantee it does not provide. A bundle planted in `~/Downloads` claiming another application's
   identifier resolves through `urlForApplication(withBundleIdentifier:)` with no write access to
   `/Applications` needed — tested, in [LAUNCH-SECURITY.md](LAUNCH-SECURITY.md). Resolving by
   identifier is still right, because it finds an app wherever it lives rather than guessing a path.
   But what stops a planted impostor is **Gatekeeper**, and the rule should not be read as claiming
   otherwise.

   **The identifiers themselves are not reliable either**, which is a separate problem with the same
   root. Two are verifiably stale — `com.apple.Xcode` (really `com.apple.dt.Xcode`) and `dev.warp`
   (really `dev.warp.Warp-Stable`, which resolves to nothing) — and both were surviving only through
   rule 2's `/Applications` fallback, so they would fail for anyone keeping apps in
   `~/Applications`. Corrections live in `Sources/YatuKit/CatalogCorrections.swift`, on our side of
   the line that keeps `Sources/YatuUpstream/` unedited, and the bar for adding one is verification
   against the real application.
2. Catalog entries without a bundle id (GitHub Desktop, Fork) are resolved by an explicit
   `/Applications` path or dropped.
3. A path handed to a **terminal** is always an existing directory — never a file, a symlink to a
   file, or an `.app`/`.command` bundle. **One** selected item names that directory; a selection of
   **several** is ignored in favour of the folder being viewed, because a terminal opens at exactly
   one place and choosing the "first" of a set would depend on selection order the user neither
   chose nor can see. The **editor** role takes all of them, where order does not matter.
   *(The extension did not honour the second half until 2026-09-23: it collapsed a multiple
   selection to nothing before the role was known, and `HandOff.Request.open` could carry only one
   path, so "Send to editor" with several files sent the folder. The contract now carries a bounded
   list and the per-role rule is applied only in `FinderTarget.resolve`, which is where it belongs.)* The **editor** role may receive files, since opening a
   document is the point, **including executable ones**; `.app` bundles are still dropped.
   *(Relaxed 2026-09-18. The rule previously refused anything with the execute bit, which blocked
   `chmod +x` scripts — one of the commonest reasons to open an editor. The execution risk in
   finding F1 is the terminal role's, and that is this rule's first sentence, unchanged. An editor
   is opened **with** the file via `NSWorkspace.open(_:withApplicationAt:)`, which hands it to that
   application rather than asking the system what to do with it, so a `.command` is edited, not
   run.)*
4. No Finder window, or a view with no filesystem target → `~/Desktop`, built with
   `URL(fileURLWithPath:)`.
5. Argument templates are compiled-in constants. Nothing from preferences reaches an argument
   vector except the catalog identifier.
6. No file logging; paths are `.private` in `os.Logger`.
7. Terminal.app keeps the ScriptingBridge path (it is how a folder opens without a shell).

## 5. The settings window

The feature OITL doesn't have, and the main reason this is a product rather than a patch.

- **Opening it:** ⌥-click the toolbar button. A Finder toolbar app has no menu bar of its own,
  so this is the discoverable route; first run still shows the picker. `yatu --settings` for
  scripting and for the cask caveat.
- **Contents:**
  - ~~the terminal list, installed apps first with their real icons, the rest dimmed (the existing
    picker already does this);~~ **revised 2026-09-25 in 1.0.2.** The dimmed rows are gone. Copying
    the existing picker was the whole justification, and it was a bad one: a dozen or more rows
    that cannot be chosen, in the window whose only job is choosing. The list is now what is
    installed; the catalog moved to the README's **Supported terminals and editors**, which the
    window links to when something is missing. Nothing is lost — "why is my terminal not here" is
    still answered, just not by spending the window on it;
  - the current choice, with an obvious way to change it;
  - ~~"open a new window" vs "new tab" where the terminal supports both~~ — **dropped 2026-09-19.**
    There are only two ways to do it. Upstream's is
    `tell application "System Events" to keystroke "t" using command down`, which needs a second
    TCC grant (System Events / Accessibility) on top of Apple Events to Finder and the terminal —
    a permission prompt for a preference. The other is Terminal's `doScript`, which means building
    a shell command string from a folder path: the exact injection shape this fork exists to avoid,
    and the one upstream already had to fix twice. Meanwhile every terminal has its own
    "new windows/tabs open with" preference, which `open` already honours, so the setting belongs
    to the terminal and not to Yatu. Revisit only if a terminal offers a non-shell way to ask.
  - a **Reveal in Finder** line naming the resolved app bundle, so the user sees exactly what will launch;
  - a footer: the version and build, written `1.0.0 build 1` — a build number should say that is
    what it is. **Not** "based on OpenInTerminal-Lite X.Y.Z": that is a credit, and credits belong
    in the README's acknowledgements and in the release notes, not in a window opened to change a
    terminal. It stays in `Info.plist` as `YatuUpstreamVersion`.
- **Roles:** the same window serves both executables, showing the catalog for the role it was
  launched in; the title says which. If both apps are installed they share nothing but the code.
- **Implementation:** SwiftUI window, AppKit host, using `.formStyle(.grouped)` and
  `LabeledContent` — which is what the macOS 13.0 floor buys (§8.2).
- **What it must not do:** offer a free-text command or app path. That is finding L1, and the
  allowlist is the fix. If a user needs an unsupported terminal, the answer is a catalog entry
  in a release, not a text field.

## 6. Project conventions

**Amended 2026-09-23**, when the fork was cut (§9.7). The conventions below that existed only to
manage a fork — the `Fork:` / `Sync:` merge prefixes, the `fork/<topic>` branch name, and the
"new files are free, edits to upstream files are rent" rule — are retired. What survives is
everything that was never about the fork.

- `docs/UPSTREAM.md` is the source of truth for what code comes from OpenInTerminal, the licence
  and attribution obligations, how upstream changes are noticed, and the contribution track.
- `README.md` credits OpenInTerminal and Jianing Wang at the end, worded as **uses code from**,
  never "fork of". `CLAUDE.md` carries the same rule for agents.
- Two repositories: `inquinity/yatu` (`~/dev/projects/yatu`, `main`) is the product;
  `inquinity/OpenInTerminal` (`~/dev/oss/openinterminal`, `master`) is the contribution clone and
  is the only one with an `upstream` remote. `git rerere` enabled in both.
- Branches: `main` is the product line; short-lived topic branches merged `--no-ff`;
  `contrib/<topic>` cut from `upstream/master` **in the contribution clone**, one fix each.
- Merge commits follow Conventional Commits, like every other commit. **Merge, never rebase** `main`.
- Nothing in `Sources/YatuUpstream/` is edited to make Yatu's code work; new behaviour goes in
  `Sources/YatuKit/` and calls into that target.
- Public-repo writing: refer to upstream with full URLs or `GH-287`, never a bare `#287` or
  `owner/repo#287` (S7 — we already tripped this once in the tap commit and release notes).
- **No invented dot-directories.** A leading dot means a tool owns the directory and you are meant
  to ignore it — `.build` is SwiftPM's, `.github` is GitHub's. Our own content never takes one,
  because hiding something a person is supposed to read is the opposite of what the dot means.
  Keeping a directory out of git is `.gitignore`'s job; `security-review/` is both visible and
  ignored, and those are two separate decisions.
- Adopting a catalog change gets a security review of what it adds (`security-oss-app-reviewer`);
  so does anything touching the launch path or the `yatu://` handler.

## 7. Milestones

Risk gates per `~/.claude/CLAUDE.md`. M4 and M5 are outward-facing and need separate approval
before anything is published.

### M0 — Fork scaffolding (low) — **done, then superseded 2026-09-23 by §9.7**

> Kept as the record of what was built. Most of it has since been removed with the fork:
> `docs/FORK-NOTES.md` is now `docs/UPSTREAM.md`, the README banner and the `CLAUDE.md` FORK STATUS
> block are gone, `bin/show-private-changes.sh` and the two root build scripts are deleted, and
> `bin/check-upstream.sh` compares catalog entries rather than commits.

- `docs/FORK-NOTES.md`, README fork banner, `CLAUDE.md` FORK STATUS block.
- `bin/check-upstream.sh`, `bin/show-private-changes.sh`, `justfile`, `git rerere`.
- Remove upstream-only automation and leftovers: `.claude/skills/release/` (S4), `.travis.yml`,
  the stray `OpenInTerminal_Lite.entitlements`, `FUNDING.yml`.
- Restore `build-signed.sh` / `build-unsigned.sh` to upstream content — the fork build moves to
  `bin/build.sh` in M4, so we stop paying rent on those two files. `scripts/which-openinterminal.sh`
  becomes `bin/which-yatu.sh`.
- **Verify:** `bin/show-private-changes.sh --stat` lists only intended files. **Rollback:** revert the merge.

### M1 — Identity (low) — **done 2026-09-18**
- `Version.xcconfig`-equivalent in `Resources/Info.plist` + `bin/ver`; team and bundle id in the
  build script; new icon via `bin/make-icon.swift` (flat asset catalog / `.icns`, **no Icon Composer
  bundle** — that is what broke in 26.6); `NSAppleEventsUsageDescription` written for Yatu;
  copyright "© 2026 Altman Software Design, LLC — portions © 2019 Jianing Wang (MIT)";
  MIT license text shipped in the bundle (the license requires it).
- **Verified on this Mac, 2026-09-18 (a snapshot — release builds have since been Developer ID
  signed and notarized, M4, and the preferences domain now exists):** `bin/build.sh` produces `Yatu.app`, universal
  (`x86_64 arm64`), `minos 13.0` in both slices, ad-hoc signed with the single Apple Events
  entitlement and passing `codesign --verify --strict`. `plutil -p` shows the bundle id, name,
  `LSUIElement`, the dual copyright and the per-role usage string; `YatuBuildCommit`,
  `YatuBuildDate` (taken from the commit, not the clock) and `YatuUpstreamVersion` are stamped.
  Launching it creates **no** preferences domain — `~/Library/Preferences` still holds only
  `wang.jianing.app.OpenInTerminal-Lite.plist`, which is what M3 migrates from.
- **Note on L4:** a SwiftPM release build embeds no `/Users/...` paths to begin with — `strings`
  finds none before or after `strip`. The strip step stays as a guard, but the finding is closed
  by the build system, not by us.
- **Icon: done.** `bin/make-icon.swift` draws the folder-and-caret mark (§8.6) and writes all ten sizes into
  `Resources/AppIcon.icns`; the built bundle carries a byte-identical copy and `CFBundleIconFile`
  resolves to it. Nothing in M1 is outstanding.

### M2 — The app (medium: app logic)
- **M2a** compile-set spike (§4) — **done 2026-09-18**, outcome recorded in §4.
- **M2b** the sources in §4 with their seven rules, as `YatuKit` plus the two thin
  executables (§4.1) — **done 2026-09-18**. `Log` (rule 6), `FinderTarget` (rules 3, 4, and the
  force-cast-free Finder query that closes L3), `Launcher` (rules 1, 2, 5, 7) and `Settings` (the
  allowlist that closes L1). The Finder query sits behind a protocol so the policy is testable
  without a running Finder, and `Settings` takes a store rather than `UserDefaults` directly so the
  suite creates no preferences domain.
- **M2c** the settings window (§5) — **done 2026-09-19.** SwiftUI in an AppKit host, reached by
  ⌥-clicking the toolbar button, by `--settings`, or by there being no valid choice yet. Installed
  apps first with their real icons, the rest dimmed and unselectable; the resolved bundle path is
  shown with Reveal in Finder; the version, the upstream version it is based on, and a source link
  are pinned below the scrolling catalog. Every row is a catalog case, so there is nowhere to type
  a path. The window/tab control in §5 was dropped, with the reasoning recorded there.
  The dimmed uninstalled rows described here shipped in 1.0.0 and were removed in 1.0.2; see §5.
- **Release gates for 1.0.0, all closed 2026-09-24** (counts as of then; 111 unit and 7 shell as
  of 1.0.2, see M5): 92 unit tests, 4 shell tests, lint clean;
  `bin/attack-matrix.sh --live` run by Robert against the installed build — **all hostile cases
  passed**, no command execution and nothing selected was executed; the `yatu://` security review
  (no High or Critical, L1 and F1 confirmed closed); and the Gatekeeper launch assessment in
  `docs/LAUNCH-SECURITY.md`.
- **M2d** tests: unit tests for rules 1–6 — **done 2026-09-18**, 30 tests; **92 tests and 4 shell
  checks as of 2026-09-23**, after three defects shipped past the first 65 (see the test commit).
  `docs/MANUAL-TEST-CHECKLIST.md` — **done 2026-09-23**, EXPECT / FAIL IF throughout, and its
  §4 exists because a menu item that draws correctly and does nothing when clicked is
  indistinguishable from one that works unless you click it. Rule 7 and rule 6's *absence* of a
  log file are not unit-testable and are covered there. `bin/attack-matrix.sh` —
  **done 2026-09-24**: the hostile-name and canary-app matrix, fired at the `yatu://` handler
  directly, scratch only, preferences backed up and restored on exit even if interrupted. Detection
  is by canary rather than by inspection — every hostile name embeds a command that writes one, so
  the verdict is whether a file exists, not whether escaping looks right. Two modes: the default
  fires only the cases that must be refused and launches nothing, `--live` adds the cases that
  legitimately launch and opens a window each. The rule-6 log check is dated against a marker taken
  at the start, because upstream's Lite build writes `~/Library/Logs/logfile-N.log` (finding L2) and
  that is not ours to fail on. **M2d complete.**
- **Review:** independent code review plus a security review of the diff.
- **Rollback:** the package is additive; delete it. OITL keeps building.

### ~~M3 — Migration from the current cask~~ — **dropped 2026-09-24**

Built, verified, and then removed the same day. Recording why, because the reasoning applies to
other "helpful" ideas that will come along.

It read `LiteDefaultTerminal` from OpenInTerminal-Lite's preference domain on first launch and
adopted the choice, so someone replacing that toolbar button was not asked a question they had
already answered. It worked: with Yatu's own setting cleared, a launch adopted `Terminal`.

**It was not worth its complexity.** Yatu is a stand-alone app, not an upgrade path. The population
it helps is people who already ran OpenInTerminal-Lite *and* are installing Yatu *and* have not yet
chosen a terminal — which in practice is one person. What it saves them is a single click, once.
Against that: a permanent branch in the launch path, a file of untrusted-input handling, nine tests,
and a foreign preference domain to keep reading correctly forever.

Little value in breadth, little in depth. The cask caveats that were part of this milestone — tell
the user to replace the toolbar button and approve the new Automation prompt — move to M5, where
they belong.

**Q5 is unaffected:** `openinterminal-lite-inquinity` still stays in the tap for older Macs. The two
apps coexist by having different bundle ids and preference domains, which was always the mechanism;
Yatu simply no longer reads the old one.

### M4 — Build and release pipeline (medium–high: signing) — **done. Signing and notarisation 2026-09-24; release automation 2026-09-25**

> **Done:** `bin/build.sh --release` signs with the Developer ID chosen *by team*, with the hardened
> runtime and a secure timestamp, refuses a dirty or untracked tree, and then asserts what it
> produced — strict deep verification, the exact designated requirement, the runtime flag, and the
> absence of `get-task-allow`. `bin/notarize.sh` submits, requires the status to be literally
> `Accepted`, staples, and confirms with `spctl` that Gatekeeper would let the app run.
> **First notarized build: submission `fe44e1e9-7be8-42d3-a65f-da62f2b3c7e0`, accepted.**
>
> The assertions earned their place immediately. The pinned designated requirement was wrong on the
> first attempt — the real one also pins Apple's Developer ID CA and the Developer ID Application
> leaf — and the check rejected the signature for being *more* specific than expected, which is the
> right direction for an assertion to fail in.
>
> **Closed 2026-09-24/25, and M4 is done.** `SHA256SUMS` is written by `bin/package.sh` and
> uploaded with the release. The dSYM was never a step to add: a SwiftPM release build leaves it in
> `.build` and `strip -x` takes the local paths out of the shipped binary (finding L4, see M1).
> Release composition and publication landed as `bin/release.sh` rather than as the two `just`
> recipes planned below — see the note there.

- `bin/build.sh`: `cd` to the repo root (S2), build into `.build/app`, universal (`arm64` + `x86_64`),
  assemble the bundle, `--release` refuses a dirty or untracked tree (S3).
- Signing: select the identity **by team 45GJWJVQN2**, never "first found". After signing assert
  `codesign --verify --strict --deep`; entitlements equal the expected plist exactly; `codesign -dr -`
  matches `identifier "com.altmansoftwaredesign.yatu" and anchor apple generic and certificate
  leaf[subject.OU] = "45GJWJVQN2"`; hardened runtime on; no `get-task-allow`.
- Notarize with `notarytool submit --wait --output-format json`; fail unless `Accepted`; save the log
  under `dist/`; staple; `spctl -a -t exec`.
- Outputs: stripped binary, dSYM kept privately, `SHA256SUMS`, build date from the commit timestamp,
  `YatuBuildCommit` / `YatuBuildDate` in Info.plist.
- ~~`just release <seg>` bumps the version, composes notes and creates a signed annotated tag;
  `just publish` is a dry run unless `--go`.~~ **Landed differently, 2026-09-25.** One script,
  `bin/release.sh`, dry by default and publishing only with `--go`, exposed as `just release-check`
  and `just release-go`. Three differences from the plan, each deliberate:
  - **Version bumping stayed out of it.** `bin/ver bump <seg>` is its own step, committed and
    pushed before the release runs. The release script then *verifies* that the artifact was built
    from the commit it is about to tag, which is a stronger guarantee than bumping and building in
    one motion — and it is the check that caught a DMG built four commits stale in M5.
  - **Notes are not composed.** `ON-TOP-OF-UPSTREAM.md` went with the fork. `UNRELEASED.md` alone
    is the tag message and the release body; the script titles it with the version and refuses to
    publish it empty (fixed 2026-09-25 — until then both were published under "# Unreleased").
  - **It does more than publish.** It pins `origin`, requires a clean in-sync `main`, reads the
    sha256 back from the *downloaded* asset rather than the local build, audits the cask before
    pushing the tap, and archives the notes. The signed annotated tag (§8 Q4) is still there and
    still verified before it is pushed.
- **Rollback:** delete the tag and release; the dry-run default is the guard.

### M5 — Distribution (high: public) — **done. 1.0.0 released 2026-09-24; current 1.0.2**

**<https://github.com/inquinity/yatu/releases/tag/v1.0.0>** — signed by the Developer ID for team
45GJWJVQN2, notarized and stapled, app and disk image both. Cask live at
`inquinity/tap/yatu`; `brew info --cask yatu` reports 1.0.0.

How it was produced, and what was checked:

- `bin/build.sh --release` → `bin/notarize.sh` → `bin/package.sh`. The first DMG was **rebuilt**
  because it had been made four commits earlier: a release artifact must match its tag, and the
  rebuild changed the sha256 (`0f365b3a…` → `60a513b2…`). That is exactly the trap the cask header
  warned about.
- The cask's sha256 was taken from the asset **downloaded back from the release**, not from the
  local build, and the downloaded image was confirmed accepted by Gatekeeper before the cask was
  pushed.
- `brew style`, `brew audit --cask --strict` and `brew audit --cask --online --strict` all pass;
  the online audit fetches the image and verifies the hash.
- Tag `v1.0.0` is annotated and SSH-signed; verified `Good "git" signature`.

**Caught during the release, worth remembering:** `gh release create` resolved the repository to
**Ji4n1ng/OpenInTerminal** and tried to create the release there. The `upstream` remote had survived
the fork cut — the tree and the merge workflow went, the remote did not — and with no default set,
`gh` chose it. `--verify-tag` refused because the tag did not exist there. The remote is now
removed from this clone, where §9.7 says it should never have remained; the contribution clone at
`~/dev/oss/openinterminal` keeps its own.

- `openinterminal-lite-inquinity` stays in the tap (Q5, reversed), listed in the tap README as
  coexisting rather than superseded.

**Closed 2026-09-25.** `bin/release.sh` automates what was done by hand here, and cut 1.0.2 as its
first real use; see M4 for how it differs from the two `just` recipes originally planned.

#### Releases since

**1.0.1 — 2026-09-25.** The toolbar button did nothing in iCloud Drive and other File
Provider-backed folders. `FIFinderSyncController.targetedURL()` answers nil there, so the extension
sent a hand-off carrying nothing and the app rejected its own extension's request as unrecognised.
⌘-drag and OpenInTerminal-Lite both worked in those folders, which is what localised it: they ask
Finder over ScriptingBridge. A hand-off may now carry "I could not resolve anything" and the app
asks Finder directly. Not a widening of reach — a request naming no path is strictly less capable
than one naming any. Notes: `docs/release-notes/1.0.1.md`.

**1.0.2 — 2026-09-25.** Two things, plus the About box.

- **One delegate, one run loop.** `SettingsWindow.run` and `AboutWindow.run` each installed their
  own `NSApplicationDelegate` and called `NSApplication.run()` a second time, re-entrantly, from
  inside `application(_:open:)`. Three user-visible faults came out of that single cause: a window
  that appeared only sometimes (built in an `applicationDidFinishLaunching` already delivered, so
  it depended on Apple Event timing); a toolbar click answered by whichever window had displaced
  the delegate, which raised itself and discarded the request — clicking for a terminal produced
  the About box; and a declined request calling `exit(1)` with a window still on screen.
  `LaunchCoordinator` is now the only delegate, `run()` is called once, the window hosts are
  factories that touch `NSApp` nowhere, and the process lives exactly as long as a window is up.
  `applicationShouldHandleReopen` is implemented, which nothing had been listening for.
- **Settings lists only what is installed.** The greyed-out rows for uninstalled apps are gone —
  a dozen unchoosable rows in the window whose only job is choosing. The full list moved to the
  README under **Supported terminals and editors**, which Settings links to when something is
  missing, and the window sizes itself to its content instead of to a height chosen for the long
  list. This partly revises §5, which specified "the rest dimmed and unselectable".
- **About**, reachable from the menu and as `yatu://about` — a new host on the public entry point,
  parsed by the same strict rules as the rest (§4).

Notes: `docs/release-notes/1.0.2.md`.

**Tests as of 1.0.2: 111 unit, 7 shell.** The new ones are structural, because the 1.0.2 fault was
not reachable from a running test — it existed only in a live app, depended on event timing, and
presented as a dead menu item. `LaunchLifetimeTests` asserts against the *source* that there is one
delegate, one `run()`, one `application(_:open:)`, one delegate assignment, and no `NSApp` in the
window factories. `SupportedAppsDocTests` holds the README's app list to the catalog, since Settings
now links to it. Both follow `BrandTests`' precedent: when the thing worth checking is not reachable
from a test, check the source for the structure that permits the fault.

### M6 — Upstream contribution track (outward-facing, each approved separately) — **not started**

The only substantive milestone left. F1 is the one with a clock on it: it is slated for a *private
vulnerability report* against a project that is still shipping, and it has been open since
2026-09-18. `fix/sandbox-command-injection` exists as a branch on upstream, so check whether any of
this is already in flight before drafting anything. Nothing here is ever cut from this repository —
it is all `~/dev/oss/openinterminal` work (see `CLAUDE.md`).

| Item | Form |
|---|---|
| F1 extension executes a selected file | Reproduce on an upstream build; if confirmed, **private vulnerability report**, then a `contrib/` PR |
| F2 distributed-notification confused deputy | Issue → PR removing the observers |
| F4/F6 copy-path quoting | PR: single-quote quoting instead of the denylist |
| L1 prefs-driven launch, L2 world-readable path log | Public issue with patch; low severity |
| Dead AppleScript helpers, `.travis.yml`, stray entitlements | Cleanup PR |
| GH-287 (icon), GH-288 (Xcode 27) | Already open; the watch task tracks them |

### ~~M6a — Ship the editor app~~ — **dropped 2026-09-23**
Superseded by §9. The extension's menu carries a **Send to editor** section, so the editor role is
reachable without a second bundle to sign, notarize, icon and explain. `YatuKit` keeps the role and
its tests; `Sources/YatuEditor` is retired.

**Done 2026-09-23.** `Sources/YatuEditor/` and its `Package.swift` product and target are gone, and
`bin/build.sh` builds one app rather than two. `Role.editor` stays — `Catalog`, `FinderTarget`'s
editor rules, `MenuModel` and the settings window all use it, and the 60 tests passed untouched.
`Role.editor.bundleIdentifier` now names a bundle that does not exist; it is kept as the role's
stable identity and the comment says so.

### M7 — Optional, after 1.0
- App Sandbox spike on a topic branch (`sandbox-spike`): `app-sandbox` plus temporary Apple Events exceptions for
  `com.apple.finder` and the catalog's bundle ids. Ship only if launching a Finder-derived folder works
  without an `NSUserAppleScriptTask` helper, or if that one-time install step proves acceptable.
- Optional extras only if wanted: multiple selected folders each in a tab; a Services entry;
  a second cask for an editor variant.

## 8. Questions — all answered 2026-09-18

1. **Repo layout — settled: two repositories, no rename.** `inquinity/OpenInTerminal` turns out
   **not** to be a GitHub fork (it was pushed from a clone), and
   [PR GH-287](https://github.com/Ji4n1ng/OpenInTerminal/pull/287) is open from it
   cross-repository. GitHub follows renames, so renaming it to `yatu` would have moved that live
   PR's head repository under the product's name. It therefore keeps its name and becomes the
   contribution clone at `~/dev/oss/openinterminal` (`master`, six pre-split commits left in
   place, not force-pushed away). Yatu gets a **new** public repository, `inquinity/yatu`, cloned
   at `~/dev/projects/yatu` on `main`. See `docs/UPSTREAM.md`.

2. **Minimum macOS — settled: 13.0 (Ventura).** Xcode 27's `MacOSX27.0.sdk` declares
   `MinimumDeploymentTarget = 12.0`, so 12.0 remains available and only 10.x/11.x are refused —
   that is what commit `144cf5b` was about, and it is unrelated to Xcode 27 itself requiring
   macOS 26.6 to *run*. The floor was therefore a product choice. 13.0 buys `.formStyle(.grouped)`,
   `LabeledContent` and `NavigationStack` for §5's settings window; 12.0 would have cost
   hand-rolled layout or AppKit and bought back only 2015-era hardware, which can still run
   upstream's 10.13-target build. Neither version receives Apple security updates as of 2026-09.

3. **The rest of the upstream tree — settled: keep. Reversed 2026-09-23: removed (§9.7).**
   `OpenInTerminal/`, the Finder extension, the helper and `OpenInEditor-Lite` were to stay,
   documented as unsupported, so syncs stayed trivial. Once the product compiled only three
   upstream files, 289 unbuilt ones were cost without benefit; the reference copy lives in
   `~/dev/oss/openinterminal`.

4. **Signed tags — settled: yes.** SSH signing is set up (`~/.ssh/git-signing`, ed25519, passphrase
   in the vault; `commit.gpgsign` and `tag.gpgsign` on). `~/.ssh/allowed_signers` carries **two
   principal lines for the same address in different capitalizations** —
   `robert@AltmanSoftwareDesign.com` (what `user.email` is set to, and what every commit here
   carries) and the all-lowercase `robert@altmansoftwaredesign.com` — both mapped to the same key,
   because git matches the signer principal as a case-sensitive literal and would otherwise report
   "no principal matched" on our own commits. GitHub matches addresses case-insensitively, so this
   affects local `--show-signature` only. So `just release` creates **signed annotated tags**, and
   `bin/publish-release.sh` uses `gh release create --verify-tag`.
   Remaining step, outside this plan: upload the public key to GitHub as a **signing** key
   (`gh ssh-key add ~/.ssh/git-signing.pub --type signing`) so commits and tags show Verified.

5. **Old cask — ~~delete outright, no deprecation period~~. Reversed 2026-09-24: it stays.**
   `openinterminal-lite-inquinity` remains in the tap, because it may still be wanted for older
   Macs that Yatu's macOS 13 floor excludes. That makes M5 simpler rather than harder — there is no
   removal to sequence, no window where an installed machine points at a deleted cask, and the two
   can coexist. They coexist by having different bundle ids and preference domains; the migration
   that once read the old app's preference was dropped (M3).

6. **Icon — settled: a folder with a prompt caret, "Violet Folder."** A board of seven concepts
   was drawn in `docs/icon-concepts/`; concept 7 (an aperture) was chosen on 2026-09-18 and then
   **replaced on 2026-09-21**, for a reason the board could not show. Set beside the real toolbar
   art of OpenInTerminal, OpenInTerminal-Lite and Go2Shell, the aperture-with-caret was the same
   silhouette as all three — every neighbour is a terminal-window motif with a prompt in it — and
   the colour that distinguished it does not survive at toolbar size. A folder is the one shape none
   of them use, and it says what Yatu does: open a terminal *at a folder*.

   The mark keeps concept 7's palette and construction. The tile is a violet field, a white folder
   outline filled black, and an amber caret set low and left; the toolbar glyph is the same folder
   and caret in one grey ink with nothing behind it. Where a single-ink tile is ever needed it is
   the regular light-on-dark form (`bin/make-icon.swift --monochrome`); the inverted form is
   rejected, because the mark is carried by a bright caret on black and inverting collapses all of
   its contrasts at once.

   The concepts were drawn from geometry rather than generated, so `bin/make-icon.swift` *is* the
   production art and writes a flat `.icns`. `docs/icon-concepts/make-concepts.swift` stays frozen as
   the record of the round.

   **Correction, 2026-09-22.** This section used to say Icon Composer "stopped rendering on macOS
   26.6". That is not supported: the GH-283 fix removed *duplicate* icon sources, not the format,
   and Icon Composer is Apple's documented implementation. The implementation choice is reopened;
   the facts are in [docs/FINDER-TOOLBAR-ICONS.md](FINDER-TOOLBAR-ICONS.md).

   **The `.icns` is not one drawing at ten sizes.** A Finder toolbar is a row of outline glyphs,
   and a colour tile dropped into that row looks wrong. A *grey* tile is no better — it is still a
   filled block among outlines — so the small representations are a true **template glyph**: one
   ink on transparent, at full canvas because there is no tile to sit inside. Upstream solved the
   same problem by being a glyph at every size, which is right for the toolbar and wrong for the
   Dock; macOS picks a representation by size, so one bundle can be both. 16pt and 32pt carry the
   glyph, 128pt and up the colour tile. Verified from the built bundle by measuring what `NSImage`
   serves per pixel size: glyph through 64px, colour from 96px.

   **macOS picks by size alone.** It never says whether the caller is the toolbar or a list row, so
   the toolbar and Finder's smaller views are the same request. Anything that is monochrome in the
   toolbar is monochrome in list view and small icon view too; colour appears in the Dock, Get
   Info and Quick Look.

   **Reversed 2026-09-23: colour at every size.** The paragraph above is kept because it is the
   record of a trade that was correct when it was made and stopped being correct. Its whole premise
   was that the Finder toolbar draws the app icon. The Finder Sync extension (§9) ended that: the
   toolbar button draws its own template symbol, `yatu.folder.caret`, and never asks for the app
   icon. The split then had nothing left to buy — and the cost it had always carried, named two
   paragraphs down as "anything that is monochrome in the toolbar is monochrome in list view and
   small icon view too", was all that remained. In Finder's list view Yatu was the only outline
   glyph in a column of colour tiles, and on a selected row it nearly vanished. `bin/make-icon.swift`
   now ships `.always(.colour)`; `--by-size` still reaches the old behaviour, and `--glyph` still
   draws the one-ink form if a monochrome asset is ever wanted. The one place the app icon still
   lands in a toolbar is ⌘-drag, where a colour tile on a grey plate is exactly what `README.md`
   says to expect.

   **The glyph has a stroke floor** of 1.8px. At 16px a proportional stroke is ~1.2px and the
   caret collapsed into two grey dots; the floor keeps it a caret. This was found by looking at the
   real pixels, not by reasoning.

   **The next two paragraphs are historical (superseded 2026-09-23).** They describe the app icon
   drawn in a ⌘-dragged toolbar item, which is now only the fallback path (§9.5). The extension's
   button draws its own template symbol. The "still unchecked" items at the end of the second
   paragraph were overtaken by the colour-at-every-size decision above and are no longer open.

   **The glyph cannot be tinted by the system, and does not need to be.** macOS does not tint an
   app icon the way it tints a real template image, so the ink is one mid grey. Observed on macOS
   26.6 in light and dark appearance, with the Finder window active and inactive (screenshots,
   2026-09-21, one Mac): the toolbar draws a light grey plate behind neutral app icons, and it stays
   light in dark mode, so the glyph is legible against it in both. When the window is inactive the
   toolbar dims: the neutral icons drop to a mid-grey plate with lower contrast but keep their shape,
   while OpenInTerminal's blue tile goes to dark grey and its bolt to a faint circle.

   That is a second reason colour cannot carry identity in a Finder toolbar: it is removed whenever
   the window loses focus. Differentiation has to come from silhouette, which is why the mark is a
   folder. If the glyph ever proves too weak, the fallback is the single-ink tile (`--monochrome`).
   Still unchecked: the 16px list-view representation on a 1x display, and an end-to-end launch.

   **Precedent, for the record.** No Finder toolbar app found uses a saturated colour tile in its
   toolbar art except the full OpenInTerminal app, whose blue tile is the outlier in its own row.
   Go2Shell ships neutral toolbar-only art distinct from its app icon; OpenInTerminal-Lite is a grey
   outline glyph at every size. Sample of three, local only; no web survey was done.

## 9. Adopting a Finder Sync extension — decided 2026-09-23

Decided after building a working prototype; the evidence is in
[docs/FINDER-TOOLBAR-ICONS.md](FINDER-TOOLBAR-ICONS.md) §6. In short: an application dragged into
Finder's toolbar is drawn as its **app icon**, which cannot be a template, is restyled by the four
icon styles, and is desaturated when the window is inactive. An extension supplies a **template
image** the system tints, appears in the customisation palette by name, and is unaffected by all of
that. The prototype also showed a single click can perform an action, so nothing is lost.

### 9.1 Shape

```
Yatu.app
├── Contents/MacOS/YatuTerminal              unsandboxed; owns preferences and every rule
├── Contents/PlugIns/YatuFinderSync.appex    sandboxed; reports context, executes nothing
└── Contents/Resources/Assets.car            app icon + the toolbar symbol
```

**The division is the security property.** The extension resolves nothing, launches nothing and
executes nothing; it reports what Finder is showing and hands off. Rule 3's directory resolution,
rule 5's compiled-in templates and the catalog allowlist all stay in `YatuKit` where they are
already tested. Upstream's extension does the opposite — it runs an installed AppleScript, which is
where finding F1 lives. Ours closes F1 by construction.

No app group: the extension keeps its own sandbox and cannot read the app's preferences. That is
accepted, and it is why the menu does not mark the current default.

### 9.2 Interaction

| Gesture | Behaviour |
|---|---|
| Click | Open the default terminal at the resolved target |
| ⌥-click | Menu: **Set default terminal program** (sets it), **Send to editor** (opens the editor role), **Settings…** |

Items under "Set default terminal program" change the default; they do not open anything. The
wording carries what a checkmark would, since the extension cannot read the current value.

### 9.3 Milestones

- **M2e — the extension — done 2026-09-23.** `Sources/YatuFinderSync/`; hand-off over a `yatu://` URL parsed and
  validated in `YatuKit`; a URL handler in the app that applies `FinderTarget`'s rules to the
  reported context; menu construction as a pure function returning item descriptors so it is
  testable without Finder. Carries the prototype's lessons: nothing slow inside `menu(for:)`,
  resolution and icons cached and persisted, icons rasterised, hand-off off the callback thread.
- **M1b — icons. Toolbar half done 2026-09-23.** The toolbar symbol is `yatu.folder.caret`, a
  custom SF Symbol derived from Apple's exported `folder` template by `bin/make-symbol.swift` and
  compiled into the extension's own bundle by `actool`, so it carries system metrics and tints with
  the toolbar. Two variants were built and compared at 16–64pt: the caret **on the folder face**
  won; the caret **as a corner badge** collapses to a blob below 24pt and borrows
  `folder.badge.plus`'s "add to folder" grammar. The earlier worry — that interior detail dies at
  toolbar size, since all 20 system `folder.*` symbols badge at the corner — did not apply, because
  a chevron is one stroke rather than detail. It is Apple-derived artwork and carries Apple's
  licence, not ours; see §9.8 and `docs/UPSTREAM.md`.
  **App icon done 2026-09-23 too.** The violet tile already shipped at 128pt and up; the size split
  that kept 16 and 32pt monochrome is gone, so every representation is now the colour tile and Yatu
  looks like an application in list view, Get Info and Spotlight. See §8.6.
  **Still open:** the *format*. A flat `.icns` can vary art by size and an Icon Composer `.icon`
  document cannot — but now that nothing needs the art to vary, that difference no longer argues
  for either. Decide on the merits of the format itself, not on the size split.
- **M4 additions.** `bin/build.sh` assembles and signs the `.appex` *before* the app, with its own
  entitlements; `actool` compiles the app icon and the symbol set; Xcode becomes a build
  requirement. Verification asserts the extension is sandboxed and the app is not.
- **M5 changes.** Cask caveats: enable the extension in System Settings, then add the item with
  **View → Customize Toolbar** — not by ⌘-dragging the app. `zap` gains the extension's container
  and caches.
- **M2d additions.** Unit tests for URL parsing and the rejection of malformed input; menu model
  tests; `bin/attack-matrix.sh` extended to fire hostile paths at the `yatu://` handler directly;
  manual checklist covering enable, add, click, ⌥-click, the four icon styles and an inactive window.
- **Security review** of the new entry point — **done 2026-09-24**, notes in
  `security-review/yatu-url-2026-09-24.md` (git-excluded). No High or Critical. **L1 and F1 are
  confirmed closed**: the catalog allowlist is applied on write *and* on parse, argument vectors are
  compiled-in constants, and the terminal role can only ever receive a directory. One **Medium**
  is open and needs a decision — see §9.9. Three Lows are accepted residual: `yatu://open` launching
  a catalog app at a caller-chosen path (already accepted in §9.4), no rate limit on the scheme, and
  a narrow TOCTOU between the directory check and Terminal.app's `open`.

### 9.4 The new risk

A URL scheme is **public**: any application or web page can invoke `yatu://open?path=…`. The app
treats it as untrusted input and applies the same rules as Finder input — a terminal still only ever
receives an existing directory, and the target application is still only ever a catalog entry. But
this converts an app with no entry points into an app with one, and that is what the security review
is for, not a reassurance here.

### 9.6 Noted for later: the catalog deserves no special reverence

Raised 2026-09-23, not yet decided. The only live inheritance from upstream is
`SupportedApps.swift` — a list of terminals and editors with their bundle identifiers. It is worth
remembering what that list is and is not:

- It is **not an authoritative or community-maintained source** the way something like
  endoflife.date is. It is one maintainer's list, changed 21 times in three years, almost always to
  add an app someone asked for.
- It is **partly wrong**: `com.apple.Xcode` has not been Xcode's bundle identifier for years, and
  `com.sublimetext.3` is two major versions stale. Yatu only survives those because `Launcher`
  falls back to an explicit `/Applications/<name>.app`.
- The set of popular terminals and editors **changes slowly**, so maintaining it ourselves is a few
  edits a year, not a burden.

**Settled 2026-09-23, with the cut (§9.7): vendored verbatim for now, owned later.** The list came
across unchanged, stale identifiers and all, because changing code and changing its content in the
same move makes neither reviewable. `bin/check-upstream.sh` now diffs catalog *entries* against
upstream's copy, so adopting a change is already a hand edit rather than a merge — which is the
mechanism owning the list requires. Fixing `com.apple.Xcode` and `com.sublimetext.3`, and dropping
entries for apps that no longer exist, is a separate change against a file we now control outright.

### 9.7 Cutting the fork relationship — done 2026-09-23

Measured first: the product compiles **three** upstream files — `SupportedApps.swift` and the two
ScriptingBridge interfaces, the latter unchanged since 2019 and regenerable from Apple's `sdef`.
To get them the repository carried **289 unbuilt files** (the full app, the editor app, the Core
framework, upstream's Finder extension, the helper, two Xcode projects, eight localized READMEs).
Upstream had not moved since 2026-07-14, and the bug we reported there (GH-283) is still open.

The reference value of that tree was real — it was read repeatedly while designing §9 — but it is
duplicated in the `~/dev/oss/openinterminal` clone, which keeps its own `upstream` remote and is
where contributions are made. Nothing was lost by removing it from the product repository.

**Done, after M2e**, so two structural changes did not land at once. What happened:

1. The three compiled files were **vendored** — the symlinks into the upstream tree became real
   files, each with a provenance header naming the upstream path and the commit it was taken at.
   Verified by the same 60 tests, unchanged.
2. The tree, both Xcode projects, the root build scripts, upstream's localized READMEs, donation
   images and dynamic app icons were **deleted** — 293 files, ~20,300 lines.
3. `bin/build-unsigned.sh`, `bin/build-signed.sh` (which drove the removed Xcode workspace) and
   `bin/show-private-changes.sh` (which diffed against upstream) were deleted with it. Signing
   returns in M4, in `bin/build.sh`.
4. `bin/check-upstream.sh` was rewritten to compare **catalog entries** against upstream's current
   copy instead of counting commits, preferring the contribution clone and falling back to HTTP.
   `bin/which-yatu.sh` was rewritten to report Yatu, whether its extension is registered and
   enabled, and any superseded app still installed.
5. `docs/FORK-NOTES.md` became `docs/UPSTREAM.md`; `README.md` and `CLAUDE.md` were rewritten.

The licence and attribution obligations did not change: the MIT notice stays, and credit stays in
`README.md`, in `Sources/YatuUpstream/README.md` and in every vendored file's header — worded
**uses code from**, not "fork of".

**Rollback:** the three steps are separate commits on `cut-upstream`; reverting the merge restores
the tree in full.

### 9.9 `set-default` over an unauthenticated channel — settled 2026-09-24, Low

`yatu://set-default?role=terminal&app=Warp` changes a stored preference on behalf of a caller the
app cannot identify. Any local process, or a web page, can silently repoint the toolbar button at a
different **installed, catalog** terminal or editor.

The security review of 2026-09-24 called this Medium. Testing the launch path
([LAUNCH-SECURITY.md](LAUNCH-SECURITY.md)) **collapsed it to Low**, for a reason that is worth
keeping: the worst an attacker achieves is pointing Yatu at an application that is either blocked by
Gatekeeper, gated behind a consent prompt Yatu cannot answer, or already trusted by the user. The
catalog allowlist already prevented naming an arbitrary binary, so finding L1 stays closed, and
Gatekeeper closes the rest.

**Sender verification was investigated and withdrawn.** The Apple Event delivering a URL carries
`keySenderPIDAttr`, and `SecCodeCopyGuestWithAttributes` plus `SecCodeCheckValidity` can hold that
PID to a code requirement — verified working against a live sender. Two things stopped it. The
requirement has to include `anchor apple generic` and the team OU to mean anything at all: an
identifier-only requirement is satisfied by any ad-hoc signed binary claiming that identifier, which
takes about ten seconds, so the check would have been decorative in exactly the builds where it is
easiest to get wrong. And it cannot work in a development build, where there is no team identifier.
Set against a Low finding whose payoff Gatekeeper already denies, it is not worth the code. If the
hand-off ever moves to XPC, `SecCodeCreateWithXPCMessage` gives an audit token and the whole
question disappears — but that reopens the app-group decision §9.1 closed deliberately.

**What remains worth doing is not a security control.** A default changing without the user seeing
it is poor behaviour regardless of who changed it: a notification with an undo, and a durable log
entry, so the change is visible and traceable. Tracked as ordinary work, not as a finding.

### 9.5 What stays

- **Dragging the app into the toolbar still works.** Anyone who does not enable the extension keeps
  a working button; it is drawn as the app icon, with the plate and restyling that implies.
- The settings window (§5) is unchanged and remains where defaults are seen and changed.
- Upstream's own Finder extension stays untouched and unsupported, as `CLAUDE.md` says. Yatu's is
  new, fork-owned code and is not that extension.
