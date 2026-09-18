#!/bin/bash
#
# Reports whether Ji4n1ng/OpenInTerminal has moved ahead of this fork.
# Read-only: fetches remote metadata and prints counts, never merges.
#
set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}%s${COLOR_RESET}\n" "$message"
}

REMOTE="${REMOTE:-upstream}"
# Upstream's default branch is still master; ours is main.
REMOTE_BRANCH="${REMOTE_BRANCH:-master}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/Ji4n1ng/OpenInTerminal.git}"

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [-h|--help] [-n|--no-fetch]

Fetch upstream metadata and report whether it has new commits, tags or releases.
Read-only: nothing is merged and no local branch is changed.

Environment:
  REMOTE          Remote to inspect. Default: upstream
  REMOTE_BRANCH   Upstream branch to compare against. Default: master
  UPSTREAM_URL    Added as the remote if it is missing."
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

no_fetch=0
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    -n|--no-fetch) no_fetch=1 ;;
    "") ;;
    *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
esac

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v git >/dev/null 2>&1 || die "git is required but was not found"

# Add the upstream remote on first use rather than failing.
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    print_colored "$COLOR_BRIGHTYELLOW" "Adding missing remote '$REMOTE' -> $UPSTREAM_URL"
    git remote add "$REMOTE" "$UPSTREAM_URL"
fi

if (( ! no_fetch )); then
    git fetch --quiet --tags "$REMOTE" || die "could not fetch from '$REMOTE'"
fi

upstream_ref="$REMOTE/$REMOTE_BRANCH"
git rev-parse --verify --quiet "$upstream_ref" >/dev/null || die "no such ref: $upstream_ref"

behind="$(git rev-list --count "HEAD..$upstream_ref")"
ahead="$(git rev-list --count "$upstream_ref..HEAD")"
upstream_head="$(git rev-parse --short "$upstream_ref")"
upstream_date="$(git log -1 --format=%cs "$upstream_ref")"
latest_tag="$(git tag --list --sort=-creatordate --merged "$upstream_ref" | head -n1)"

printf '%s\n' "upstream:  $upstream_ref @ $upstream_head ($upstream_date)"
printf '%s\n' "latest upstream tag: ${latest_tag:-none}"
printf '%s\n' "this fork: $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
printf '%s\n' "ahead: $ahead commit(s)   behind: $behind commit(s)"

if (( behind == 0 )); then
    print_colored "$COLOR_GREEN" "Up to date with $upstream_ref — nothing to merge."
    exit 0
fi

print_colored "$COLOR_BRIGHTYELLOW" "Upstream has $behind new commit(s). Review, then:"
print_colored "$COLOR_YELLOW" "  git merge $upstream_ref     # merge, never rebase; prefix the merge 'Sync:'"
print_colored "$COLOR_YELLOW" "  security-review the incoming diff before building anything"
