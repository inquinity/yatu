#!/bin/bash
#
# Build and export OpenInTerminal, OpenInTerminal-Lite and OpenInEditor-Lite
# WITHOUT an Apple Developer account.
#
# Strategy: build each app with signing turned off (so Xcode never demands a
# provisioning profile for the app-groups / sandbox capabilities), then re-sign
# the finished bundles ad-hoc ("Sign to Run Locally"). Ad-hoc signing is enough
# for the apps to launch and for the Finder extension to be enabled locally.
#
# For the full OpenInTerminal app the login-item helper is embedded into
# Contents/Library/LoginItems and signed too, so "Launch at Login" works.
#
# Output: ./export/<App>.app
#
set -euo pipefail

WORKSPACE="OpenInTerminal.xcworkspace"
CONFIG="Release"
DERIVED="build"
EXPORT_DIR="export"
PRODUCTS="$DERIVED/Build/Products/$CONFIG"
EXT_ENT="OpenInTerminalFinderExtension/OpenInTerminalFinderExtension.entitlements"
HELPER="OpenInTerminalHelper.app"
# Xcode 27 rejects deployment targets below macOS 12.0, which the projects
# still use; override at build time instead of editing the projects.
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-12.0}"

# scheme:app-entitlements pairs
TARGETS=(
  "OpenInTerminal:OpenInTerminal/OpenInTerminal.entitlements"
  "OpenInTerminal-Lite:OpenInTerminal-Lite/OpenInTerminal-Lite/OpenInTerminal-Lite.entitlements"
  "OpenInEditor-Lite:OpenInEditor-Lite/OpenInEditor-Lite/OpenInEditor-Lite.entitlements"
)

# Ad-hoc sign an .app bundle strictly leaf-first so every inner signature is
# sealed before the bundle that contains it:
#   dylibs -> frameworks -> app extensions -> nested (helper) apps -> the app
adhoc_sign() {  # $1 = .app bundle, $2 = app entitlements
  local app="$1" ent="$2"
  find "$app" -type f -name "*.dylib" -print0 | while IFS= read -r -d '' d; do
    codesign --force --sign - "$d"
  done
  find "$app" -type d -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
    codesign --force --sign - "$fw"
  done
  find "$app" -type d -name "*.appex" -print0 | while IFS= read -r -d '' ext; do
    codesign --force --sign - --entitlements "$EXT_ENT" "$ext"
  done
  # nested apps (e.g. the login-item helper); signed plain ad-hoc
  find "$app" -mindepth 1 -type d -name "*.app" -print0 | while IFS= read -r -d '' sub; do
    codesign --force --sign - "$sub"
  done
  codesign --force --sign - --entitlements "$ent" "$app"
}

# Mark every bundle (app, extensions, helper) as a local fork build so it can
# be told apart from the upstream/Homebrew release. Custom keys are used
# because CFBundleVersion must stay numeric. Must run before signing.
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

  echo "==> Ad-hoc signing $scheme.app"
  adhoc_sign "$app" "$ent"
  codesign --verify --deep --strict "$app"

  cp -R "$app" "$EXPORT_DIR/"
  echo "==> Exported $EXPORT_DIR/$scheme.app"
done

echo
echo "Done. Apps are in ./$EXPORT_DIR :"
ls -1 "$EXPORT_DIR"
