# Fork notes

This repository is a fork of [Ji4n1ng/OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal),
maintained by [inquinity](https://github.com/inquinity). It exists for two reasons:

> **Upstream ships rarely** — 12 to 19 months between the last three releases, with outside PRs
> merged in batches just before one. A fix we need today (the macOS 26.6 Finder toolbar icon)
> would otherwise wait months.
>
> **We want one thing upstream does not have:** a settings window for choosing the terminal.
> OpenInTerminal-Lite asks once, then the choice can only be changed by editing preferences by hand.

The product of this fork is **Yatu**, a Finder toolbar app that opens a terminal at the folder you
are looking at. Everything it does today is upstream's work; see
[docs/YATU-PLAN.md](YATU-PLAN.md) for what is being built and why.

## Relationship to upstream

| Remote | URL | Role |
|---|---|---|
| `origin` | `inquinity/OpenInTerminal` (renaming to `inquinity/yatu`) | This fork. Where our `master` lives. |
| `upstream` | `Ji4n1ng/OpenInTerminal` | The base project. Read-only; never pushed to. |

Upstream moves slowly, so syncs are rare and cheap — but each one still gets a security review of
the incoming diff (`security-oss-app-reviewer`), because a Finder toolbar app runs whatever it is
told to run.

## What we ship, and what we don't

| Part | State |
|---|---|
| OpenInTerminal-Lite → **Yatu** | The product. Developer ID signed by Altman Software Design, LLC (`45GJWJVQN2`), notarized, distributed as the `yatu` cask in [`inquinity/homebrew-tap`](https://github.com/inquinity/homebrew-tap). |
| `OpenInTerminal/` (full app), `OpenInTerminalFinderExtension/`, `OpenInTerminalHelper/`, `OpenInEditor-Lite/` | **Kept, unsupported, not built.** They stay untouched so syncs stay trivial. We do not ship them, and their open findings are upstream's (see below). |
| `OpenInTerminalCore/` | Partly used. Yatu compiles a few of its files unchanged; the rest is upstream's. |

## Branch model

```
upstream/master        remote-tracking only; never a local branch we edit
master       (origin)  our product line: upstream + our changes
fork/<topic>           short-lived; merged with --no-ff, then deleted
contrib/<topic>        cut from upstream/master; ONE fix each; for PRs to Ji4n1ng
```

`contrib/*` branches carry only the fix being offered, never our private-label work, so the PR diff
is exactly what upstream is asked to review. `fix/macos-26-icon-rendering`
([PR GH-287](https://github.com/Ji4n1ng/OpenInTerminal/pull/287)) is effectively the first of these;
it keeps its name while the PR is open.

### Syncing

```bash
bin/check-upstream.sh          # read-only: has upstream moved?
git fetch upstream
git merge upstream/master      # merge, never rebase
```

**Merge, never rebase** `master`: it is published, and rebasing means force-pushing over history
other people hold. `git rerere` is enabled in this clone so each conflict resolution is recorded
once and replayed on later merges. In a fresh clone:

```bash
git config rerere.enabled true
git config rerere.autoupdate true
```

### Merge commit convention

```
Fork: add the settings window
Sync: upstream/master @ a1b2c3d
```

`git log --merges --grep='^Fork:'` is then a complete changelog of everything we have done to the
base project.

### Reviewing what this fork changes

```bash
bin/show-private-changes.sh --stat      # summary
bin/show-private-changes.sh             # full diff
bin/show-private-changes.sh --commits   # commit log
```

## How changes are applied

> **New files are free. Edits to upstream-maintained files are rent.**

Upstream owns `OpenInTerminalCore/`, the Xcode projects and the app targets. Every line we change
there is a line that can conflict on sync, so:

- Fork code lives in new files and directories: `Sources/Yatu/`, `bin/`, `docs/`, `justfile`.
- Upstream files we still want are **compiled unchanged**, not edited.
- Where behaviour must differ, we write our own file rather than patching theirs.
- Fork-owned copies of upstream scripts live in `bin/` (`build-unsigned.sh`, `build-signed.sh`), so
  `git merge upstream/master` never touches them; upstream's originals stay at the repo root.

### Rent we currently pay

| Upstream file | Change | Why |
|---|---|---|
| `OpenInTerminal.xcodeproj/project.pbxproj`, `OpenInTerminal-Lite/…/project.pbxproj` | `AppIcon.icon` removed from the Resources phase | The macOS 26.6 icon bug; offered upstream as [PR GH-287](https://github.com/Ji4n1ng/OpenInTerminal/pull/287) |

Everything else we have added is a new file. Deletions of upstream-only automation
(`.travis.yml`, `.github/FUNDING.yml`, `.claude/skills/release/`, the unused
`OpenInTerminal_Lite.entitlements`) are recorded here so a future sync conflict is resolved by
keeping the deletion.

## Security posture

A full review of the fork (2026-09-16/17) is in `.security-review/` — git-excluded, since it
includes a working attack log. Summary:

- **The shipped Lite build has no injection paths.** ~50 hostile launches with crafted folder and
  file names produced no command execution, and selected `.command`, executables and `.app` bundles
  were never run. This is a property to keep, not a one-off result: `bin/attack-matrix.sh` (M2)
  re-runs that matrix each release.
- **Four Low findings** in what we ship, all fixed by design in Yatu: preferences-driven app launch,
  a world-readable path log, force-casts that can crash on special Finder views, and unstripped
  binaries carrying build paths.
- **Build and release gaps** (unpinned dependency, `rm -rf export` from the caller's directory,
  signing that accepts a dirty tree and never verifies the result) are addressed by `bin/build.sh` in M4.
- **The parts we do not ship carry more** — one High (the Finder extension can hand a *file* to a
  terminal, which runs it) and four Medium. Those go upstream through the contribution track, with
  the High reported privately first.

## Upstream contribution track

Genuine fixes go back upstream; once merged they stop being our diff to carry.

| Finding | Form | Status |
|---|---|---|
| Finder toolbar icons render wrong on macOS 26.6 | PR | **open** — [GH-287](https://github.com/Ji4n1ng/OpenInTerminal/pull/287), fixes [GH-283](https://github.com/Ji4n1ng/OpenInTerminal/issues/283) |
| Build fails on Xcode 27 (deployment targets below macOS 12) | Issue | **open** — [GH-288](https://github.com/Ji4n1ng/OpenInTerminal/issues/288) |
| Extension can hand a selected file to a terminal, which runs it | Private report, then PR | not started — reproduce on an upstream build first |
| `DistributedNotificationCenter` observers accept any local sender | Issue → PR | not started |
| Menu-bar copy-path does no escaping; extension's escaping is a denylist | PR | not started |
| Preferences-driven arbitrary app launch; world-readable path log | Issue with patch | not started |
| Dead AppleScript helpers, `.travis.yml`, stray entitlements | Cleanup PR | not started |

A daily scheduled task (`watch-openinterminal-pr-287`) reports upstream movement.

## Writing for other people

This fork is **public**. Commit messages, PR descriptions and issue comments are readable by anyone.

- Refer to upstream issues and PRs by **full URL or `GH-287`**, never a bare `#287` or
  `Ji4n1ng/OpenInTerminal#287` — those auto-link into upstream's timeline permanently and cannot be
  removed. (We already did this once, in the tap cask commit and the v1.2.8-inquinity.1 release notes.)
- No fork-internal shorthand (`M2a`, `L1`, `FORK-NOTES`) in anything that travels to upstream. Write
  the actual subject.
