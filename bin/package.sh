#!/bin/bash
#
# Package a signed, notarized Yatu.app into a distributable DMG.
#
# Run after bin/build.sh --release and bin/notarize.sh. The app inside carries
# its own stapled ticket, so it opens even if the DMG is copied somewhere the
# ticket cannot be fetched; the DMG is notarized and stapled as well, because
# that is the file people actually download.
#
# ## Outputs
#
#   dist/Yatu-<version>.dmg      the artifact a release and the cask point at
#   dist/SHA256SUMS              what the cask's sha256 must match
#
# ## What it refuses
#
# A DMG built from an app that is not signed, or not notarized, is a download
# that warns on every machine. Both are checked before anything is built, and
# the finished DMG is checked again with spctl -- the question being not "did
# the commands succeed" but "would Gatekeeper let this run".
#
# The full colour palette is declared in every script by convention, so the set
# is identical everywhere; not every script uses every colour.
# shellcheck disable=SC2034
set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}%s${COLOR_RESET}\n" "$message"
}

TEAM_ID="45GJWJVQN2"
NOTARY_PROFILE="${NOTARY_PROFILE:-altman-notary}"
OUTPUT_DIR="dist"
APP_NAME="Yatu"

skip_notarization=0

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [--skip-notarization] [-h|--help]

Package $OUTPUT_DIR/$APP_NAME.app into a DMG and write SHA256SUMS.

Run first:
  bin/build.sh --release
  bin/notarize.sh

Options:
      --skip-notarization   Build the DMG but do not notarize or staple it.
                            The result is NOT distributable; for checking the
                            packaging itself without uploading.
  -h, --help                Show this help

Environment:
  NOTARY_PROFILE  notarytool keychain profile. Default: altman-notary"
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

while (( $# )); do
    case "$1" in
        --skip-notarization) skip_notarization=1 ;;
        -h|--help)           usage; exit 0 ;;
        *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

app="$OUTPUT_DIR/$APP_NAME.app"
version="$(bin/ver short)"
dmg="$OUTPUT_DIR/$APP_NAME-$version.dmg"
checksums="$OUTPUT_DIR/SHA256SUMS"

# MARK: - Refuse to package something undistributable

[[ -d "$app" ]] || die "$app does not exist; run bin/build.sh --release first"
command -v hdiutil >/dev/null || die "hdiutil not found"

print_colored "$COLOR_CYAN" "Checking the app"
signature="$(codesign -dvv "$app" 2>&1 || true)"
[[ "$signature" == *"TeamIdentifier=$TEAM_ID"* ]] \
    || die "$app is not signed by team $TEAM_ID. Run: bin/build.sh --release"
xcrun stapler validate "$app" >/dev/null 2>&1 \
    || die "$app has no stapled notarization ticket. Run: bin/notarize.sh"
print_colored "$COLOR_GREEN" "  signed by $TEAM_ID, notarized, ticket stapled"

# MARK: - Build the image

# A staging directory, so the DMG contains exactly the app and the shortcut and
# nothing that happens to be sitting in dist/.
staging="$(mktemp -d "${TMPDIR:-/tmp}/yatu-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/$APP_NAME.app" || die "could not stage the app"
ln -s /Applications "$staging/Applications"

print_colored "$COLOR_CYAN" "Building $dmg"
rm -f "$dmg"
hdiutil create -quiet -srcfolder "$staging" -volname "$APP_NAME $version" \
    -format UDZO -fs HFS+ "$dmg" \
    || die "hdiutil failed"

# MARK: - Notarize the download itself

if (( skip_notarization )); then
    print_colored "$COLOR_BRIGHTYELLOW" "  skipped notarization — this DMG is NOT distributable"
else
    print_colored "$COLOR_CYAN" "Signing and notarizing the DMG"
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | grep "($TEAM_ID)" | sed 's/.*"\(.*\)"/\1/')"
    [[ -n "$identity" ]] || die "no Developer ID Application identity for team $TEAM_ID"
    codesign --force --sign "$identity" --timestamp "$dmg" || die "could not sign the DMG"

    local_log="$OUTPUT_DIR/$APP_NAME-dmg-notarization.json"
    if ! xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" \
            --wait --output-format json > "$local_log" 2>&1; then
        cat "$local_log" >&2
        die "DMG notarization submission failed"
    fi
    status="$(/usr/bin/python3 -c '
import json, sys
try:    print(json.load(open(sys.argv[1])).get("status", "unknown"))
except Exception: print("unparseable")' "$local_log")"
    [[ "$status" == "Accepted" ]] || die "DMG notarization status: $status (see $local_log)"
    xcrun stapler staple "$dmg" || die "could not staple the DMG"
    print_colored "$COLOR_GREEN" "  Accepted and stapled"
fi

# MARK: - Checksums, and the question that matters

print_colored "$COLOR_CYAN" "Checksums"
( cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$checksums")" )
print_colored "$COLOR_YELLOW" "  $(cat "$checksums")"

if (( ! skip_notarization )); then
    print_colored "$COLOR_CYAN" "Gatekeeper assessment of the DMG"
    spctl --assess --type open --context context:primary-signature -vv "$dmg" 2>&1 | sed 's/^/  /' \
        || die "spctl rejects the DMG"
fi

print_colored "$COLOR_GREEN" "
Done. $dmg"
print_colored "$COLOR_YELLOW" "sha256 for the cask:
  $(awk '{print $1}' "$checksums")"
