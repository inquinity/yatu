# Unreleased

The build number shown in About and in the settings footer now means something.

`CFBundleVersion` was reset to 1 on every version change, so 1.0.0, 1.0.1 and
1.0.2 all shipped as **build 1** — the field carried no information, nothing
could order two copies of Yatu by it, and a local build was indistinguishable
from the release it was built on. It is now a single monotonic integer that only
ever goes up, which is what the field is for.

## The supported apps list is Yatu's own, and shorter

Atom, AppCode, Fleet, TextMate and Hyper are no longer supported: each is
discontinued or on life support. If one of them was your chosen app, Yatu will
ask you to pick another the next time you click. Bundle identifiers were
corrected for Sublime Text, VSCodium, Alacritty, CLion, WebStorm, Android Studio
and Zed, so these are now found wherever they are installed and not only in
`/Applications`.

## The toolbar button's folder is more closed

The bar under the folder's tab now reaches the walls, so the button reads as
one shape at toolbar size instead of a floating line.

## Test builds are numbered

A build made from source now reports a dotted build number such as `1.7`, so a
test build can no longer be mistaken for the release it was built on. Releases
are unchanged.

## The app icon follows the system icon style

Yatu's icon is now an Icon Composer icon, so in the Dock, Get Info and Spotlight
it follows System Settings → Appearance → Icon & widget style (Default, Dark,
Clear, Tinted) like other apps. It looks the same in the default style.
