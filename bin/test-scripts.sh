#!/bin/bash
#
# Tests for the shell in bin/. Two things are worth testing here, and both
# earned their place by producing confident wrong output.
#
# 1. How bin/which-yatu.sh reads pluginkit. When nothing matches, pluginkit
#    prints "  (no matches)", which is not empty, and the script reported an
#    extension macOS had never heard of as "registered but NOT enabled".
#    README.md and docs/BUILDING.md both point at that script when the toolbar
#    button does not appear, so a wrong answer sends someone to System Settings
#    to enable something that is not listed.
#
# 2. How bin/release.sh titles the release notes. One file is both the working
#    notes and the published release body, and nothing rewrote its heading -- so
#    the tag message and the GitHub release body announced "Unreleased" unless
#    someone retitled it by hand. Nobody sees that until it is published.
#
# pluginkit is stubbed on PATH, so these run without touching the real plug-in
# registry and without needing Yatu installed. Nothing here publishes anything.
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

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [-h|--help]

Run the shell tests. Stubs pluginkit on PATH; changes nothing on this Mac."
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
esac

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

stub_dir="$(mktemp -d)"
trap 'rm -rf "$stub_dir"' EXIT

failures=0
checks=0

# Install a pluginkit stub whose output is whatever the test says it is.
write_stub() {  # $1 = the text pluginkit should print
    printf '%s\n' '#!/bin/bash' 'cat "$(dirname "$0")/pluginkit.out"' > "$stub_dir/pluginkit"
    chmod +x "$stub_dir/pluginkit"
    printf '%s\n' "$1" > "$stub_dir/pluginkit.out"
}

# $1 = case name, $2 = pluginkit output, $3 = text the report must contain,
# $4 = text it must NOT contain (may be empty)
expect() {
    local name=$1 stub_output=$2 wanted=$3 unwanted=${4:-}
    local report
    checks=$((checks + 1))
    write_stub "$stub_output"
    # Only the extension section; the rest reports on whatever is installed.
    report="$(PATH="$stub_dir:$PATH" bin/which-yatu.sh 2>&1 | sed -n '/Finder extension/,/^$/p')"

    if [[ "$report" != *"$wanted"* ]]; then
        print_colored "$COLOR_RED" "FAIL  $name"
        printf '      expected to contain: %s\n' "$wanted"
        printf '      got:\n%s\n' "$report"
        failures=$((failures + 1))
        return
    fi
    if [[ -n "$unwanted" && "$report" == *"$unwanted"* ]]; then
        print_colored "$COLOR_RED" "FAIL  $name"
        printf '      expected NOT to contain: %s\n' "$unwanted"
        printf '      got:\n%s\n' "$report"
        failures=$((failures + 1))
        return
    fi
    print_colored "$COLOR_GREEN" "ok    $name"
}

registered_record() {  # $1 = leading marker: "+" for enabled, " " for not
    printf '%s\n' \
        "$1    com.altmansoftwaredesign.yatu.findersync(1.0.0)" \
        "                Path = /Applications/Yatu.app/Contents/PlugIns/YatuFinderSync.appex" \
        "                UUID = 00000000-0000-0000-0000-000000000000" \
        "                 SDK = com.apple.FinderSync"
}

print_colored "$COLOR_CYAN" "which-yatu.sh: reading pluginkit"

# The bug: not empty, but not a record either.
expect "no matches is reported as not registered" \
    "  (no matches)" "not registered" "registered but"

expect "truly empty output is reported as not registered" \
    "" "not registered" "registered but"

expect "a record with a + is enabled" \
    "$(registered_record '+')" "enabled" "not registered"

expect "a record without a + is registered but not enabled" \
    "$(registered_record ' ')" "registered but NOT enabled" ""

# MARK: - release.sh: titling the release notes

# release.sh runs top to bottom, so retitle_notes is lifted out and exercised on
# its own. Extracted from the real script rather than copied here: a copy would
# keep passing while the shipped version rotted.
retitle_source() {
    sed -n '/^retitle_notes() {/,/^}/p' bin/release.sh
}

