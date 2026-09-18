#!/bin/bash
#
# Build, Developer-ID sign, NOTARIZE and staple OpenInTerminal, OpenInTerminal-Lite
# and OpenInEditor-Lite for distribution outside the Mac App Store.
#
# Unlike build-unsigned.sh (ad-hoc "Sign to Run Locally"), this produces artifacts
# that pass Gatekeeper and satisfy Homebrew/cask's "signed AND notarized" rule.
#
# Strategy: build each app with signing turned off (so Xcode never demands a
# provisioning profile for the app-groups / sandbox capabilities), then re-sign
# the finished bundles with a "Developer ID Application" certificate, enabling the
# hardened runtime (--options runtime) and a secure timestamp (--timestamp) — both
# mandatory for notarization. The bundle is then zipped, submitted to Apple's
# notary service, and the resulting ticket is stapled into the .app.
#
# For the full OpenInTerminal app the login-item helper is embedded into
# Contents/Library/LoginItems and signed too, so "Launch at Login" works.
#
# Output: ./export/<App>.app  (stapled)  and  ./export/<App>.zip  (ready to upload)
#
# ---------------------------------------------------------------------------
# Prerequisites (all tied to your paid Apple Developer account):
#
#   1. A "Developer ID Application" certificate installed in your login keychain.
#         security find-identity -v -p codesigning | grep "Developer ID Application"
#      Create it at https://developer.apple.com/account/resources/certificates
#      (or via Xcode > Settings > Accounts > Manage Certificates > +).
#
#   2. Notary credentials stored as a keychain profile (recommended):
#         xcrun notarytool store-credentials "OpenInTerminal-notary" \
#           --apple-id "you@example.com" \
#           --team-id  "XXXXXXXXXX" \
#           --password "app-specific-password"      # appleid.apple.com > App-Specific Passwords
#      ...or with an App Store Connect API key:
#         xcrun notarytool store-credentials "OpenInTerminal-notary" \
#           --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
#
# Configuration (override via environment):
#   SIGN_ID         signing identity; default: auto-detected Developer ID Application
#   NOTARY_PROFILE  notarytool keychain profile name; default: OpenInTerminal-notary
#   SKIP_NOTARIZE   set to 1 to sign only (no notarization/stapling) — for testing
#   DEPLOYMENT_TARGET  macOS deployment target; default: 12.0 (Xcode 27 minimum)
#
# Usage: ./build-signed.sh [scheme ...]   # default: all three apps
# ---------------------------------------------------------------------------
set -euo pipefail

# Fork-owned copy of upstream's build script; the upstream original stays at the
# repo root. Always operate on the repo, not on the caller's directory: the
# paths below (and the `rm -rf "$EXPORT_DIR"`) are repo-relative.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKSPACE="OpenInTerminal.xcworkspace"
CONFIG="Release"
DERIVED="build"
EXPORT_DIR="export"
PRODUCTS="$DERIVED/Build/Products/$CONFIG"
EXT_ENT="OpenInTerminalFinderExtension/OpenInTerminalFinderExtension.entitlements"
HELPER="OpenInTerminalHelper.app"

NOTARY_PROFILE="${NOTARY_PROFILE:-OpenInTerminal-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
# Xcode 27 rejects deployment targets below macOS 12.0, which the projects
# still use; override at build time instead of editing the projects.
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-12.0}"

# scheme:app-entitlements pairs
TARGETS=(
  "OpenInTerminal:OpenInTerminal/OpenInTerminal.entitlements"
  "OpenInTerminal-Lite:OpenInTerminal-Lite/OpenInTerminal-Lite/OpenInTerminal-Lite.entitlements"
  "OpenInEditor-Lite:OpenInEditor-Lite/OpenInEditor-Lite/OpenInEditor-Lite.entitlements"
)

