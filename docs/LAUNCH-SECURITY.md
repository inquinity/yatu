# Can Yatu be used to launch a malicious app?

**Short answer: no, because Gatekeeper stops it — and we tested that rather than assuming it.**

Yatu is a Finder toolbar button that opens your chosen terminal at the folder you are looking at.
Doing that means launching other applications with paths taken from Finder, which is worth being
careful about. This is the write-up of a question raised on 2026-09-24 and the testing that settled
it. Tested on macOS 27 with the real launch code, not an approximation of it.

---

## 1. The issue

Yatu launches other applications with paths taken from Finder. That is its whole purpose, and it is
also its whole attack surface. The security review of the `yatu://` entry point raised a related
worry, and it was then sharpened into a concrete attack:

> An attacker plants a malicious payload saved as `Warp.app` on a system without Warp. The attacker
> then changes Yatu's stored default to Warp. Yatu innocently launches the payload.

The question underneath: **does Yatu enlarge the attack surface in any tangible way?** Specifically,
can Yatu launch an application downloaded from the internet and effectively bypass Gatekeeper — or
can we rely on Gatekeeper and assert that anything Yatu launches was already trusted by the user?

## 2. The conclusion

**We can rely on Gatekeeper. It holds, and Yatu does not enlarge the attack surface.**

Launching through `NSWorkspace` does not launder Gatekeeper. Both halves of the attack were tested:

- An **unsigned** impostor is blocked outright. The user is shown *"Not Opened — Apple could not
  verify…"*, which on macOS 27 offers no "Open Anyway" at all.
- A **notarized but never-approved** app is held for consent: *"…downloaded from the Internet. Are
  you sure you want to open it?"*

In both cases the process was staged and suspended, the quarantine flag was untouched, and the
launch API never called back. **Yatu supplied no consent and had no way to.**

One residual, and it is not specific to Yatu: Gatekeeper assessment is triggered by the
`com.apple.quarantine` attribute. An attacker who *already has code execution* can write a bundle
without that attribute, and it will launch unassessed — through any launcher, not just this one.
Such an attacker does not need Yatu.

## 3. The framing that redirected the analysis

Three observations, each of which narrowed the question:

1. **Replacing an already-installed `iTerm.app` or `Warp.app` is a bigger issue and out of scope.**
   An attacker who can write into `/Applications` has already won, and nothing Yatu does changes
   that.
2. **If the attacker can trigger Yatu to launch the payload, they could open it directly anyway.**
   This is the decisive point. Yatu is unprivileged, holds no entitlement that affects assessment,
   and its launch is attributed normally. It is not a privilege the attacker lacks.
3. **The real question is Gatekeeper**, not the hand-off. Either Yatu can bypass it — which would be
   serious — or it cannot, in which case the user has already trusted whatever Yatu launches.

This reframing mattered. The review had been heading toward authenticating the *sender* of a
`yatu://` request, using the Apple Event's sender PID and a code-signing requirement. That work was
withdrawn: it would have defended an attack that Gatekeeper already stops.

## 4. Testing

Both tests ran against the real `Launcher.swift` call —
`NSWorkspace.open(_:withApplicationAt:configuration:)` — not an approximation of it.

### Test A — unsigned impostor

A harmless payload (it creates a marker file) was packaged as `Ghostty.app` in `~/Downloads`,
claiming `com.mitchellh.ghostty`, a catalog terminal not installed on this Mac, and given a
quarantine attribute to simulate a download.

| Step | Result |
|---|---|
| Does LaunchServices resolve the bundle id to it? | **Yes** — `com.mitchellh.ghostty -> ~/Downloads/Ghostty.app`. No `/Applications` write needed. |
| Gatekeeper assessment | `rejected — source=no usable signature` |
| Yatu's launch call | Staged under App Translocation, then **suspended**. Marker file never created. |
| What the user saw | *"Ghostty.app" Not Opened — Apple could not verify…* with only **Move to Trash** / **Done**. No "Open Anyway". |

**The resolution half of the attack works. The execution half does not.**

### Test B — notarized, installed, never approved

Warp installed with `brew install --cask warp` and deliberately never opened.

| Step | Result |
|---|---|
| Gatekeeper assessment | `accepted — Notarized Developer ID Application: Denver Technologies, Inc` |
| Quarantine before the test | present — never approved |
| Yatu's launch call | No callback within 10s. Process staged, `finishedLaunching=false`, `active=false`. |
| What the user saw | *"Warp.app" is an app downloaded from the Internet. Are you sure you want to open it?* with **Cancel** / **Open**. |

**A notarized app still requires consent on first launch, and Yatu cannot give it.**

*Note on this test:* the quarantine attribute was found cleared afterwards, so the prompt was
approved at some point rather than cancelled. That does not affect the finding — the launch was held
pending a human either way — but it is recorded rather than glossed over.

### Incidental findings

- **A bundle identifier is not a trust signal.** Rule 1 in [the roadmap](DESIGN.md) justifies resolving by bundle id
  rather than by name on the grounds that *"a name is a string a user can control, a bundle id is
  what LaunchServices indexes."* Test A disproves the implied guarantee: LaunchServices resolved a
  planted identifier straight to `~/Downloads`. Bundle-id resolution is still preferable, but the
  security comes from Gatekeeper, not from the identifier. **The rule's rationale should be
  corrected.**
- **The Warp catalog entry is stale.** The catalog says `dev.warp`; the real identifier is
  `dev.warp.Warp-Stable`. `dev.warp` resolves to nothing, so Warp works only through rule 2's
  `/Applications/<name>.app` fallback. This is the third confirmed stale entry after
  `com.apple.Xcode` and `com.sublimetext.3` — more evidence for the plan's §9.6, that the app
  catalog Yatu inherited from OpenInTerminal is not an authoritative source and needs checking
  against the real applications.

### Cleanup

The planted bundle was removed, its LaunchServices registration withdrawn, the staged processes
killed, and `com.mitchellh.ghostty` confirmed to resolve to nothing again.
