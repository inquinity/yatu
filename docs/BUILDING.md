# Building Yatu

There is no Xcode project. SwiftPM produces the executables and `bin/build.sh` assembles them into
`.app` bundles.

## Requirements

- macOS 13.0 or later to run; Xcode 27 or the matching command line tools to build
- [`just`](https://github.com/casey/just) and [`shellcheck`](https://www.shellcheck.net) are
  optional — every recipe also works by calling the `bin/` script directly

## Build and test

```bash
bin/build.sh                  # both bundles, release, universal  (just build)
bin/build.sh terminal         # Yatu.app only
bin/build.sh --native --debug # this Mac's architecture, debug configuration
bin/build.sh --help           # every option
swift test                    # 87 tests                          (just test)
bin/test-scripts.sh           # shell tests                       (just test-scripts)
just lint                     # shellcheck every script
just --list                   # every task
```

Output is `dist/Yatu.app`. `bin/build.sh` always operates on
the repository, not on the directory you call it from, and removes its output directory before
building.

The build refuses to finish rather than ship something wrong: it asserts that the extension is
sandboxed and the app is not, and runs `codesign --verify --strict` on the result. A failure there
is a refusal, not a warning.

## Running what you built

The bundles are **ad-hoc signed**, so they run on the Mac that built them and nowhere else.

The Finder extension needs three things, and skipping any of them looks like a broken build:

1. **Copy the app to `/Applications`.** macOS registers the extension from the containing app's
   location; running it out of `dist/` is not enough.
2. **Launch it once**, so `pluginkit` records the extension.
3. **Enable it** in System Settings → General → Login Items & Extensions, then add the button with
   Finder's **View → Customize Toolbar**.

```bash
bin/which-yatu.sh             # is it installed? is the extension registered AND enabled?
```

That script is the first thing to run when the button does not appear. A registered-but-disabled
extension is absent from the customize palette, which looks identical to a build that did not work.

**The trap:** macOS remembers extension approval **per bundle identifier**. If you have previously
approved an extension with the same identifier, a fresh build inherits that approval; if you change
the identifier, the new one comes up registered but disabled even though the old one was enabled.
Both states are normal and neither means the build is broken.

A built bundle identifies itself:

```bash
/Applications/Yatu.app/Contents/MacOS/Yatu --version    # 1.0.0 build 1
/Applications/Yatu.app/Contents/MacOS/Yatu --identity   # bundle id, team, commit, build date
bin/ver --help                                          # read or bump VERSION
```

## Regenerating the toolbar symbol

The toolbar button draws `yatu.folder.caret`, a custom SF Symbol committed at
`Resources/YatuFinderSync.xcassets/`. `bin/build.sh` compiles it with `actool` into the extension's
own bundle — a sandboxed extension can only read its own — and that happens *before* the extension
is signed, because signing is leaf-first and anything added afterwards invalidates the seal.

You only need to regenerate it if you are changing the mark:

```bash
brew install --cask sf-symbols
```

In SF Symbols: search `folder`, select the plain folder, **File → Export Template**, choose
**Static**, and save it. Then:

```bash
bin/make-symbol.swift ~/path/to/folder.svg \
    Resources/YatuFinderSync.xcassets/yatu.folder.caret.symbolset/yatu.folder.caret.svg
```

The caret's size and position are environment variables, so trying a different one costs one run —
`CARET_HEIGHT` (default 0.72 of the folder's interior), `CARET_WIDTH`, `CARET_DX`, `CARET_DY`.
0.60 is timid at Regular weight and 0.84 merges into the walls at Black.

Apple's exported `folder.svg` is deliberately **not** in the repository: it is Apple's artwork
unmodified, and `.gitignore` keeps `SFSymbols/` out. The generated symbol is shipped, and carries
Apple's licence rather than Yatu's — see [UPSTREAM.md](UPSTREAM.md).

## Signing and notarization

`bin/build.sh` never signs with a real identity, and nothing in this repository produces a
distributable build today — Developer ID signing and notarization arrive in M4 (see
[YATU-PLAN.md](YATU-PLAN.md)).

When they do, they will need an **Apple Developer account**, a Developer ID Application certificate
and `notarytool` credentials stored in a keychain profile. Yatu's own releases are signed by team
`45GJWJVQN2`. If you build your own copy, signing it is your problem and your account — an ad-hoc
build is fine for personal use and for working on the code.

## Working on the code

- **Never edit anything in `Sources/YatuUpstream/`.** Those files come from OpenInTerminal and are
  compiled unchanged, each carrying a provenance header. Behaviour that has to differ goes in
  `Sources/YatuKit/` and calls into that target. See [UPSTREAM.md](UPSTREAM.md).
- **`yatu://` is a public entry point.** Any application or web page can invoke it. It is parsed
  strictly in `Sources/YatuKit/HandOff.swift`, and `FinderTarget` re-validates every path that
  arrives. Treat changes to either as security-relevant.
- The Finder extension (`Sources/YatuFinderSync/`) is sandboxed and executes nothing: it reports
  Finder's context and stops. Nothing slow belongs inside `menu(for:)` — that is the click handler,
  and work done there shows up as an empty or reflowing menu.
- Before opening a pull request: `swift test`, `bin/test-scripts.sh` and `just lint` all clean.
- **The extension is an executable target, so nothing can import it.** Anything in
  `Sources/YatuFinderSync/` worth testing belongs in `YatuKit` instead — that is why menu
  construction lives in `MenuBuilder` rather than in the extension. Two shipped bugs hid in the
  part that could not be imported.
