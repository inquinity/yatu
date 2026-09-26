# Yatu — agent guide

**Yatu** is a Finder toolbar button that opens a terminal at the folder you are looking at.
Bundle id `com.altmansoftwaredesign.yatu`, team `45GJWJVQN2`, distributed as the `yatu` cask in
`inquinity/homebrew-tap`.

Read **[docs/ROADMAP.md](docs/ROADMAP.md)** for what is being built next,
**[docs/DESIGN.md](docs/DESIGN.md)** for why it is built the way it is, and
**[docs/UPSTREAM.md](docs/UPSTREAM.md)** for the code that comes from OpenInTerminal.

> ## ⚠️ This is no longer a fork — read before acting
>
> Yatu began in a fork of [Ji4n1ng/OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal) and
> **stopped being one on 2026-09-23**. The upstream tree, both Xcode projects and the `upstream`
> merge workflow are gone from this repository.
>
> - **It uses code from OpenInTerminal; it is not a fork of it.** Say it that way in commits, docs
>   and anything public. Three files are vendored in `Sources/YatuUpstream/` — the app catalog and
>   two ScriptingBridge interfaces — each with a provenance header naming the upstream path and
>   commit. **Never edit a vendored file to make Yatu's code work**; new behaviour goes in
>   `Sources/YatuKit/` and calls into that target. The MIT licence and the attribution in
>   `README.md` are obligations, not decoration.
> - **We ship one app, which contains one extension.** Yatu's Finder Sync extension
>   (`Sources/YatuFinderSync/`) is ours, sandboxed, and executes nothing — it reports Finder's
>   context over a `yatu://` URL and stops. Yatu also carries an **editor role** in `YatuKit`,
>   reached from that extension's menu; there is no separate editor app.
> - **`yatu://` is a public entry point.** Any application or web page can invoke it. It is parsed
>   strictly in `Sources/YatuKit/HandOff.swift` and every path is re-validated by `FinderTarget`.
>   Treat changes to either as security-relevant.
> - **Two repositories.** This one — `inquinity/yatu`, branch `main`, at `~/dev/projects/yatu` — is
>   the product. Upstream contributions live in a *separate* clone: `inquinity/OpenInTerminal`,
>   branch `master`, at `~/dev/oss/openinterminal`, which keeps its own `upstream` remote. **No
>   `contrib/*` branch is ever cut here**, and no Yatu work ever lands there.
>   [PR GH-287](https://github.com/Ji4n1ng/OpenInTerminal/pull/287) is open from that repository.
> - **Never rebase `main`** — it is published. Work on a branch and merge. `git rerere` is on.
>   The old `Fork:` / `Sync:` merge prefixes are retired along with the fork; merge commits follow
>   Conventional Commits like everything else.
> - **Upstream changes are noticed, not merged.** `bin/check-upstream.sh` diffs the app catalog
>   against upstream's current copy. Adopting an entry is a hand edit plus a provenance-header
>   update, and a judgement call: upstream's catalog is one project's list, not an authority, and it
>   has shipped stale bundle identifiers. Verify against the real application.
> - **This repository is public.** Refer to upstream issues by full URL or `GH-287` — never a bare
>   `#287` or `Ji4n1ng/OpenInTerminal#287`, which auto-links into upstream's timeline permanently.
> - **Security-review anything touching the launch path** with the `security-oss-app-reviewer`
>   skill. This app launches other programs with paths taken from Finder; that is the whole attack
>   surface. **[docs/LAUNCH-SECURITY.md](docs/LAUNCH-SECURITY.md)** is the public assessment of
>   whether that can be abused — it cannot, because Gatekeeper stops it, and the testing is recorded
>   there. Read it before reasoning about this again from scratch. Review notes live in `security-review/` — **visible on purpose, and git-ignored on
>   purpose**. Those are different decisions: the notes need attention, so they are not hidden in a
>   dot-directory; they contain a working attack log and this repository is public, so they are
>   never committed. Summary in `docs/UPSTREAM.md`.
> - **Do not invent dot-directories.** A leading dot means "a tool owns this and you can ignore it"
>   — `.build` is SwiftPM's, `.github` is a platform convention. Naming our own content
>   `.something` hides material that someone is supposed to read. Keeping a directory out of git is
>   `.gitignore`'s job, not the filename's.

## Build and check

```bash
bin/build.sh                                # assemble Yatu.app into dist/
swift test                                  # 111 tests
bin/test-scripts.sh                         # shell tests (pluginkit is stubbed)
bin/build.sh --release && bin/notarize.sh && bin/package.sh   # a shippable build
bin/release.sh                              # check a release; --go publishes it
bin/attack-matrix.sh --live                 # hostile input at an installed Yatu
bin/which-yatu.sh                           # what is installed; is the extension enabled?
bin/check-upstream.sh                       # has upstream's app catalog moved?
just lint                                   # shellcheck every script
just --list                                 # every task
```

`bin/build.sh` operates on the repo, not the caller's directory. It assembles and signs the
`.appex` before the app, then asserts that the extension is sandboxed and the app is not — a
failure there is a refusal to ship, not a warning.

There is no Xcode project. Release builds are signed with the Developer ID for team
`45GJWJVQN2`, notarised and stapled; `bin/release.sh` refuses to publish an artifact that was not
built from the commit being tagged.

## Release notes

**Write them as the change lands.** A commit that changes what someone using Yatu sees or does
updates `docs/release-notes/UNRELEASED.md` in the same commit.

Notes reconstructed at release time are written from memory about work that has already shipped,
which is how 1.0.0, 1.0.1 and 1.0.2 were all produced. `bin/release.sh` titles that file with the
version and refuses to publish it empty — it cannot tell whether what is in it is true, or whether
anything is missing from it.
