#!/bin/bash
#
# Tests for the shell in bin/. There is exactly one thing here worth testing --
# how bin/which-yatu.sh reads pluginkit -- and it is here because it got that
# wrong in a way that mattered: when nothing matches, pluginkit prints
# "  (no matches)", which is not empty, and the script reported an extension
# macOS had never heard of as "registered but NOT enabled". README.md and
# docs/BUILDING.md both point at that script when the toolbar button does not
# appear, so a wrong answer there sends someone to System Settings to enable
# something that is not listed.
#
# pluginkit is stubbed on PATH, so these run without touching the real plug-in
# registry and without needing Yatu installed.
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

printf '\n'
if (( failures )); then
    print_colored "$COLOR_RED" "$failures of $checks checks failed"
    exit 1
fi
print_colored "$COLOR_GREEN" "$checks checks passed"
