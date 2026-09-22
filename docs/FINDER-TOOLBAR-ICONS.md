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
