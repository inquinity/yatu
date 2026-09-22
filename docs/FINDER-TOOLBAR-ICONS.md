# Finder toolbar icons — findings

Research record, started 2026-09-21. It exists for two reasons: to settle how Yatu's icon should be
built, and to give a later session the facts it needs to re-assess
[GH-283](https://github.com/Ji4n1ng/OpenInTerminal/issues/283), the OpenInTerminal /
OpenInTerminal-Lite toolbar icon that corrupts when the Finder window is inactive. **No action has
been taken on GH-283 here** — section 4 is notes for that session, nothing more.

Every finding carries a basis:

- **Documented** — stated in an Apple source listed in section 5.
- **Observed** — measured or seen on the Mac this was written on.
- **Reported** — a third-party source says so; not reproduced here.
- **Inferred** — a reading of the evidence; not proven.

Machines and versions: one Mac. Measurements in sections 2.3–2.5 were taken on **macOS 26.6.2** and
repeated on **macOS 27.0** (build 26A428) after the Mac was upgraded on 2026-09-21/22; where the two
disagree it says so. Toolbar screenshots in 2.6 were taken by the user on 26.6.2. Xcode 27.0
(27A266a), macOS 27.0 SDK.

## 1. What Apple says

### 1.1 Toolbars (HIG)

Documented, [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars):

- "Prefer system-provided symbols without borders. System-provided symbols are familiar,
  automatically receive appropriate coloring and vibrancy, and respond consistently to user
  interactions."
- "If your app already has bright, colorful content in the content layer, prefer using the default
  monochromatic appearance of toolbars."
- "Reduce the use of toolbar backgrounds and tinted controls."
- In macOS, "toolbar items don't include a bezel."

**Scope.** This guidance is written for an app designing *its own* toolbar items. An application
dragged into Finder's toolbar is a different case: Finder shows that application's **app icon**, which
the application does not draw and cannot template. The HIG has no guidance specific to that case.
The monochrome convention is followed by Finder's own items; third-party app icons in that toolbar
are whatever the app's icon is.

The HIG page says nothing about inactive-window appearance, template images, or item sizes.

### 1.2 App icons (HIG)

Documented, [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons):

- macOS icons are made in **Icon Composer**: "you then import your icon layers into Icon Composer,
  a design tool included with Xcode."
- "iOS, iPadOS, macOS, and watchOS app icons include a background layer and one or more foreground
  layers."
- "icons are square, and the system applies masking to produce rounded corners." Layout 1024×1024.
- Six appearances: "Default, dark, clear light, clear dark, tinted light, tinted dark". People choose
  the style system-wide.
- Nothing about legacy icons, plates, or per-size artwork.

### 1.3 Shipping an Icon Composer icon (Xcode)

Documented,
[Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer):

- Add the `.icon` file to the target, then "ensure that the name in the App Icon text field matches
  the name of the Icon Composer file without the extension."
- Older systems: "Xcode automatically generates app icon images at build time for those releases
  from the Icon Composer file." — "a similar-looking version of the Liquid Glass icon".

Observed: `actool` compiles a hand-written `.icon` outside Xcode
(`xcrun actool Foo.icon --compile out --platform macosx --app-icon Foo …`), producing
`Assets.car` **and** a generated `Foo.icns`, and a partial Info.plist setting both
`CFBundleIconName` and `CFBundleIconFile`. So a SwiftPM build like Yatu's can ship an Icon Composer
icon without an Xcode project. The generated `.icns` is the backward-compatibility path the Xcode
document describes.

**There is no documented way to give an Icon Composer icon different artwork at different sizes.**
It is one composition rendered at every size.

## 2. How macOS draws an app icon in and around the Finder toolbar

### 2.1 What the toolbar stores

Observed. Finder records toolbar items in `com.apple.finder` →
`NSToolbar Configuration Browser`, and an added application is stored as a **file reference URL**
(`file:///.file/id=…`), not a path. On this Mac the three added apps resolve to:

| Item | Resolves to |
|---|---|
| OpenInTerminal | `~/dev/oss/openinterminal/export/OpenInTerminal.app` |
| OpenInTerminal-Lite | `~/dev/oss/openinterminal/export/OpenInTerminal-Lite.app` |
| Yatu | `/Applications/Yatu.app` |

Consequence: replacing a bundle by delete-and-recreate (what `bin/build.sh` does to `.build/app`)
leaves the toolbar pointing at a file ID that no longer exists. Replacing in place keeps it.

### 2.2 Toolbar customisation is Finder's, not the app's

Observed. The toolbar button is the application itself, added with ⌘-drag. Nothing in the app
declares it — unlike the full OpenInTerminal app's **Finder Sync extension**, whose
`toolbarItemImage` returns a **template image** (`template-rendering-intent: template`) that the
system tints. That is a separate toolbar item; a plain application cannot supply one.

### 2.3 Which icon representation is chosen, by pixel size

Observed on 27.0, by asking `NSWorkspace.icon(forFile:)` to draw into bitmaps of fixed pixel size,
using a probe app whose ten `.icns` slots are each a different colour and label
(`/Applications/IconSizeProbe.app`):

| Pixels requested | Slot drawn |
|---|---|
| 16 | `icon_16x16` |
| 32 | `icon_32x32` (not `icon_16x16@2x`, though both are 32 px) |
| 36, 48, 64 | `icon_32x32@2x` (64 px), scaled down |
| 128 | `icon_128x128` |

Rule, **inferred** from that: the smallest slot at least as large as the request.

**Not yet known: what the toolbar actually requests.** These are 1× bitmap contexts. A Retina
toolbar asks in points with a 2× backing store and may select differently. Both displays on this
Mac are 2× (built-in Liquid Retina XDR; external 5K drawn as 2560×1440), so every screenshot here
is a Retina observation, and the 1× case — a non-Retina external display — cannot be tested on
this Mac.

**Answered for the toolbar — observed, 27.0, 2026-09-22.** With the probe in the Finder toolbar on
a 2× display, the button shows **`32@2`: the toolbar draws from the `icon_32x32@2x` slot (64 px)**.
Same slot in light and dark appearance, active and inactive windows. The button is drawn at about
26 pt (≈52 px), and 64 px is the smallest slot at least that large, consistent with the rule above.
Full-bleed artwork at that slot is masked to the rounded icon shape, with no plate.

Still unanswered: which slot Finder's own views use (list, icon, column). By the rule, list view at
16 pt on 2× asks for 32 px and icon view at 64 pt asks for 128 px, so neither would share the
toolbar's slot — but that is inferred, not observed. Anything Finder draws between roughly 17 and
32 pt on a 2× display would share it.

### 2.4 The system plate behind legacy icons

Observed on 26.6.2 and 27.0 — the plate is a system treatment of an **`.icns`-only** icon:

- **Transparent artwork** (a glyph with no tile) is composited onto a light grey rounded plate.
  OpenInTerminal-Lite, whose artwork is transparent at every size, is on the plate at every size.
  Yatu, transparent only at 16–32 pt, is on the plate up to 64 px and on its own violet tile at
  128 px.
- **Full-bleed square artwork** (the probe) is set *inside* the plate at 16 and 32 px, and masked
  to the rounded icon shape from 36 px up.
- **Icon Composer icons get no plate at any size.** OpenInTerminal (full) and a hand-built Yatu
  Icon Composer icon both render as their own tile from 16 px to 128 px.

In the toolbar, the plate stays **light in dark appearance in an active window** (observed on
26.6.2, and again on 27.0 on 2026-09-22), and turns mid grey when the window is inactive. It does
not adapt to dark appearance: an `.icns`-only icon has no dark rendition to offer. A dark-mode
screenshot from 27.0 in which every plate was mid grey turned out to show two inactive windows.

Reported, not reproduced: that 26.6.1 drew legacy icons as-is and 26.6.2 began compositing them onto
a plate. The source for that was a search-engine summary of project pull requests, and it is not
confirmed here.

### 2.5 Appearance cannot be tested through `NSWorkspace`

Observed. `NSWorkspace.icon(forFile:)` inside `NSAppearance(named: .darkAqua)
.performAsCurrentDrawingAppearance` returns the same image as under `.aqua`, for both formats —
although `assetutil --info` shows the compiled Icon Composer catalogs contain
`NSAppearanceNameDarkAqua` and `ISAppearanceTintable` renditions. **Dark, clear and tinted
behaviour can only be checked by looking at a real Finder toolbar.** Any test that uses this API to
claim otherwise is wrong.

### 2.5a Dark appearance does not select an icon's dark variant

Observed on 27.0, 2026-09-22, with `/Applications/Yatu-Composer.app` (an Icon Composer icon whose
light and dark variants have deliberately different fills) in the toolbar of an **active** window.
Pixel colours sampled from the user's screenshots:

| Screenshot | Tile fill, top → bottom |
|---|---|
| Light appearance | (99, 67, 144) → (79, 53, 123) |
| Dark appearance | (99, 67, 143) → (79, 53, 122) |
| *Authored light fill* | *(120, 66, 168) → (74, 38, 118)* |
| *Authored dark fill* | *(78, 43, 112) → (38, 20, 60)* |

The tile is the same in both appearances and matches the **light** variant, slightly lightened by
the system's glass treatment. **Switching the system to dark appearance did not make the toolbar
use the icon's dark variant.**

Inferred, from the HIG's "people can choose whether their … app icons are default, dark, clear, or
tinted": the icon variant follows the user's separate **icon style** setting (System Settings ›
Appearance), not light/dark appearance. No icon-style key is set in the global preferences domain
on this Mac, consistent with the default style — but the key's name was not confirmed. Not yet
tested: the toolbar with the icon style set to Dark, Clear and Tinted.

