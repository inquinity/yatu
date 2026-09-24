# Manual test checklist

Run this before a release, and after any change to the extension, the `yatu://` handler or the
launcher. Each line is **EXPECT** (what should happen) and **FAIL IF** (what means stop).

**Why a manual checklist exists at all.** Three defects reached a user while 65 automated tests
passed, and every one of them was invisible to those tests: menu items that drew correctly and did
nothing when clicked, a hand-off that quietly sent the wrong thing, and a diagnostic script that
confidently reported the wrong state. Two more things — rule 7's ScriptingBridge path and rule 6's
*absence* of a log file — cannot be unit-tested at all. **The single most important habit here is
to click every kind of menu item, not to look at the menu and conclude it is fine.**

Automated cover, so you know what this is *not* repeating:

```bash
swift test              # 87 tests: rules 1-6, the URL contract, the menu model, hostile input
bin/test-scripts.sh     #  4 checks: which-yatu.sh reading pluginkit
just lint               # shellcheck
```

---

## 0. Before you start

- [ ] `bin/which-yatu.sh` — note what is installed and whether the extension is enabled.
- [ ] Back up your own preference so the test does not cost you your setting:
      `defaults read com.altmansoftwaredesign.yatu > ~/yatu-prefs-backup.txt`
- [ ] `bin/attack-matrix.sh --keep` creates the awkward-names corpus — a space, a quote, a command
      substitution, a newline, a leading dash, a symlink to a file, a `.command`, a canary `.app` —
      and leaves it in place for the clicking you do by hand below.

## 1. Install and enable

- [ ] Install: `rm -rf /Applications/Yatu.app && ditto dist/Yatu.app /Applications/Yatu.app`
      **EXPECT** `codesign --verify --strict --deep /Applications/Yatu.app` passes.
      **FAIL IF** it reports a sealed resource missing or modified — something was added after signing.
- [ ] Register: `pluginkit -a /Applications/Yatu.app/Contents/PlugIns/YatuFinderSync.appex`
      **EXPECT** `bin/which-yatu.sh` reports the extension as registered.
      **FAIL IF** it reports "registered but NOT enabled" when System Settings does not list it —
      that is the script lying, and it is the one thing users are told to trust.
- [ ] **System Settings → General → Login Items & Extensions**
      **EXPECT** "Yatu" appears under the Finder extensions and can be switched on.
      **FAIL IF** it is absent while `pluginkit` says it is registered.
- [ ] Finder → **View → Customize Toolbar**
      **EXPECT** Yatu appears in the palette, named "Yatu", with the folder-and-caret glyph.
      **FAIL IF** the palette shows a stale name, a generic icon, or nothing.

## 2. How the button looks

The toolbar glyph is a template image, so the system tints it. The app icon is a different asset and
appears in list views, Get Info and the Dock.

- [ ] **EXPECT** the toolbar glyph matches the weight of Finder's own controls either side of it.
      **FAIL IF** it is visibly heavier, lighter, larger or smaller than its neighbours.
- [ ] Dark mode. **EXPECT** the glyph turns light. **FAIL IF** it stays dark, or keeps a fixed grey.
- [ ] System Settings → Appearance → **Icon & widget style**, all four: Default, Dark, Clear, Tinted.
      **EXPECT** the glyph stays legible in each.
      **FAIL IF** it vanishes or inverts into illegibility in any of them.
- [ ] Click another window so the Finder window is **inactive**.
      **EXPECT** the glyph dims with the rest of the toolbar. **FAIL IF** it stays at full strength.
- [ ] `/Applications` in list view.
      **EXPECT** Yatu's icon is the violet tile, like its neighbours.
      **FAIL IF** it is a grey outline — the size split has come back.

## 3. A plain click, once per row of rule 3

This is the whole target-resolution table. Each row is a separate click.

| In Finder | EXPECT | FAIL IF |
|---|---|---|
| A folder open, nothing selected | terminal opens at that folder | it opens at the Desktop or the parent |
| Exactly one folder selected | terminal opens at the selected folder | it opens at the enclosing folder |
| Exactly one file selected | terminal opens at the folder containing it | it opens the file, or runs it |
| Several items selected | terminal opens at the folder being viewed | it opens at one of the selection |
| A symlink to a file selected | terminal opens at the folder containing the link's target | it opens the link's target |
| An `.app` bundle selected | terminal opens at the folder containing it | it opens *inside* the bundle |
| No Finder window at all | terminal opens at `~/Desktop` | nothing happens, or an error |
| A non-filesystem view (Recents, AirDrop, a search) | terminal opens at `~/Desktop` | it crashes, or opens somewhere arbitrary |

- [ ] Repeat the first row inside the awkward-names folder.
      **EXPECT** the terminal opens at that folder and runs nothing.
      **FAIL IF** any part of a filename is executed, or the terminal opens elsewhere.

## 4. The ⌥-click menu — click every item, do not just read it

**This is the section that catches the bug class that shipped.** A menu item that draws correctly,
enables correctly, highlights on hover and does nothing when clicked looks exactly like one that
works. Only clicking tells you.