# $1 = case name, $2 = heading in, $3 = heading expected out
expect_retitle() {
    local name=$1 heading_in=$2 heading_out=$3
    local notes_dir body_in body_out got
    checks=$((checks + 1))

    notes_dir="$(mktemp -d)"
    printf '%s\n' "$heading_in" "" "First paragraph." "" "- a bullet" > "$notes_dir/NOTES.md"
    body_in="$(tail -n +2 "$notes_dir/NOTES.md")"

    (
        set -euo pipefail
        NOTES_FILE="$notes_dir/NOTES.md"
        version="1.2.3"
        # Both are called by the eval'd function, not from here.
        # shellcheck disable=SC2329
        die() { printf 'error: %s\n' "$*" >&2; exit 1; }
        # shellcheck disable=SC2329
        ok()  { :; }
        eval "$(retitle_source)"
        retitle_notes
    ) || {
        print_colored "$COLOR_RED" "FAIL  $name (retitle_notes exited non-zero)"
        failures=$((failures + 1))
        rm -rf "$notes_dir"
        return
    }

    got="$(head -1 "$notes_dir/NOTES.md")"
    body_out="$(tail -n +2 "$notes_dir/NOTES.md")"
    rm -rf "$notes_dir"

    if [[ "$got" != "$heading_out" ]]; then
        print_colored "$COLOR_RED" "FAIL  $name"
        printf '      expected heading: %s\n      got:              %s\n' "$heading_out" "$got"
        failures=$((failures + 1))
        return
    fi
    # The heading is one line; losing the notes under it would be far worse than
    # mistitling them.
    if [[ "$body_out" != "$body_in" ]]; then
        print_colored "$COLOR_RED" "FAIL  $name (the body was altered)"
        printf '      before:\n%s\n      after:\n%s\n' "$body_in" "$body_out"
        failures=$((failures + 1))
        return
    fi
    print_colored "$COLOR_GREEN" "ok    $name"
}

printf '\n'
print_colored "$COLOR_CYAN" "release.sh: titling the release notes"

expect_retitle "an Unreleased heading becomes the version" "# Unreleased" "# 1.2.3"
expect_retitle "a heading already correct is left alone"   "# 1.2.3"      "# 1.2.3"
expect_retitle "a stale version heading is corrected"      "# 1.0.2"      "# 1.2.3"

# MARK: - ver: the build number is monotonic

# $1 = case name, $2 = command words, $3 = expected "version build" after
expect_ver() {
    local name=$1 command=$2 wanted=$3
    local scratch got
    checks=$((checks + 1))

    scratch="$(mktemp -d)"
    # Starts at build 7 on purpose: a reset-to-1 bug is invisible from build 1,
    # which is how it survived three releases.
    printf '%s\n%s\n' "1.0.2" "7" > "$scratch/VERSION"

    # shellcheck disable=SC2086
    VERSION_FILE="$scratch/VERSION" bin/ver $command >/dev/null 2>&1 || {
        print_colored "$COLOR_RED" "FAIL  $name (bin/ver $command exited non-zero)"
        failures=$((failures + 1)); rm -rf "$scratch"; return
    }
    got="$(tr '\n' ' ' < "$scratch/VERSION" | sed 's/ $//')"
    rm -rf "$scratch"

    if [[ "$got" != "$wanted" ]]; then
        print_colored "$COLOR_RED" "FAIL  $name"
        printf '      expected: %s\n      got:      %s\n' "$wanted" "$got"
        failures=$((failures + 1))
        return
    fi
    print_colored "$COLOR_GREEN" "ok    $name"
}

# The guard and the template it guards against live in the same script and must
# agree on one token. If they drift the guard stops guarding, silently, and the
# next release publishes its own boilerplate as the release body.
checks=$((checks + 1))
marker="$(sed -n 's/^NOTES_MARKER="\(.*\)"$/\1/p' bin/release.sh)"
if [[ -n "$marker" ]] \
    && grep -q "grep -q \"\$NOTES_MARKER\"" bin/release.sh \
    && grep -q "\"<!-- \$NOTES_MARKER:" bin/release.sh; then
    print_colored "$COLOR_GREEN" "ok    the unwritten-notes guard and its template share one marker"
else
    print_colored "$COLOR_RED" "FAIL  the unwritten-notes guard and its template have drifted"
    printf '      marker read from NOTES_MARKER: %s\n' "${marker:-<none>}"
    failures=$((failures + 1))
fi

printf '\n'
print_colored "$COLOR_CYAN" "ver: the build number only goes up"

expect_ver "bump patch carries the build up" "bump patch"  "1.0.3 8"
expect_ver "bump minor carries the build up" "bump minor"  "1.1.0 8"
expect_ver "bump major carries the build up" "bump major"  "2.0.0 8"
expect_ver "set carries the build up"        "set 1.5.0"   "1.5.0 8"
expect_ver "bump build leaves the version"   "bump build"  "1.0.2 8"

printf '\n'
if (( failures )); then
    print_colored "$COLOR_RED" "$failures of $checks checks failed"
    exit 1
fi
print_colored "$COLOR_GREEN" "$checks checks passed"