Also observed in the same screenshots, **inactive** windows: the Icon Composer tile is desaturated
like every other icon — mid grey in light appearance, near black in dark — and has no plate. In
dark appearance it is the icon that sits closest to the toolbar's own colour; the `.icns`-only
icons keep a lighter grey plate and stand out from it.

### 2.5b The four icon styles, observed

The setting is **System Settings › Appearance › "Icon & widget style"**, with four choices —
**Default, Dark, Clear, Tinted** — confirmed from the strings in
`/System/Library/ExtensionKit/Extensions/Appearance.appex` on 27.0. It is stored as
`AppleIconAppearanceTheme` in the global domain (observed value `RegularDark` while the Dark style
was selected) and applies to every app icon on the system. An app supplies the layers; the user
picks the style. The same binary also mentions an "automatic" icon theme and a separate tint
control (Auto / Always / Light / Dark) that were not investigated.

Observed on 27.0 (user screenshots, 2026-09-22) with three hand-built Icon Composer candidates in
the toolbar — A: light grey tile, dark mark; B: white tile, dark mark; C: dark tile, light mark —
beside Yatu's `.icns` and OpenInTerminal-Lite:

| Style | What happens |
|---|---|
| **Default** | Each icon as authored. A and B glare against a dark toolbar; C sits in it. The `.icns` icons show their light plate in both appearances. |
| **Dark** | **The authored dark layers are used** — A and B become dark tiles with light marks. Legacy `.icns` icons get a dark plate too, so the plate follows icon style even though it ignores light/dark appearance. |
| **Clear** | All five converge to near-identical translucent dark tiles. The background is discarded and the mark is rendered as glass, so the tile colour stops mattering and only the silhouette identifies the app. |
| **Tinted** | The mark is derived from the **foreground layer's luminance**. C's light mark tints to a bright, legible blue; **A's and B's dark marks tint to almost nothing** and are barely visible. The `.icns` icons, whose glyph is mid grey, land in between. |