# Optional scheme arguments restrict the build to those apps.
if [[ $# -gt 0 ]]; then
  selected=()
  for wanted in "$@"; do
    match=""
    for pair in "${TARGETS[@]}"; do
      [[ "${pair%%:*}" == "$wanted" ]] && match="$pair"
    done
    if [[ -z "$match" ]]; then
      echo "!! Unknown scheme '$wanted' (expected OpenInTerminal, OpenInTerminal-Lite or OpenInEditor-Lite)" >&2
      exit 1
    fi
    selected+=("$match")
  done
  TARGETS=("${selected[@]}")
fi

# --- Resolve the signing identity ------------------------------------------
if [[ -z "${SIGN_ID:-}" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n1)"
fi
if [[ -z "${SIGN_ID:-}" ]]; then
  echo "!! No 'Developer ID Application' identity found in the keychain." >&2
  echo "   Install one from your Apple Developer account, or set SIGN_ID explicitly." >&2
  echo "   Available identities:" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi
echo "==> Signing identity: $SIGN_ID"

# --- Verify notary credentials up front (fail fast, before the long build) --
if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "!! Notary keychain profile '$NOTARY_PROFILE' is missing or invalid." >&2
    echo "   Create it with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" ..." >&2
    echo "   (see the header of this script), or run with SKIP_NOTARIZE=1 to sign only." >&2
    exit 1
  fi
  echo "==> Notary profile '$NOTARY_PROFILE' OK"
fi

# Developer-ID sign an .app bundle strictly leaf-first so every inner signature
# is sealed before the bundle that contains it:
#   dylibs -> frameworks -> app extensions -> nested (helper) apps -> the app
# Every signature uses the hardened runtime (--options runtime) and a secure
# timestamp (--timestamp); both are required by the notary service.
sign() {  # $1 = .app bundle, $2 = app entitlements
  local app="$1" ent="$2"
  local common=(--force --options runtime --timestamp --sign "$SIGN_ID")
  find "$app" -type f -name "*.dylib" -print0 | while IFS= read -r -d '' d; do
    codesign "${common[@]}" "$d"
  done
  find "$app" -type d -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
    codesign "${common[@]}" "$fw"
  done
  find "$app" -type d -name "*.appex" -print0 | while IFS= read -r -d '' ext; do
    codesign "${common[@]}" --entitlements "$EXT_ENT" "$ext"
  done
  # nested apps (e.g. the login-item helper)
  find "$app" -mindepth 1 -type d -name "*.app" -print0 | while IFS= read -r -d '' sub; do
    codesign "${common[@]}" "$sub"
  done
  codesign "${common[@]}" --entitlements "$ent" "$app"
}

# Mark every bundle (app, extensions, helper) as a fork build so it can be
# told apart from the upstream release. Custom keys are used because
# CFBundleVersion must stay numeric. Must run before signing.
BUILD_SOURCE="inquinity"
BUILD_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ "$BUILD_COMMIT" != "unknown" ]] && ! git diff --quiet HEAD --; then
  BUILD_COMMIT="$BUILD_COMMIT-dirty"
fi
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

set_plist_string() {  # $1 = Info.plist, $2 = key, $3 = value
  /usr/libexec/PlistBuddy -c "Delete :$2" "$1" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$2 string $3" "$1"
}

stamp_build_info() {  # $1 = .app bundle
  find "$1" -path "*/Contents/Info.plist" -print0 | while IFS= read -r -d '' plist; do
    set_plist_string "$plist" OITBuildSource "$BUILD_SOURCE"
    set_plist_string "$plist" OITBuildCommit "$BUILD_COMMIT"
    set_plist_string "$plist" OITBuildDate "$BUILD_DATE"
  done
}

rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

for pair in "${TARGETS[@]}"; do
  scheme="${pair%%:*}"
  ent="${pair#*:}"
  echo "==> Building $scheme (unsigned)"
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$scheme" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -destination 'generic/platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    build >/dev/null

  app="$PRODUCTS/$scheme.app"

  # Embed the login-item helper into the full app so "Launch at Login" works.
  if [[ "$scheme" == "OpenInTerminal" ]]; then
    if [[ -d "$PRODUCTS/$HELPER" ]]; then
      echo "==> Embedding $HELPER into LoginItems"
      mkdir -p "$app/Contents/Library/LoginItems"
      rm -rf "$app/Contents/Library/LoginItems/$HELPER"
      cp -R "$PRODUCTS/$HELPER" "$app/Contents/Library/LoginItems/"
    else
      echo "!! $HELPER not found in products; Launch-at-Login will be unavailable"
    fi
  fi

  echo "==> Stamping $scheme.app as $BUILD_SOURCE@$BUILD_COMMIT"
  stamp_build_info "$app"

  echo "==> Developer-ID signing $scheme.app"
  sign "$app" "$ent"
  codesign --verify --deep --strict --verbose=2 "$app"

  cp -R "$app" "$EXPORT_DIR/"
  out="$EXPORT_DIR/$scheme.app"

  if [[ "$SKIP_NOTARIZE" == "1" ]]; then
    echo "==> SKIP_NOTARIZE=1 — zipping signed (not notarized) $scheme"
    ditto -c -k --sequesterRsrc --keepParent "$out" "$EXPORT_DIR/$scheme.zip"
    echo "==> Exported $EXPORT_DIR/$scheme.zip (signed, NOT notarized)"
    continue
  fi

  # --- Notarize -------------------------------------------------------------
  # notarytool takes a zip (or dmg/pkg). Zip the signed .app, submit, wait.
  submit_zip="$EXPORT_DIR/$scheme-notarize.zip"
  ditto -c -k --sequesterRsrc --keepParent "$out" "$submit_zip"
  echo "==> Submitting $scheme to the notary service (this can take a few minutes)"
  xcrun notarytool submit "$submit_zip" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  rm -f "$submit_zip"

  # Staple the ticket into the .app so Gatekeeper works offline.
  echo "==> Stapling $scheme.app"
  xcrun stapler staple "$out"
  xcrun stapler validate "$out"
  spctl -a -t exec -vv "$out" 2>&1 | sed 's/^/    /'

  # Final distributable zip (contains the stapled app).
  ditto -c -k --sequesterRsrc --keepParent "$out" "$EXPORT_DIR/$scheme.zip"
  echo "==> Exported $EXPORT_DIR/$scheme.zip (signed + notarized + stapled)"
done

echo
echo "Done. Artifacts are in ./$EXPORT_DIR :"
ls -1 "$EXPORT_DIR"