- [ ] ⌥-click.
      **EXPECT** the menu appears immediately, fully drawn, with app icons already in place.
      **FAIL IF** it appears empty, appears then reflows, or takes a visible moment to fill.
- [ ] **"Set default terminal program" → one you do not currently use.**
      **EXPECT** nothing opens. The menu closes and the default changes.
      **FAIL IF** a terminal opens — these items set, they do not act.
- [ ] Plain click now.
      **EXPECT** the terminal you just chose opens.
      **FAIL IF** the previous default opens — the setting did not stick.
- [ ] **"Send to editor" → an editor, with one file selected.**
      **EXPECT** that editor opens with that file. The terminal default is unchanged.
      **FAIL IF** the folder opens instead, or the terminal default changed.
- [ ] **"Send to editor" → an editor, with three files selected.**
      **EXPECT** all three open. **FAIL IF** only one opens, or the folder opens instead.
- [ ] **"Send to editor" → an editor, with nothing selected.**
      **EXPECT** the folder being viewed opens.
      **FAIL IF** nothing happens, or the Desktop opens.
- [ ] **"Settings…"**
      **EXPECT** the settings window appears and comes to the front.
      **FAIL IF** nothing happens, or it opens behind another window.
- [ ] Go back and click **every remaining item in the menu**, one per run.
      **EXPECT** each one does something.
      **FAIL IF** any item does nothing at all — that is the shipped-bug signature.

## 5. Settings

- [ ] Change the terminal in the settings window, close it, plain-click the toolbar button.
      **EXPECT** the newly chosen terminal opens. **FAIL IF** the old one does.
- [ ] Quit Yatu, reopen Settings. **EXPECT** the choice persisted. **FAIL IF** it reset.
- [ ] With an app in the list uninstalled. **EXPECT** it is absent or unselectable.
      **FAIL IF** choosing it appears to work and then nothing launches.

## 6. Rule 7 — Terminal.app specifically

Terminal.app is the one entry opened over ScriptingBridge, because it is the only way to hand it a
folder without also handing it a shell. Nothing about that is unit-testable.

- [ ] Set the default to **Terminal**, plain-click.
      **EXPECT** Terminal opens a new window already at that folder.
      **FAIL IF** it opens at `~`, or opens a window running a command.
- [ ] Repeat with Terminal already running, with a window open.
      **EXPECT** a new window or tab at the folder, and the existing one untouched.
      **FAIL IF** the existing session has anything typed into it.
- [ ] Repeat inside the awkward-names folder.
      **FAIL IF** anything in a name is interpreted rather than treated as a path.

## 7. Rule 6 — the absence of a log file

Upstream wrote every opened path to a world-readable file. Yatu must not, and you cannot test for
the absence of a file with a unit test.

- [ ] After all of the above:
      `ls -la ~/Library/Logs | grep -i -E 'yatu|logfile'`
      **EXPECT** nothing. **FAIL IF** any file exists.
- [ ] `log show --predicate 'subsystem == "com.altmansoftwaredesign.yatu"' --last 30m`
      **EXPECT** entries exist, and **no filesystem path appears in them** — paths are `.private`
      and render as `<private>`.
      **FAIL IF** a real path is visible to a reader who did not enable private data.

## 8. ⌘-drag, the fallback

Supported, not recommended: it works without the extension enabled.

- [ ] ⌘-drag `Yatu.app` from `/Applications` onto the Finder toolbar.
      **EXPECT** the app icon appears on a grey plate, in colour.
      **FAIL IF** the item refuses to drop.
- [ ] Click it. **EXPECT** the terminal opens at the current folder, as a plain click does.
      **FAIL IF** nothing happens.
- [ ] ⌥-launch `Yatu.app` from `/Applications`.
      **EXPECT** the settings window. **FAIL IF** a terminal opens instead.

## 9. The public entry point

`yatu://` is reachable by anything on this Mac. `swift test` covers parsing; this covers the app
actually running.

- [ ] `open "yatu://settings?role=terminal"` **EXPECT** the settings window.
- [ ] `open "yatu://open?role=terminal&container=/tmp"` **EXPECT** a terminal at `/tmp`.
- [ ] `open "yatu://open?role=terminal&app=NotAnApp&container=/tmp"`
      **EXPECT** nothing happens. **FAIL IF** anything launches.
- [ ] `open "yatu://execute?role=terminal&container=/tmp"`
      **EXPECT** nothing happens. **FAIL IF** anything launches.
- [ ] `bin/attack-matrix.sh --live`
      **EXPECT** "All checks passed" — no canary fired, no log file written by the run, no path in
      the unified log. It opens a terminal window per case; that is expected.
      **FAIL IF** any canary exists: something interpreted a filename or ran a selected file.

## 10. Afterwards

- [ ] Restore your preference from the backup, or set it again by hand.
- [ ] Remove the scratch folder.
- [ ] Note anything that surprised you, even if it passed. The bugs that shipped all looked fine.