**Consequence for design, and it is not a matter of taste:** a foreground layer that is *dark on a
light background* fails the Tinted style. For an icon to work across all four styles the mark must
be light and the background dark. That, plus Default-style behaviour on a dark toolbar, is why
Yatu's tile is dark with a light mark.

### 2.6 Active versus inactive Finder windows

Observed by the user on 26.6.2, dark appearance:

- **Active window:** OpenInTerminal (full) is its blue tile. OpenInTerminal-Lite and Yatu are dark
  glyphs on the light plate.
- **Inactive window:** the whole toolbar dims. The neutral icons keep their shape on a darker plate
  with less contrast. OpenInTerminal (full) changes rendering: its tile goes dark grey and its bolt
  becomes a faint circle.

Observed by the user on **27.0, light appearance** (screenshot, 2026-09-22), two Finder windows:

- **Active:** OpenInTerminal (full) is its blue tile; OpenInTerminal-Lite and Yatu are dark glyphs
  on the light plate.
- **Inactive:** OpenInTerminal (full) becomes a flat mid-grey tile with its `>` and bolt still
  legible in white — a clean monochrome rendering, not the corruption GH-283 describes.
  OpenInTerminal-Lite and Yatu fade: lighter glyph, lighter plate, same shape. Finder's own pill
  buttons fade the same way.

