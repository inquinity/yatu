#!/bin/bash
#
# Reports whether OpenInTerminal's app catalog has moved since the commit our
# vendored copy records. Read-only: nothing is fetched into this repository and
# no file is changed.
#
# Yatu was a fork until 2026-09-23 and tracked upstream
# with `git merge`. It no longer does. The only upstream code still compiled is
# Sources/YatuUpstream/, and of that only the catalog changes in practice — so
# this compares catalog entries rather than commits.
#
# ## This repository never contacts upstream
#
# The comparison reads the CONTRIBUTION CLONE, which is where the upstream
# remote legitimately lives. Nothing here holds an upstream URL, and no script
# in this repository fetches from one. A tool here that names another project's
# repository is a tool that can act on it by mistake -- not hypothetical:
# `gh release create` resolved to upstream and tried to publish there, and only
# --verify-tag stopped it. Adopting a change is a
# judgement call: upstream's list is one project's opinion, not an authority
# (docs/YATU-PLAN.md section 9.6).
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

# The contribution clone keeps its own upstream remote; prefer it over the
# network so this works offline and reports the upstream commit as well.
UPSTREAM_CLONE="${UPSTREAM_CLONE:-$HOME/dev/oss/openinterminal}"
UPSTREAM_REF="${UPSTREAM_REF:-upstream/master}"
UPSTREAM_PATH="OpenInTerminalCore/SupportedApps.swift"

VENDORED="Sources/YatuUpstream/SupportedApps.swift"

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [-h|--help] [-n|--no-fetch] [-d|--diff]

Compare upstream's app catalog against the copy vendored in $VENDORED
and report which terminals and editors upstream has added or removed.

Options:
  -n, --no-fetch  Do not update the upstream clone before comparing.
  -d, --diff      Print a full unified diff instead of an entry summary.

Environment:
  UPSTREAM_CLONE  Clone with an 'upstream' remote. Default: \$HOME/dev/oss/openinterminal
  UPSTREAM_REF    Ref to compare against. Default: upstream/master

This repository holds no upstream URL and never fetches from one. The
comparison reads the contribution clone, which is where the upstream remote
lives."
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

# Catalog entries only: `case iTerm = "iTerm"` -> `iTerm = "iTerm"`. Comments,
# MARK dividers and the provenance header are all dropped, so a header-only
# change never registers as a catalog change.
catalog_entries() {  # reads a Swift source on stdin
    sed -n 's/^[[:space:]]*case[[:space:]]\{1,\}\([A-Za-z0-9_]*[[:space:]]*=[[:space:]]*".*"\).*/\1/p'
}

no_fetch=0
show_diff=0
while (( $# )); do
    case "$1" in
        -h|--help)     usage; exit 0 ;;
        -n|--no-fetch) no_fetch=1 ;;
        -d|--diff)     show_diff=1 ;;
        *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$VENDORED" ]] || die "$VENDORED is missing"

# The commit the vendored copy was taken at, recorded in its provenance header.
# First match only, without piping into head — see bin/build.sh for why.
recorded_commit="$(sed -n 's/.*as of upstream commit \([0-9a-f]\{7,\}\).*/\1/p' "$VENDORED")"
recorded_commit="${recorded_commit%%$'\n'*}"

upstream_source="$(mktemp)"
trap 'rm -f "$upstream_source"' EXIT

upstream_commit="unknown"
if [[ -d "$UPSTREAM_CLONE/.git" ]]; then
    origin="$UPSTREAM_CLONE ($UPSTREAM_REF)"
    if (( ! no_fetch )); then
        git -C "$UPSTREAM_CLONE" fetch --quiet "${UPSTREAM_REF%%/*}" \
            || print_colored "$COLOR_RED" "warning: could not fetch; comparing against the last fetch"
    fi
    git -C "$UPSTREAM_CLONE" show "$UPSTREAM_REF:$UPSTREAM_PATH" > "$upstream_source" \
        || die "could not read $UPSTREAM_PATH at $UPSTREAM_REF"
    upstream_commit="$(git -C "$UPSTREAM_CLONE" log -1 --format='%h (%cs)' "$UPSTREAM_REF" -- "$UPSTREAM_PATH")"
else
    die "no clone at $UPSTREAM_CLONE.

Upstream contact lives in the contribution clone, not in this repository, so
there is no network fallback here by design. Clone it there and retry, or set
UPSTREAM_CLONE to where it is."
fi

printf 'vendored: %s @ %s\n' "$VENDORED" "${recorded_commit:-no commit recorded}"
printf 'upstream: %s @ %s\n\n' "$origin" "$upstream_commit"

if (( show_diff )); then
    if diff -u "$VENDORED" "$upstream_source"; then
        print_colored "$COLOR_GREEN" "Identical."
    fi
    exit 0
fi

ours="$(catalog_entries < "$VENDORED")"
theirs="$(catalog_entries < "$upstream_source")"

added="$(comm -13 <(printf '%s\n' "$ours" | sort) <(printf '%s\n' "$theirs" | sort))"
removed="$(comm -23 <(printf '%s\n' "$ours" | sort) <(printf '%s\n' "$theirs" | sort))"

if [[ -z "$added" && -z "$removed" ]]; then
    print_colored "$COLOR_GREEN" "Catalog unchanged — $(printf '%s\n' "$ours" | wc -l | tr -d ' ') entries, identical to upstream."
    exit 0
fi

[[ -n "$added" ]] && {
    print_colored "$COLOR_BRIGHTYELLOW" "Upstream has added:"
    print_colored "$COLOR_YELLOW" "$(printf '%s\n' "$added" | sed 's/^/  + /')"
}
[[ -n "$removed" ]] && {
    print_colored "$COLOR_BRIGHTYELLOW" "Upstream has removed (or we carry entries it does not):"
    print_colored "$COLOR_YELLOW" "$(printf '%s\n' "$removed" | sed 's/^/  - /')"
}

printf '\n'
print_colored "$COLOR_YELLOW" "Adopting a change means editing $VENDORED by hand and
updating the commit in its provenance header. Verify the bundle identifier
against the real application before trusting it — upstream's catalog has
shipped stale identifiers."
