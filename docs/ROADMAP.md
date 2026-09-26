# Yatu — roadmap

Yatu is a Finder toolbar button that opens a terminal at the folder you are looking at.
**Current release: 1.0.2 (2026-09-25).** Why it is built this way: [DESIGN.md](DESIGN.md).

## Next

Nothing is scheduled.

## For consideration

- **The Mac App Store.** It requires the App Sandbox for the app, not just the extension. Looked
  into 2026-09-26, with a throwaway sandboxed test app; the app cannot do this as it works today:
  - **No Apple Events.** A sandboxed app cannot script Finder or Terminal, and Apple's own guidance
    (QA1888) says a temporary exception for either is likely to be rejected. So the direct-open
    path and the 1.0.1 fix for iCloud Drive and other File Provider folders, which both ask Finder,
    would go, and the extension becomes the only way in: the ⌘-drag fallback would stop working.
  - **No opening a folder you cannot read.** `NSWorkspace.open` of an arbitrary folder in Terminal
    or iTerm failed with "a miscellaneous error"; the same call worked for the app's own container
    and, with read access added, for a granted folder, and still failed for one outside it.
    Sandboxed `fileExists` on the folder did succeed, so rule 3's check is not what breaks.
  - **The way through:** the extension already supplies the folder, so the app needs no Finder query;
    what it lacks is *access*. A one-time prompt asking the user to grant a broad root (their home
    folder, and any other volume they use) with a security-scoped bookmark would let it open anything
    beneath. That is a normal, reviewable request, but it is a setup step every user sees.
  - **Untested:** whether a sandboxed app can launch terminals that take arguments (kitty, WezTerm,
    Alacritty, Tabby), and how App Review treats an app whose job is launching other apps.
  - **Cost:** a second, sandboxed build and entitlement set, the grant flow, loss of the two
    fallbacks above, App Store review, and 30% if the app is ever priced. Not started.

- **Open a "working group": one terminal window per selected folder.** Select folders at different
  levels, click, and each opens at its own folder. Passing several folders to the terminal as
  `open` arguments works with no new permissions and no shell string, but it gives **windows, not
  tabs**: tested 2026-09-26, three folders opened three windows with one tab each in both
  Terminal.app and iTerm, the only catalog terminals installed here. So this is windows only.
  - Changes DESIGN §4.1 rule 3, which sends several selected items to the viewed folder. It would
    become: every selected *folder* opens; files in the selection are ignored; a selection with no
    folder falls back to the viewed folder as now.
  - Needs a cap of about 8, because `yatu://` is public and a hostile URL must not be able to open
    dozens of windows; the hand-off already carries a bounded list.
  - Tabs would need a per-terminal scripting path (iTerm's scripting creates a tab at a working
    directory without a shell string, Terminal.app's does not) and a new Automation prompt, which is
    a security review, not a feature. Not proposed.

## Shipped

| Version | What |
|---|---|
| 1.0.0 (2026-09-24) | Signed, notarized app with a Finder Sync extension, a settings window, the `yatu://` hand-off, and the `yatu` cask in `inquinity/tap` |
| 1.0.1 (2026-09-25) | Toolbar button works in iCloud Drive and other File Provider folders |
| 1.0.2 (2026-09-25) | One app delegate and run loop, so windows and clicks stop misfiring; Settings lists only installed apps; an About window |

Release notes: [release-notes/](release-notes/). Checks before a release: `swift test` (106),
`bin/test-scripts.sh` (13), `bin/attack-matrix.sh --live`, and
[MANUAL-TEST-CHECKLIST.md](MANUAL-TEST-CHECKLIST.md), last run in full against 1.0.2 on 2026-09-25.

## Dropped, on purpose

| What | Why |
|---|---|
| Migrating the old OpenInTerminal-Lite preference | Saved one click, once, for about one person, at the price of a permanent branch in the launch path (DESIGN M3) |
| A separate editor app | The extension's menu reaches the editor role; one bundle to sign and explain (DESIGN §9) |
| Reporting upstream's findings | Yatu is independent and does not carry them (DESIGN M6) |
| Window/tab choice in Settings | Needs a second permission grant or shell-string building; the terminal owns that preference (DESIGN §5) |
