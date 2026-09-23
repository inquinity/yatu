# Yatu — agent guide

**Yatu** is a Finder toolbar button that opens a terminal at the folder you are looking at.
Bundle id `com.altmansoftwaredesign.yatu`, team `45GJWJVQN2`, distributed as the `yatu` cask in
`inquinity/homebrew-tap`.

Read **[docs/YATU-PLAN.md](docs/YATU-PLAN.md)** for what is being built and why, and
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
>   surface. Review notes live in `.security-review/`, git-excluded on purpose (they contain a
>   working attack log). Summary in `docs/UPSTREAM.md`.

## Build and check

```bash
bin/build.sh                                # assemble Yatu.app into dist/
swift test                                  # 87 tests
bin/test-scripts.sh                         # shell tests (pluginkit is stubbed)
bin/which-yatu.sh                           # what is installed; is the extension enabled?
bin/check-upstream.sh                       # has upstream's app catalog moved?
just lint                                   # shellcheck every script
just --list                                 # every task
```

`bin/build.sh` operates on the repo, not the caller's directory. It assembles and signs the
`.appex` before the app, then asserts that the extension is sandboxed and the app is not — a
failure there is a refusal to ship, not a warning.

There is no Xcode project. Signing and notarisation return in M4.
