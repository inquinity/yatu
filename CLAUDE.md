# OpenInTerminal fork — agent guide

> ## ⚠️ FORK STATUS — read before acting on anything in this repo
>
> This is **[inquinity/OpenInTerminal](https://github.com/inquinity/OpenInTerminal)**, a fork of
> [Ji4n1ng/OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal). Read
> **[docs/FORK-NOTES.md](docs/FORK-NOTES.md)** first — it is the source of truth for how this
> repository differs from upstream, and **[docs/YATU-PLAN.md](docs/YATU-PLAN.md)** for what is being
> built.
>
> - **The product of this fork is Yatu**, a private-label build of OpenInTerminal-Lite:
>   bundle id `com.altmansoftwaredesign.yatu`, team `45GJWJVQN2`, distributed as the `yatu` cask in
>   `inquinity/homebrew-tap`. The name in `README.md` and throughout the upstream tree is still
>   OpenInTerminal; that is upstream's, not ours.
> - **We ship one app.** The full `OpenInTerminal/` app, the Finder extension, the login helper and
>   `OpenInEditor-Lite/` are kept untouched and unsupported. Do not "fix" them here — their findings
>   go upstream (see the contribution track in the fork notes). Yatu does carry an **editor role**
>   of its own (`Yatu Edit`, built and tested but not shipped in 1.0 — see §4.1 of the plan); that
>   is fork-owned code, not upstream's target.
> - **Build scripts:** use the fork-owned copies in `bin/` (`bin/build-unsigned.sh`,
>   `bin/build-signed.sh`). The identically named scripts at the repo root are upstream's and are
>   left alone so merges stay clean. `bin/build-signed.sh` needs the Developer ID for team
>   `45GJWJVQN2` and `NOTARY_PROFILE=altman-notary`.
> - **Upstream's release runbook has been deleted** from `.claude/skills/`. It drove the upstream
>   maintainer's account, certificate and paths. Releases here go through `bin/` and the `justfile`.
> - **Two remotes:** `origin` (inquinity) and `upstream` (Ji4n1ng, read-only). Sync with
>   `git merge upstream/master`. **Never rebase `main`** — it is published. `git rerere` is on.
> - **Merge commits are prefixed** `Fork:` (our change) or `Sync:` (an upstream merge).
> - **Upstream contributions go on a `contrib/<topic>` branch** cut from `upstream/master`, carrying
>   only the fix being offered — never our private-label work.
> - **New files are free; edits to upstream-maintained files are rent.** Prefer adding a file over
>   editing `OpenInTerminalCore/`, the Xcode projects or the app targets. Every rent-paying edit is
>   listed in the fork notes.
> - **This repository is public.** In commits, PRs and comments, refer to upstream issues by full URL
>   or `GH-287` — never a bare `#287` or `Ji4n1ng/OpenInTerminal#287`, which auto-links into
>   upstream's timeline permanently.
> - **Review incoming upstream changes for security** on every sync, with the
>   `security-oss-app-reviewer` skill. This app launches other programs with paths taken from Finder;
>   that is the whole attack surface.
> - **Security review notes live in `.security-review/`** and are git-excluded on purpose (they
>   contain a working attack log). Summary in the fork notes.

## Build and check

```bash
bin/build-unsigned.sh                       # local ad-hoc build of all three upstream apps
NOTARY_PROFILE=altman-notary bin/build-signed.sh OpenInTerminal-Lite
bin/which-yatu.sh                           # what is installed, and where it came from
bin/check-upstream.sh                       # has upstream moved?
bin/show-private-changes.sh --stat          # what this fork changes
just --list                                 # the same, via just
```

Both build scripts operate on the repo, not the caller's directory, and delete `export/` before
building.

## Upstream's own notes

Upstream ships no `CLAUDE.md` or `AGENTS.md`. `README.md` is upstream's, describes their three apps,
and will be rewritten for Yatu when the app exists (see the plan).
