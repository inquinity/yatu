# 1.0.2

Fixes the Finder button and the menu behaving differently depending on what had
already been opened, and trims the settings window to what you can actually
choose.

## The menu did the wrong thing, or nothing

Opening a window left the app unable to answer anything else. Three faults came
out of one cause, and all three were visible:

- **A window sometimes did not appear.** Settings and About each installed
  their own application delegate and started a second run loop, then built
  their window in `applicationDidFinishLaunching` — a notification already
  delivered for that process. Whether it arrived again depended on event
  timing, so About worked, then failed, then worked.
- **The wrong thing happened.** Once a window had displaced the delegate, the
  next toolbar click reached that window instead: it raised itself and threw
  the request away. Clicking for a terminal produced the About box.
- **A window could be closed by an unrelated request.** A request the app
  declined took the process down with it, whatever was on screen.

A process has one delegate and one run loop, and the app now treats them that
way. Windows are built, shown and raised by the one object that knows what else
is open; a second request for a window already up raises it rather than
stacking another behind it; and a toolbar click while About is open opens a
terminal and leaves About where it was.

Reopening Yatu while it is already running now works too — that arrives without
a URL, so nothing had been listening for it.

## Settings shows what you can choose

Every supported application used to be listed, with the ones you do not have
greyed out — a dozen or more rows that cannot be picked, in the window whose
only job is picking. They are gone, and the window sizes itself to what is left
rather than to a fixed height chosen for the long list.

The full list moved to the README, under **Supported terminals and editors**,
which settings links to when something is missing.

## About

The Finder button's menu gains **About Yatu**, showing the version, the build
and the repository. It is also reachable as `yatu://about`.