Observed on **27.0, light and dark**, with the size probe in the toolbar (screenshots,
2026-09-22): in an inactive window the probe's **green tile turns grey**. The probe is an
`.icns`-only icon with no appearance renditions at all, so **the toolbar desaturates every icon in
an inactive window**, legacy or Icon Composer alike.

That weakens an earlier inference, kept here struck through so the reasoning can be followed:
~~the inactive state draws Icon Composer icons from a monochrome rendition — the catalog's
`ISAppearanceTintable` group — rather than dimming the colour one.~~ OpenInTerminal's grey
inactive tile is explained by the same system desaturation that greys the probe; no special
rendition is needed to account for it. Whether the tintable rendition plays any part is unknown. This build of the full
app has the `.icon` in the app target only and renders cleanly when inactive on 27.0; GH-283's
corruption was reported against builds that carried it in four targets. Not yet observed on 27.0
in dark appearance.

Consequence for design: in a Finder toolbar, **colour is removed whenever the window loses focus**,
so an icon cannot rely on colour to be recognisable there. Silhouette survives both states.

### 2.7 Release notes

- macOS **26.7** (14 September 2026) is a security-only update
  ([MacRumors](https://www.macrumors.com/2026/09/14/apple-releases-macos-tahoe-26-7/)). Nothing in
  it concerns icons.
- The Icon Composer bug widely reported in 2025 was the opposite direction to GH-283: apps built
  with Xcode 26 beta 3 showed **generic icons on older macOS** while rendering correctly on 26
  ([Eclectic Light](https://eclecticlight.co/2025/07/10/tahoe-b3-and-xcode-26-b3-can-screw-app-icons/)).
  Apple listed it in the beta 3 release notes; later betas addressed it. It says nothing about
  toolbar rendering on 26.x.

## 3. The Yatu icon, as built on 2026-09-21

`bin/make-icon.swift` writes an `.icns` only, with different artwork by size: a grey template-style
folder glyph at 16 and 32 pt, a violet folder tile at 128 pt and up. That split is only possible
with `.icns`; it is not Icon Composer and does not follow Apple's documented implementation (1.2,
1.3). Its toolbar appearance is therefore the plate treatment in 2.4.

## 4. GH-283 — notes for a later session (no action taken)

**Symptom** (issue text, 2026-08-05): on 26.6 the toolbar icon of both OpenInTerminal 2.3.9 and
OpenInTerminal-Lite 1.2.8 "becomes visually corrupted" **only while the Finder window is inactive**;
refocusing restores it. Reproduced on two Macs; a second reporter confirms. The issue's screenshot:
`https://github.com/user-attachments/assets/ef84ec37-106d-4fc9-a471-8ce92b01b472` (not downloaded
here).

**Upstream configuration at the time** (observed from `upstream/master`):

- OpenInTerminal (full): `AppIcon.icon` was in the Resources phase of **four** targets — the app,
  `OpenInTerminalCore`, `OpenInTerminalFinderExtension` and `OpenInTerminalHelper` — all of which
  are embedded in the app bundle, with `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- OpenInTerminal-Lite: `AppIcon.icon` in Resources **and** `Assets.xcassets/AppIcon.appiconset`,
  both named `AppIcon`, with `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

**What the fork's fix did** (PR [GH-287](https://github.com/Ji4n1ng/OpenInTerminal/pull/287),
commits `96acd51`, `b338bff` in this repository):

- Full app: removed `AppIcon.icon` from Core, the Finder extension and the Helper; **kept it in the
  app target**. The full app still ships an Icon Composer icon, with `ISAppearanceTintable`
  renditions (observed in the build at `e94c429`).
- Lite: removed `AppIcon.icon` entirely. Lite now ships a classic asset-catalog icon with no
  appearance renditions, so it falls under the legacy plate treatment (2.4) — which is why its
  toolbar icon sits on a grey plate today.

**Correction of an earlier claim.** This fork's notes and an earlier session said Icon Composer
"broke" on 26.6. The evidence does not support that. The fix removed **duplicate icon sources** —
four nested copies in one case, two same-named sources in the other — not the format.

**Hypotheses to test, none verified:**

1. The inactive-window state selects the tintable/monochrome rendition (2.6). If a bundle carries
   conflicting renditions — nested bundles each with their own copy, or two sources named
   `AppIcon` — that rendition is where the conflict would show, and only while inactive. That fits
   the "inactive only" symptom.
2. Lite's current plate is not a bug but the consequence of the fix: with no Icon Composer icon, it
   is a legacy icon (2.4).
3. A single, correctly configured Icon Composer icon (one `.icon`, one target, no competing
   `AppIcon` asset) renders correctly in both states. Suggested test: build Lite with the `.icon`
   restored and the `.appiconset` removed, then check the toolbar active and inactive, on 26.6.x
   and 27.0.

**The toolbar on this Mac runs the fork's own builds** of OpenInTerminal and OpenInTerminal-Lite from
`~/dev/oss/openinterminal/export` at `e94c429`, not upstream releases (2.1).

## 6. The other path: a Finder Sync extension

Investigated 2026-09-22 after noticing that BetterZip's toolbar item appears in Finder's
customisation palette with a name and does not change with icon style. Everything in sections 1–4
concerns the **app-icon** path, where Finder draws the icon of an application someone ⌘-dragged in.
An extension is a different mechanism with different rules.

### 6.1 What it is

Observed. BetterZip, Keka, Beyond Compare, Dropbox, OneDrive and Google Drive all ship a
**Finder Sync extension** (`.appex`, extension point `com.apple.FinderSync`). The extension
declares `toolbarItemName`, `toolbarItemToolTip` and `toolbarItemImage`. When that image is a
**template**, the system tints it exactly like Finder's own symbols. Consequences, all observed:

- it appears in the customisation palette as a named item, not as a dragged-in application;
- it is unaffected by the Default / Dark / Clear / Tinted icon styles (§2.5b), because those apply
  to app icons and widgets, not to controls;
- it matches Finder's own buttons in every appearance, which no app icon can do.

The full OpenInTerminal app already does this: its extension's `toolbarItemImage` comes from an
asset marked `template-rendering-intent: template` (§2.2).

### 6.2 Sandboxing, and how shipping extensions actually act

Observed from the installed bundles' signed entitlements:

| | App sandbox | App group | Apple Events | How the click acts |
|---|---|---|---|---|
| BetterZip extension | **yes** | yes | no | `openURL:` to the host app's `btrzp` URL scheme |
| Keka extension | **yes** | yes | no | `launchApplicationAtURL:options:configuration:error:` |
| BetterZip **main app** | **no** | — | — | does the work itself |
| Keka main app | yes | — | — | — |

Two findings follow:

1. **The extension is sandboxed; the containing app need not be.** BetterZip ships exactly that
   combination, so Yatu's app could stay as it is today.
2. **Neither extension executes anything or scripts anything.** Both hand the work to their main
   app and stop. That is the opposite of upstream's design, whose sandboxed path runs an installed
   AppleScript through `NSUserAppleScriptTask` — the `do shell script` route where the quoting
   findings live.

So upstream's AppleScript path is **not** required by the platform. An extension that only passes a
URL to the app avoids finding F1 by construction: the extension executes nothing, and the app
applies the rules it already has (rule 3 — a terminal is only ever handed an existing directory).

*(A first pass at this table reported none of the extensions as sandboxed. That was wrong: the
check piped `codesign`'s XML through `plutil` incorrectly and produced empty output, which was read
as absence. The entitlements above are from `codesign -d --entitlements :-`.)*

### 6.3 Can it be built without Xcode?

Observed, partly. An extension binary compiles and links outside an Xcode project:

```
xcrun swiftc -target arm64-apple-macos13.0 -framework FinderSync -framework AppKit \
  -o YatuFinderSync main.swift
```

with a `FIFinderSync` subclass and `@_silgen_name("NSExtensionMain")` as the entry point — the same
thing Xcode's template does. The binary links against `FinderSync.framework` correctly.

**Not verified:** that the assembled `.appex` loads and appears in Finder. That needs the bundle
(`CFBundlePackageType = XPC!`, an `NSExtension` dictionary naming the principal class), signing
with the sandbox entitlement, and the user enabling it in System Settings. The principal class name
must match what the Objective-C runtime sees, so it needs `@objc(Name)` or a module-qualified name.

### 6.4 What it would cost Yatu

- **A second bundle**, assembled, signed and notarised as nested code by `bin/build.sh`.
- **An extra install step:** the user must enable the extension in System Settings. A dragged-in
  app needs no such step.
- **A new hand-off surface.** A custom URL scheme is public — any application or web page can
  invoke it. `NSWorkspace.openApplication` with arguments is narrower. Either way it is a new entry
  point into Yatu and needs its own review.
- **Plan changes:** §4's architecture is one package and two executables with no extension, and
  §1 records "no app group". An extension may need a group; Keka and BetterZip both declare one,
  though a pure hand-off design might not.
- **It is the component the fork deliberately excludes.** `CLAUDE.md` says the Finder extension is
  kept untouched and unsupported, and the security review's only High finding is an extension
  finding.

### 6.5 What it would buy

- A toolbar item that is correct in all four icon styles and matches Finder's own buttons — the
  convention §1.1 describes, which the app-icon path cannot reach.
- **It separates the two problems.** The toolbar would use the extension's template glyph, so the
  app icon would no longer need to work at toolbar size. A colour app icon for the Dock and Finder
  plus a monochrome toolbar glyph becomes possible — the combination that sections 2.3–2.5b show is
  impossible with an app icon alone.

### 6.6 Prototype results (2026-09-22)

A throwaway host app with an embedded Finder Sync extension was built, ad-hoc signed, installed and
driven by the user on macOS 27.0. Everything below is observed.

**It works, and it can be built the way Yatu builds.**

- A hand-assembled `.appex` — compiled with `swiftc`, `CFBundlePackageType = XPC!`, an `NSExtension`
  dictionary naming an `@objc` principal class, ad-hoc signed with `com.apple.security.app-sandbox`
  — **registers with `pluginkit` and runs**. No Xcode project is needed.
- The item **appears in Finder's customisation palette** with its name, beside BetterZip.
- In the toolbar it is drawn as a **pill-shaped control matching Finder's own buttons**, not as a
  tile among app icons.
- It is **unaffected by the icon styles**: with the Dark style selected, every app icon in the row
  became a black tile while the extension's item stayed a light pill with a dark glyph. This is the
  behaviour §2.5b shows an app icon cannot have.
- The whole chain runs: click → `targetedURL()` → the extension opens a URL → the containing app
  receives the path intact. The extension executes nothing.

**Costs and constraints found by building it:**

1. **A toolbar click asks for a menu, not an action.** The only entry point is
   `menu(for: .toolbarItemMenu)`, and the system draws a **disclosure chevron** beside the glyph.
   Acting inside that callback and returning a menu works, but v1 returned an empty `NSMenu` and an
   empty menu visibly flashed. The Swift signature is optional, so `nil` can be returned instead.
   **A one-click item like Yatu's today may not be reachable; a menu-shaped interaction is inherent.**
2. **`targetedURL()` is nil unless the folder is inside `directoryURLs`.** Watching only the home
   folder returned nothing everywhere else. A general tool must watch `/`.
3. **`NSWorkspace.OpenConfiguration.arguments` did not arrive.** The app launched with no
   arguments. A **URL scheme worked** (BetterZip's approach), and a sandboxed extension is
   permitted to open one. Keka's `launchApplicationAtURL:` is the other known-good route.
4. **A URL scheme is a public entry point.** Any application or web page can invoke
   `yatu://open?path=…`. Yatu's existing rules already constrain what a path may be (rule 3), but
   this is a new surface that needs its own review.
5. **`os.Logger` output from the sandboxed extension never reached the unified log**, under either
   its subsystem or its process name, which made debugging blind. The host app writing to a file
   was the workable channel. Worth knowing before building the real thing.
6. **`NSImage`'s lazy drawing handler is unreliable here.** The glyph rendered initially, then
   disappeared after a reload leaving a bare chevron. Drawing into an `NSBitmapImageRep` instead is
   deterministic.

**What it would mean for Yatu.** The toolbar item would stop being the app icon, so the app icon
would no longer have to survive at toolbar size — a colour app icon for the Dock and Finder plus a
system-tinted monochrome toolbar glyph becomes possible, which §§2.3–2.5b show is unreachable
otherwise. Against that: a second signed and notarised bundle, an extension the user must enable, a
new public entry point, the sandbox, and an interaction shaped like a menu rather than a button.

## 5. Sources

Apple:

- [Human Interface Guidelines — Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
  (fetched via its JSON endpoint; the page renders client-side)
- [Human Interface Guidelines — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Configuring your app icon](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
  — says nothing macOS-specific about Icon Composer, build settings or Info.plist keys

Third party:

- [Eclectic Light — Tahoe b3 and Xcode 26 b3 can screw app icons](https://eclecticlight.co/2025/07/10/tahoe-b3-and-xcode-26-b3-can-screw-app-icons/)
- [Successful Software — Updating application icons for macOS 26 Tahoe and Liquid Glass](https://successfulsoftware.net/2025/09/26/updating-application-icons-for-macos-26-tahoe-and-liquid-glass/)
  — recommends shipping `Assets.car` and the legacy `.icns` together; notes legacy icons look poor
  when the app is inactive or a non-default icon style is chosen
- [MacRumors — Apple Releases macOS Tahoe 26.7](https://www.macrumors.com/2026/09/14/apple-releases-macos-tahoe-26-7/)
- [Ji4n1ng/OpenInTerminal GH-283](https://github.com/Ji4n1ng/OpenInTerminal/issues/283)

Local tools used: `assetutil --info`, `actool`, `iconutil`, `lsregister`, `NSWorkspace` rendering
scripts. The throwaway test apps — `IconSizeProbe.app` (one colour and label per `.icns` slot),
`IconTest-Legacy.app` and `Yatu-Composer.app`, bundle ids `com.altmansoftwaredesign.icontest.*` —
were installed in `/Applications` for these measurements and **removed on 2026-09-22**. To repeat
a measurement, rebuild the probe: ten solid-colour PNGs, each labelled with its slot name, packed
with `iconutil` into an `.icns`-only app bundle.
