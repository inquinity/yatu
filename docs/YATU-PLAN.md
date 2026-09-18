# Yatu — private-label plan

Status: **draft for review**, 2026-09-18. Nothing here is implemented yet.
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
| Functional base | **OpenInTerminal-Lite**, kept as the upstream to merge from |
| Structure | **Swift package**, built into an app bundle by script — modelled on [sozercan/OpenInCode](https://github.com/sozercan/OpenInCode) |
| Headline feature | A **settings window** for choosing the terminal, which OITL lacks |
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
yatu/                            (repo root, the fork)
├── Package.swift                executable target "Yatu", no dependencies
├── Sources/Yatu/
│   ├── main.swift               entry: ⌥ → settings, else open terminal
│   ├── FinderTarget.swift       Finder query; no force-casts; always resolves to a directory
│   ├── Launcher.swift           NSWorkspace launch; compiled-in argument templates
│   ├── Settings.swift           allowlisted terminal choice; one-time migration from OITL
│   ├── SettingsWindow.swift     the new GUI (§5)
│   ├── TerminalCatalog.swift    thin wrapper over upstream's SupportedApps
│   └── Log.swift                os.Logger; paths marked .private
├── Sources/YatuUpstream/        upstream files compiled UNCHANGED (see below)
├── Tests/YatuTests/             path resolution, validation, migration, catalog
├── Resources/                   Info.plist, entitlements, icon, terminal icons, strings
├── bin/                         build.sh, publish-release.sh, check-upstream.sh,
│                                show-private-changes.sh, attack-matrix.sh, make-icon.swift
├── docs/                        FORK-NOTES.md, this plan, MANUAL-TEST-CHECKLIST.md, release-notes/
├── justfile                     just build | test | release <seg> | publish --go
└── (upstream tree kept as-is: OpenInTerminal*/ , OpenInTerminalCore/ , *.xcodeproj)
```

**Upstream files compiled unchanged** (symlinked or path-referenced into `Sources/YatuUpstream`):
`OpenInTerminalCore/SupportedApps.swift`, `ScriptingBridge/Finder.swift`,
`ScriptingBridge/Terminal.swift`, and `App.swift` only if the spike shows its dependency
chain can be cut. Upstream fixes to these arrive with a `Sync:` merge for free.

**Spike M2a (½ day), decides the compile set.** `App.swift` reaches `DefaultsManager` →
`Defaults` → `Log`. If that can't be cut without editing upstream files, Yatu defines its own
2-field model type and compiles only `SupportedApps.swift` plus the two ScriptingBridge files.
Either way **no upstream file is edited**; anything else is copied into `Sources/Yatu` with
provenance in a header comment.

**Behavioural rules, each with a unit test:**
1. The chosen terminal must exist in the catalog; resolution is by bundle id, never by name.
2. Catalog entries without a bundle id (GitHub Desktop, Fork) are resolved by an explicit
   `/Applications` path or dropped.
3. A path handed to a terminal is always an existing directory — never a file, a symlink to a
   file, or an `.app`/`.command` bundle.
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
  - "open a new window" vs "new tab" where the terminal supports both (Terminal.app, iTerm);
  - a **Reveal in Finder** line naming the resolved app bundle, so the user sees exactly what will launch;
  - a footer: version, build, "based on OpenInTerminal-Lite X.Y.Z", and a link to the source.
- **Implementation:** SwiftUI window, AppKit host. Needs macOS 13 (§8, Q3 default).
- **What it must not do:** offer a free-text command or app path. That is finding L1, and the
  allowlist is the fix. If a user needs an unsupported terminal, the answer is a catalog entry
  in a release, not a text field.

## 6. Fork conventions (from Belvedere)

- `docs/FORK-NOTES.md` is the source of truth: why the fork exists, remote table, branch model,
  what we change, upstream contribution track, roadmap.
- `README.md` rewritten for Yatu with a **Credits** section naming OpenInTerminal and Jianing Wang;
  `CLAUDE.md` gets a **FORK STATUS** block telling agents which upstream text to ignore.
- Remotes: `origin` (inquinity) and `upstream` (Ji4n1ng, read-only). `git rerere` enabled.
- Branches: `master` is the product line; `fork/<topic>` short-lived, merged `--no-ff`;
  `contrib/<topic>` cut from `upstream/master`, one fix each, for PRs to upstream.
- Merge commits: `Fork: <what>` and `Sync: upstream/master @ <sha>`. **Merge, never rebase** `master`.
- "New files are free. Edits to upstream-maintained files are rent." Every rent-paying edit is
  listed in FORK-NOTES.
- Public-repo writing: refer to upstream with full URLs or `GH-287`, never a bare `#287` or
  `owner/repo#287` (S7 — we already tripped this once in the tap commit and release notes).
- Every upstream sync gets a security review of the incoming diff (`security-oss-app-reviewer`).

## 7. Milestones

Risk gates per `~/.claude/CLAUDE.md`. M4 and M5 are outward-facing and need separate approval
before anything is published.

### M0 — Fork scaffolding (low)
- `docs/FORK-NOTES.md`, README fork banner, `CLAUDE.md` FORK STATUS block.
- `bin/check-upstream.sh`, `bin/show-private-changes.sh`, `justfile`, `git rerere`.
- Remove upstream-only automation and leftovers: `.claude/skills/release/` (S4), `.travis.yml`,
  the stray `OpenInTerminal_Lite.entitlements`, `FUNDING.yml`.
- Restore `build-signed.sh` / `build-unsigned.sh` to upstream content — the fork build moves to
  `bin/build.sh` in M4, so we stop paying rent on those two files. `scripts/which-openinterminal.sh`
  becomes `bin/which-yatu.sh`.
- **Verify:** `bin/show-private-changes.sh --stat` lists only intended files. **Rollback:** revert the merge.

### M1 — Identity (low)
- `Version.xcconfig`-equivalent in `Resources/Info.plist` + `bin/ver`; team and bundle id in the
  build script; new icon via `bin/make-icon.swift` (flat asset catalog / `.icns`, **no Icon Composer
  bundle** — that is what broke in 26.6); `NSAppleEventsUsageDescription` written for Yatu;
  copyright "© 2026 Altman Software Design, LLC — portions © 2019 Jianing Wang (MIT)";
  MIT license text shipped in the bundle (the license requires it).
- **Verify:** built app shows Yatu's name and icon; `defaults domains` shows only the new domain.

### M2 — The app (medium: app logic)
- **M2a** compile-set spike (§4). **M2b** the sources in §4 with their seven rules.
- **M2c** the settings window (§5).
- **M2d** tests: unit tests for rules 1–6; `bin/attack-matrix.sh` automating the hostile-name and
  canary-app matrix from the dynamic review (scratch only, prefs backed up and restored);
  `docs/MANUAL-TEST-CHECKLIST.md` with EXPECT / FAIL IF lines.
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
- New cask `yatu`: sha256-pinned, `depends_on macos:`, `uninstall quit:`, `zap` covering the prefs
  plist and Saved Application State, `caveats` for the toolbar button and
  `tccutil reset AppleEvents com.altmansoftwaredesign.yatu`, `livecheck` on our releases.
- `openinterminal-lite-inquinity` gets `deprecate!` pointing at `yatu`, removed one release later (Q6).
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

### M7 — Optional, after 1.0
- App Sandbox spike on `fork/sandbox-spike`: `app-sandbox` plus temporary Apple Events exceptions for
  `com.apple.finder` and the catalog's bundle ids. Ship only if launching a Finder-derived folder works
  without an `NSUserAppleScriptTask` helper, or if that one-time install step proves acceptable.
- Optional extras only if wanted: multiple selected folders each in a tab; a Services entry;
  a second cask for an editor variant.

## 8. Open questions (defaults proposed — say "as proposed" to accept all)

1. **Repo name.** Rename `inquinity/OpenInTerminal` → `inquinity/yatu`? GitHub keeps the fork link and
   redirects the old URL. *Default: rename at M1.*
2. **Minimum macOS.** 12.0 (today's floor), or 13.0 (simpler SwiftUI settings window)?
   *Default: 13.0.*
3. **The rest of the upstream tree.** Keep `OpenInTerminal/`, the Finder extension, the helper and
   `OpenInEditor-Lite` in the repo, untouched and unsupported, so syncs stay trivial — or delete them?
   *Default: keep, documented as unsupported and not built.*
4. **Signed tags — settled 2026-09-18: yes.** SSH signing is set up (`~/.ssh/git-signing`,
   ed25519, passphrase in the vault; `commit.gpgsign` and `tag.gpgsign` on;
   `~/.ssh/allowed_signers` carries both spellings of the author email). So `just release`
   creates **signed annotated tags**, and `bin/publish-release.sh` uses `gh release create --verify-tag`.
   Remaining step, outside this plan: upload the public key to GitHub as a *signing* key so commits
   and tags show Verified.
5. **Old cask.** Deprecate with a pointer to `yatu` for one release, then delete — or delete at once?
   *Default: deprecate, then delete.*
6. **Icon.** Commission a concept board the way Belvedere did (`docs/icon-concepts/`), or go straight to
   one design? *Default: a small board of 4–6 concepts, you pick.*
