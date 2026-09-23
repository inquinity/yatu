# Yatu — private-label plan

Status: **accepted 2026-09-18**, all questions in §8 answered.
M0 is done; M1 is in progress.
Replaces the earlier `PRIVATE-LABEL-PLAN.md` draft.
Inputs: the security review in `.security-review/` (git-excluded), the Belvedere fork
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

Detail in `.security-review/NOTES.md`. Shipped-app findings, all Low, all fixed by design in §4:

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

```
yatu/                            (repo root)
├── Package.swift                library YatuKit + two executables, no dependencies
├── Sources/YatuKit/             everything below except the entry points
├── Sources/YatuTerminal/
│   └── main.swift               entry: ⌥ → settings, else open the terminal
├── Sources/YatuEditor/
│   └── main.swift               same, for the editor role (§4.1); built, not shipped in 1.0
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
chain can be cut. Upstream fixes to these arrive with a `Sync:` merge for free.

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

Upstream ships two Lite apps — OpenInTerminal-Lite and OpenInEditor-Lite — because a Finder
toolbar button does exactly one thing. Yatu keeps that shape: **one codebase, two executables**,
differing only in which role they ask the shared code for.

| | Terminal (ships in 1.0) | Editor (built, not shipped) |
|---|---|---|
| Bundle id | `com.altmansoftwaredesign.yatu` | `com.altmansoftwaredesign.yatu.editor` |
| App name | Yatu | Yatu Edit |
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
2. Catalog entries without a bundle id (GitHub Desktop, Fork) are resolved by an explicit
   `/Applications` path or dropped.
3. A path handed to a **terminal** is always an existing directory — never a file, a symlink to a
   file, or an `.app`/`.command` bundle. **One** selected item names that directory; a selection of
   **several** is ignored in favour of the folder being viewed, because a terminal opens at exactly
   one place and choosing the "first" of a set would depend on selection order the user neither
   chose nor can see. The **editor** role takes all of them, where order does not matter. The **editor** role may receive files, since opening a
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
  - the terminal list, installed apps first with their real icons, the rest dimmed (the existing picker already does this);
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
- **Verified on this Mac:** `bin/build.sh` produces `Yatu.app` and `Yatu Edit.app`, universal
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
- **M2d** tests: unit tests for rules 1–6 — **done 2026-09-18**, 30 tests. Still outstanding:
  `bin/attack-matrix.sh` automating the hostile-name and canary-app matrix from the dynamic review
  (scratch only, prefs backed up and restored), and `docs/MANUAL-TEST-CHECKLIST.md` with
  EXPECT / FAIL IF lines. Rule 7 and rule 6's *absence* of a log file are not unit-testable and
  belong in the manual checklist.
- **Review:** independent code review plus a security review of the diff.
- **Rollback:** the package is additive; delete it. OITL keeps building.

### M3 — Migration from the current cask (low, local)
- On launch, if no Yatu setting exists, read `LiteDefaultTerminal` from
  `wang.jianing.app.OpenInTerminal-Lite`, validate it against the catalog, adopt it, and log once.
- Cask caveats tell the user to replace the toolbar button and approve the new Automation prompt.
- **Verify:** on this Mac, with the old cask still installed, Yatu adopts "Terminal" without a prompt.

### M4 — Build and release pipeline (medium–high: signing)
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
- `just release <seg>` bumps the version, composes notes from `docs/release-notes/UNRELEASED.md` +
  `ON-TOP-OF-UPSTREAM.md`, commits, and creates a **signed annotated tag** (§8 Q4). `just publish` is a dry run unless `--go`.
- **Rollback:** delete the tag and release; the dry-run default is the guard.

### M5 — Distribution (high: public)

> **The cask is already scaffolded** at `~/dev/projects/homebrew-tap/Casks/yatu.rb` (commit
> `d72443c`, unpushed), marked "not yet installable" with `version "0.0.0"` and `sha256 :no_check`.
> Nothing happens to it until there is a real 1.0.0 to point at. Note when that comes: it was
> written **before** the extension was adopted (§9), so its `caveats` tell the user to add the
> toolbar button but not to *enable the extension* first — which is now the step that decides
> whether the button appears at all — and its `zap` covers the prefs plist and saved state but not
> the extension's container. Both are listed in §9.3 under M5 changes.

- New cask `yatu`: sha256-pinned, `depends_on macos:`, `uninstall quit:`, `zap` covering the prefs
  plist and Saved Application State, `caveats` for the toolbar button and
  `tccutil reset AppleEvents com.altmansoftwaredesign.yatu`, `livecheck` on our releases.
- `openinterminal-lite-inquinity` is **deleted outright, with no deprecation period** (Q5). Order
  matters, because it is installed on this Mac: install `yatu`, then
  `brew uninstall --cask openinterminal-lite-inquinity` on **both** Macs, and only then delete the
  cask from the tap — removing it while an install still points at it makes `brew update` error
  on that machine. The old cask's `url`, `homepage` and README row keep naming
  `inquinity/OpenInTerminal` until that moment and are **not** repointed — the
  `v1.2.8-inquinity.1` release they resolve to lives in that repository and stays there. The new
  `yatu` cask is a separate file pointing at `inquinity/yatu` releases; the old row is deleted
  from the tap README rather than edited.
- Update the tap README, `bin/which-yatu.sh`, the daily upstream-watch task, and the project memory.
- Migrate this Mac, then the second Mac. The icon-cache confusion disappears once the bundle id differs.

### M6 — Upstream contribution track (outward-facing, each approved separately)
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

### M7 — Optional, after 1.0
- App Sandbox spike on `fork/sandbox-spike`: `app-sandbox` plus temporary Apple Events exceptions for
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

3. **The rest of the upstream tree — settled: keep.** `OpenInTerminal/`, the Finder extension, the
   helper and `OpenInEditor-Lite` stay in the repository, documented as unsupported and not built,
   so syncs stay trivial.

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

5. **Old cask — settled: delete outright, no deprecation period.** Sequencing in M5.

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

   **The glyph has a stroke floor** of 1.8px. At 16px a proportional stroke is ~1.2px and the
   caret collapsed into two grey dots; the floor keeps it a caret. This was found by looking at the
   real pixels, not by reasoning.

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
  **Still open:** the app icon. The violet tile already ships at 128pt and up — `bin/make-icon.swift`
  draws glyph ≤32pt and colour above — so "back to colour" was largely already true. What is
  actually open is the *format*: flat `.icns` with art that varies by size, or an Icon Composer
  `.icon` document, which cannot vary by size. Now that the extension draws its own symbol, the
  size split only serves ⌘-drag.
- **M4 additions.** `bin/build.sh` assembles and signs the `.appex` *before* the app, with its own
  entitlements; `actool` compiles the app icon and the symbol set; Xcode becomes a build
  requirement. Verification asserts the extension is sandboxed and the app is not.
- **M5 changes.** Cask caveats: enable the extension in System Settings, then add the item with
  **View → Customize Toolbar** — not by ⌘-dragging the app. `zap` gains the extension's container
  and caches.
- **M2d additions.** Unit tests for URL parsing and the rejection of malformed input; menu model
  tests; `bin/attack-matrix.sh` extended to fire hostile paths at the `yatu://` handler directly;
  manual checklist covering enable, add, click, ⌥-click, the four icon styles and an inactive window.
- **Security review** of the new entry point, before merge.

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

### 9.5 What stays

- **Dragging the app into the toolbar still works.** Anyone who does not enable the extension keeps
  a working button; it is drawn as the app icon, with the plate and restyling that implies.
- The settings window (§5) is unchanged and remains where defaults are seen and changed.
- Upstream's own Finder extension stays untouched and unsupported, as `CLAUDE.md` says. Yatu's is
  new, fork-owned code and is not that extension.
