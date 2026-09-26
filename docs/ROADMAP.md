# Yatu — roadmap

Yatu is a Finder toolbar button that opens a terminal at the folder you are looking at.
**Current release: 1.0.2 (2026-09-25).** Why it is built this way: [DESIGN.md](DESIGN.md).

## Next

Nothing here is scheduled; the order is a suggestion.

1. **Tell the user when the default changes.** `yatu://set-default` changes a stored preference on
   behalf of a caller the app cannot identify. Gatekeeper keeps the worst case low (DESIGN §9.9), but
   a default that changes silently is poor behaviour whoever changed it. Post a notification with an
   undo, and write a log entry. Not a security control; ordinary work.
2. **Own the app catalog.** It is one maintainer's list, partly stale (DESIGN §9.6). Decide when
   to stop treating it as upstream's: the trigger is the next time `bin/check-upstream.sh` reports
   a difference. Corrections already live in `Sources/YatuKit/CatalogCorrections.swift`.
3. **Choose the app icon format.** A flat `.icns` or an Icon Composer `.icon`. The old reason to
   prefer `.icns` (art that varies by size) no longer applies, so decide on the format's own merits
   (DESIGN §9.3, M1b).

## Optional, unscheduled

- App Sandbox spike for the app itself. Ship only if launching a Finder-derived folder works without
  an `NSUserAppleScriptTask` helper.
- Extras only if wanted: several selected folders each in a tab; a Services entry.

## Shipped

| Version | What |
|---|---|
| 1.0.0 (2026-09-24) | Signed, notarized app with a Finder Sync extension, a settings window, the `yatu://` hand-off, and the `yatu` cask in `inquinity/tap` |
| 1.0.1 (2026-09-25) | Toolbar button works in iCloud Drive and other File Provider folders |
| 1.0.2 (2026-09-25) | One app delegate and run loop, so windows and clicks stop misfiring; Settings lists only installed apps; an About window |

Release notes: [release-notes/](release-notes/). Checks before a release: `swift test` (111),
`bin/test-scripts.sh` (13), `bin/attack-matrix.sh --live`, and
[MANUAL-TEST-CHECKLIST.md](MANUAL-TEST-CHECKLIST.md), last run in full against 1.0.2 on 2026-09-25.

## Dropped, on purpose

| What | Why |
|---|---|
| Migrating the old OpenInTerminal-Lite preference | Saved one click, once, for about one person, at the price of a permanent branch in the launch path (DESIGN M3) |
| A separate editor app | The extension's menu reaches the editor role; one bundle to sign and explain (DESIGN §9) |
| Reporting upstream's findings | Yatu is independent and does not carry them (DESIGN M6) |
| Window/tab choice in Settings | Needs a second permission grant or shell-string building; the terminal owns that preference (DESIGN §5) |
