#!/bin/bash
#
# Notarize and staple a signed Yatu.app.
#
# Notarization is Apple checking the app and issuing a ticket saying so.
# Without it Gatekeeper warns on every machine but this one, whatever the
# signature says — see docs/LAUNCH-SECURITY.md for what that warning looks
# like and why it matters.
#
# ## This uploads to Apple
#
# `notarytool submit` sends the app to Apple's notary service and records a
# submission against the developer account. That is the intended path for
# distributing a Mac app outside the App Store, and it is not reversible: the
# submission appears in `xcrun notarytool history` afterwards.
#
# ## What it refuses
#
# Everything is asserted rather than assumed, because a build that silently
# skips a step here is one that warns on every user's Mac:
#
#   * the app must already be signed with the Developer ID for this team,
#     with the hardened runtime on — bin/build.sh --release does that
#   * the submission must come back Accepted, not "Accepted with warnings"
#     inferred from a zero exit code
#   * stapling must succeed, and the stapled app must pass `spctl -a -t exec`,
#     which is the actual question: would Gatekeeper let this run?
#
# The full JSON log is saved next to the app, because when notarization fails
# the reason is in that log and nowhere else.
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

dry_run=0

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [-n|--dry-run] [-h|--help]

Notarize and staple $OUTPUT_DIR/$APP_NAME.app, then verify that Gatekeeper
would let it run.

Build it first:  bin/build.sh --release

This UPLOADS the app to Apple's notary service and records a submission
against the developer account.

Options:
  -n, --dry-run   Check everything and stop before uploading.
  -h, --help      Show this help

Environment:
  NOTARY_PROFILE  notarytool keychain profile. Default: altman-notary"
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

while (( $# )); do
    case "$1" in
        -n|--dry-run) dry_run=1 ;;
        -h|--help)    usage; exit 0 ;;
        *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

app="$OUTPUT_DIR/$APP_NAME.app"
archive="$OUTPUT_DIR/$APP_NAME-notarize.zip"
log_file="$OUTPUT_DIR/$APP_NAME-notarization.json"

# MARK: - Refuse to upload something that cannot pass

[[ -d "$app" ]] || die "$app does not exist; run bin/build.sh --release first"
command -v xcrun >/dev/null || die "xcrun not found; install Xcode"

print_colored "$COLOR_CYAN" "Checking the signature before uploading"

signature="$(codesign -dv "$app" 2>&1)"
# String tests, not `| grep -q`: grep exits on match, the producer takes
# SIGPIPE, and `set -o pipefail` reports the pipeline as failed. Here that
# would refuse to notarize a correctly signed app.
[[ "$signature" == *"TeamIdentifier=$TEAM_ID"* ]] \
    || die "$app is not signed by team $TEAM_ID — this is an ad-hoc build.
  Run: bin/build.sh --release"
[[ "$signature" == *"runtime"* ]] \
    || die "$app does not have the hardened runtime; notarization would reject it"
codesign --verify --strict --deep "$app" || die "$app fails strict deep verification"
print_colored "$COLOR_GREEN" "  signed by $TEAM_ID, hardened runtime on, verifies strictly"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notarytool profile '$NOTARY_PROFILE' is not usable.
  Create it with: xcrun notarytool store-credentials $NOTARY_PROFILE"
print_colored "$COLOR_GREEN" "  notary profile '$NOTARY_PROFILE' works"

if (( dry_run )); then
    print_colored "$COLOR_BRIGHTYELLOW" "
Dry run — everything needed is in place. Nothing was uploaded."
    exit 0
fi

# MARK: - Submit

# ditto -c -k --keepParent preserves the bundle; zip(1) does not, and a
# flattened bundle is rejected.
print_colored "$COLOR_CYAN" "Packaging"
rm -f "$archive"
ditto -c -k --keepParent "$app" "$archive" || die "could not create $archive"

print_colored "$COLOR_CYAN" "Submitting to Apple — this takes a few minutes"
if ! xcrun notarytool submit "$archive" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format json > "$log_file" 2>&1; then
    print_colored "$COLOR_RED" "notarytool failed; the response is in $log_file:"
    cat "$log_file" >&2
    die "submission failed"
fi

status="$(/usr/bin/python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("status", "unknown"))
except Exception:
    print("unparseable")' "$log_file")"

submission="$(/usr/bin/python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("id", ""))
except Exception:
    print("")' "$log_file")"

if [[ "$status" != "Accepted" ]]; then
    print_colored "$COLOR_RED" "Notarization status: $status"
    [[ -n "$submission" ]] && print_colored "$COLOR_YELLOW" "Why:
  xcrun notarytool log $submission --keychain-profile $NOTARY_PROFILE"
    die "not accepted; nothing was stapled"
fi
print_colored "$COLOR_GREEN" "  Accepted (submission $submission)"

# The reasons behind an acceptance matter too: Apple reports warnings here.
xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" \
    "$OUTPUT_DIR/$APP_NAME-notarization-log.json" >/dev/null 2>&1 || true

# MARK: - Staple and verify

print_colored "$COLOR_CYAN" "Stapling"
xcrun stapler staple "$app" || die "stapling failed"
xcrun stapler validate "$app" || die "the stapled ticket does not validate"

# The question that actually matters: would Gatekeeper let this run?
print_colored "$COLOR_CYAN" "Gatekeeper assessment"
spctl --assess --type execute -vv "$app" 2>&1 | sed 's/^/  /' \
    || die "spctl rejects the app even after stapling"

rm -f "$archive"
print_colored "$COLOR_GREEN" "
Done. $app is signed, notarized and stapled.
It will open on any Mac without a Gatekeeper warning."
print_colored "$COLOR_YELLOW" "Notarization record: $log_file"
