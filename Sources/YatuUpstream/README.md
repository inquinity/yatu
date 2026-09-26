# YatuUpstream

Code from [OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal) by Jianing
Wang, MIT licensed, vendored **verbatim** (the two ScriptingBridge interfaces) — plus the minimum needed to compile it.

| File | Origin |
|---|---|
| `Finder.swift` | upstream's ScriptingBridge interface, commit `eaa3bd5` (2019-04-17) |
| `Terminal.swift` | upstream's ScriptingBridge interface, commit `eaa3bd5` (2019-04-17) |
| `Model.swift` | ours; the dependency-free `App`/`AppType` declarations lifted from upstream's `App.swift`, with provenance in its header |

Each vendored file carries a provenance header naming the upstream path and
commit it was taken at. Yatu was a fork of that repository until 2026-09-23 and
these files were symlinks into the upstream tree; the tree is gone and the
files are real. See [docs/UPSTREAM.md](../../docs/UPSTREAM.md).

Nothing else from `OpenInTerminalCore` is compiled. Upstream's `App.swift` is
not, because its `Openable` extension pulls in `FinderManager`,
`DefaultsManager`, `ScriptManager`, `Constants`, `OITError` and `logw` — which
is the whole framework, and includes the three components Yatu replaces by
design (findings L1–L3 in [docs/DESIGN.md](../../docs/DESIGN.md) §3).

**Rule:** no vendored file is edited to make Yatu's code work. If upstream's
code needs to behave differently, the new behaviour goes in `Sources/YatuKit/`
and calls into this target, never the other way around.

The app catalog used to be here. It is Yatu's own now, in `Sources/YatuKit/SupportedApps.swift`
(docs/UPSTREAM.md).
