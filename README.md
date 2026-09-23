# Yatu

A Finder toolbar button that opens a terminal at the folder you are looking at.

One click on the toolbar and your terminal is there, in the right directory. Hold ⌥ for a menu that
changes which terminal that is, or sends the selection to an editor instead.

- **macOS 13.0 or later**
- Developer ID signed by Altman Software Design, LLC
- No background process, no login item, no menu-bar icon

---

## Install

```bash
brew install --cask inquinity/tap/yatu
```

Then two one-time steps. Yatu's toolbar button is a Finder extension, and macOS requires you to
turn extensions on yourself.

**1. Enable the extension.** Open **System Settings → General → Login Items & Extensions**, find
**Yatu** under the Finder extensions, and switch it on.

**2. Add the button.** In Finder, choose **View → Customize Toolbar**, then drag **Yatu** into the
toolbar and click Done.

If Yatu is missing from the customize palette, it is almost always because step 1 has not been
done — a registered but disabled extension does not appear there. `bin/which-yatu.sh` will tell you
which state it is in.

## Using it

**Click** the button to open your default terminal at the current folder.

What "the current folder" means:

| In Finder | Yatu opens |
|---|---|
| A folder is showing, nothing selected | that folder |
| Exactly one folder selected | the selected folder |
| Exactly one file selected | the folder containing it |
| Several items selected | the folder you are looking at — the selection is ignored, because the order you happened to select things should not change where the terminal lands |
| No Finder window at all | the Desktop |

Symlinks are resolved first, and an application bundle is treated as a file rather than a folder —
a terminal opened inside an `.app` is never what was meant.

**⌥-click** the button for a menu:

- **Set default terminal program** — every terminal you have installed. Choosing one *sets the
  default*; it does not open anything. The next plain click uses it.
- **Send to editor** — every editor you have installed. Choosing one *opens it now* and changes no
  default. One selected file is handed to the editor; with nothing selected, or with several things
  selected, the editor is given the folder instead, which suits the editors that can open one
  (VS Code, Emacs).
- **Settings…**

The asymmetry is deliberate: the terminal is the thing you use constantly and want one click away,
so the menu configures it. The editor is occasional, so the menu does it.

## Settings

Reached from the ⌥-click menu, or by holding ⌥ while launching Yatu from `/Applications`.

## ⌘-drag: supported, but not recommended

You can also hold ⌘ and drag `Yatu.app` from `/Applications` onto the Finder toolbar, the way you
can with any application. This works, and it works **without the extension enabled** — it is the
fallback if you would rather not turn an extension on.

It is not the recommended route, because you lose things:

- **No ⌥-click menu.** Finder launches the app; there is nothing to hold ⌥ for. You can still reach
  settings by ⌥-launching Yatu from `/Applications`.
- **The app icon, on a grey plate.** Finder draws the application's own icon, in colour, rather than
  a toolbar glyph that matches Finder's own controls.
- **Slower.** Every click launches the application rather than messaging an extension that is
  already resident.

Use **View → Customize Toolbar** unless you have a reason not to.

## Uninstall

```bash
brew uninstall --cask --zap inquinity/tap/yatu
```

`--zap` also removes Yatu's preferences and the extension's container. Remove the toolbar button
yourself with **View → Customize Toolbar** if it is still there.

## Building from source

There is no Xcode project; `bin/build.sh` assembles the `.app` from a Swift package.

```bash
git clone https://github.com/inquinity/yatu.git
cd yatu
bin/build.sh                  # or: just build
swift test                    # 60 tests
bin/which-yatu.sh             # what is installed, and whether the extension is enabled
just --list                   # every task
```

The build produces an ad-hoc signed bundle in `.build/app`. Copy it to `/Applications` and launch it
once so macOS registers the extension.

Requires Xcode 27 or later. `Yatu.app --version` and `--identity` report what a built bundle is.

## Credits

Yatu **uses code from** [OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal) by
[Jianing Wang](https://github.com/Ji4n1ng), MIT licensed — the catalog of supported terminals and
editors with their bundle identifiers, and two ScriptingBridge interfaces. Those files are vendored
in [`Sources/YatuUpstream/`](Sources/YatuUpstream/), each carrying the upstream path and commit it
came from. Yatu would not exist without that project, and it is worth installing in its own right:
it does considerably more than this does.

Everything else — the Finder Sync extension, the launch path, the settings, the build — is Yatu's
own. See [docs/UPSTREAM.md](docs/UPSTREAM.md) for exactly what is used and why, and
[docs/YATU-PLAN.md](docs/YATU-PLAN.md) for what is being built.

## Licence

MIT. See [LICENSE](LICENSE).
