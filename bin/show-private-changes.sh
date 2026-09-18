#!/bin/bash
#
# Shows everything this fork changes relative to Ji4n1ng/OpenInTerminal.
# This is the canonical answer to "what have we done to the base project?" --
# see docs/FORK-NOTES.md for why each change exists.
#
# Read-only: never merges, never writes.
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

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [options] [-- <git diff args>]

Show what this fork changes on top of $REMOTE/$REMOTE_BRANCH.

Options:
  -h, --help       Show this help text.
      --stat       Summary (diffstat) instead of the full diff.
      --files      List changed paths only.
      --commits    List the fork's commits instead of a diff.
      --fetch      Fetch the remote first (default: use what is already fetched)."
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

mode="diff"
do_fetch=0
# Bash 3.2 (macOS) treats an empty array as unset under `set -u`, so every
# expansion below uses the ${a[@]+"${a[@]}"} form.
extra_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --stat) mode="stat"; shift ;;
        --files) mode="files"; shift ;;
        --commits) mode="commits"; shift ;;
        --fetch) do_fetch=1; shift ;;
        --) shift; extra_args=("$@"); break ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git remote get-url "$REMOTE" >/dev/null 2>&1 || die "no '$REMOTE' remote; run bin/check-upstream.sh first"
(( do_fetch )) && git fetch --quiet "$REMOTE"

base_ref="$REMOTE/$REMOTE_BRANCH"
git rev-parse --verify --quiet "$base_ref" >/dev/null || die "no such ref: $base_ref (try --fetch)"

# Compare against the merge base so unmerged upstream work is not shown as ours.
merge_base="$(git merge-base HEAD "$base_ref")"
print_colored "$COLOR_BRIGHTYELLOW" "Fork changes: $(git rev-parse --abbrev-ref HEAD) vs $base_ref (merge base $(git rev-parse --short "$merge_base"))"

case "$mode" in
    stat)    git diff --stat "$merge_base..HEAD" ${extra_args[@]+"${extra_args[@]}"} ;;
    files)   git diff --name-status "$merge_base..HEAD" ${extra_args[@]+"${extra_args[@]}"} ;;
    commits) git log --oneline --no-merges "$merge_base..HEAD" ${extra_args[@]+"${extra_args[@]}"} ;;
    diff)    git diff "$merge_base..HEAD" ${extra_args[@]+"${extra_args[@]}"} ;;
esac
