# YatuUpstream

Upstream files compiled **unchanged**, plus the minimum needed to make them compile.

| File | Origin |
|---|---|
| `SupportedApps.swift` | symlink to `../../OpenInTerminalCore/SupportedApps.swift` — upstream's, never edited |
| `Model.swift` | ours; the dependency-free `App`/`AppType` declarations lifted from upstream's `App.swift`, with provenance in its header |

The symlink is the point: upstream adds a terminal to the catalog, we merge, and
Yatu has it — no diff to carry. Nothing else from `OpenInTerminalCore/` is
compiled. Upstream's `App.swift` is not, because its `Openable` extension pulls
in `FinderManager`, `DefaultsManager`, `ScriptManager`, `Constants`, `OITError`
and `logw` — which is the whole framework, and includes the three components
Yatu replaces by design (findings L1–L3).

**Rule:** no file in this directory is edited to make Yatu's code work. If
upstream's code needs to behave differently, the new behaviour goes in
`Sources/YatuKit/` and calls into this target, never the other way around.
