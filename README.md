# Yatu

A Finder toolbar button that opens a terminal at the folder you are looking at.

One click on the toolbar and your terminal is there, in the right directory. Hold ⌥ for a menu that
changes which terminal that is, or sends the selection to an editor instead.

- **macOS 13.0 or later**
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

## Settings Menu
**⌥-click** the button for a menu:

- **Set default terminal program** — every terminal you have installed. Choosing one *sets the
  default*.
- **Send to editor** — every editor you have installed. Choosing one *opens it now*, with
  everything you have selected. Nothing selected gives the editor the folder.
- **Settings…**

## Supported terminals and editors

Settings lists the ones you actually have. These are the 36 Yatu knows how to
open — if yours is missing, that is why it does not appear.

**Terminals (13)**

Terminal, iTerm, Alacritty, kitty, WezTerm, Tabby, Warp, cmux, GitHub Desktop, GitKraken, Fork, Ghostty, Kaku

**Editors (23)**

TextEdit, Xcode, Visual Studio Code, Sublime Text, VSCodium, BBEdit, Visual Studio Code - Insiders, CotEditor, MacVim, Typora, Nova, Cursor, Neovim, Zed, Emacs, CLion, GoLand, IntelliJ IDEA, PhpStorm, PyCharm, RubyMine, WebStorm, Android Studio

GitHub Desktop, GitKraken and Fork sit in the terminal list because that is how the catalog
groups them: they open the folder as a repository rather than as a shell.

The list is Yatu's own. It began as [OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal)'s
catalog — see [docs/UPSTREAM.md](docs/UPSTREAM.md) — and apps that are dead or on life support are
dropped. If one you want is missing, open an issue.

## Troubleshooting

**Yatu is not in the Customize Toolbar palette.** Either step 1 has not been done — a registered but
disabled extension does not appear there — or Finder has not picked up the extension yet. Finder
loads extensions when it starts, so if it has been running a while:

```bash
killall Finder
```

Finder relaunches immediately; it only closes your Finder windows.

**Resetting the Finder permission.** The first click asks for permission to control Finder. That is
how Yatu learns which folder you are looking at; it is the app's only entitlement. To reset that
answer later:

```bash
tccutil reset AppleEvents com.altmansoftwaredesign.yatu
```

## Alternative Install: ⌘-drag
⌘-drag is supported, but not recommended. Really, it works, but you are stuck with a color icon that sticks out like a sore thumb. You might do this to avoid enabling the Finder extension (or just because you can); that's up to you.

## Uninstall

```bash
brew uninstall --cask --zap inquinity/tap/yatu
```

`--zap` also removes Yatu's preferences and the extension's container. Remove the toolbar button
yourself with **View → Customize Toolbar** if it is still there.

## Credits

Yatu **uses code from** [OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal) by [Jianing Wang](https://github.com/Ji4n1ng), under the MIT license
- the catalog of supported terminals and editors with their bundle identifiers
- two ScriptingBridge interfaces

Thanks for the jump-start.

## The toolbar symbol

Yatu's toolbar button draws a custom SF Symbol — a folder with a prompt caret — which is **derived
from Apple's `folder` symbol**, exported from SF Symbols and modified. That file
(`Resources/YatuFinderSync.xcassets/yatu.folder.caret.symbolset/`) is governed by **Apple's SF
Symbols licence, not by Yatu's MIT licence**, and is shipped inside a macOS app, which is what SF
Symbols are licensed for. Do not relicense it or reuse it off an Apple platform.

## Licence

MIT, because free means free!
See [LICENSE](LICENSE) — with the one carve-out noted above.
