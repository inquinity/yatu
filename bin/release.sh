#!/bin/bash
#
# Publish a release: tag, GitHub release, cask, tap.
#
# This does NOT build. Run these first, in order:
#
#   bin/build.sh --release
#   bin/notarize.sh
#   bin/package.sh
#
# Then this verifies what they produced and publishes it. The split is
# deliberate: building is slow and repeatable, publishing is fast and is not.
#
# ## Why this exists
#
# The first two releases were done by hand, and three things went wrong or
# nearly did. Each has a check here, and each check is the reason for a step
# that would otherwise look like ceremony:
#
#   1. The DMG was four commits stale. A release artifact must be built from
#      the commit being tagged, so the app's YatuBuildCommit is compared to
#      HEAD and a mismatch stops everything.
#   2. `gh release create` resolved the repository to the UPSTREAM project and
#      tried to publish there; only --verify-tag refused it. Every gh call here
#      pins --repo explicitly, and origin's URL is checked before anything is
#      pushed. Nothing is ever inferred from remotes.
#   3. The cask's sha256 was nearly taken from the local file. Re-notarizing
#      produces a different file, so the hash is computed from the asset
#      DOWNLOADED BACK from the release, and that download is checked against
#      Gatekeeper before the tap is pushed.
#
# ## Dry run by default
#
# Without --go nothing is created, pushed or uploaded. That is not a courtesy;
# a release is the one thing here that cannot be taken back.
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

# Pinned, never inferred. See reason 2 above.
REPO="inquinity/yatu"
ORIGIN_URL="https://github.com/inquinity/yatu.git"
RELEASE_BRANCH="main"
TEAM_ID="45GJWJVQN2"
APP_NAME="Yatu"
OUTPUT_DIR="dist"
NOTES_FILE="docs/release-notes/UNRELEASED.md"
# The token that means "these notes have not been written". The guard below and
# the template written after each release must agree on it, or the guard stops
# guarding silently; bin/test-scripts.sh holds them together.
NOTES_MARKER="UNWRITTEN"
TAP_CLONE="${TAP_CLONE:-$HOME/dev/projects/homebrew-tap}"
CASK_FILE="Casks/yatu.rb"

go=0

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [--go] [-h|--help]

Verify the built artifacts and publish a release of $REPO.

Build first:
  bin/build.sh --release && bin/notarize.sh && bin/package.sh

Without --go this checks everything and changes nothing.

With --go it will, in order:
  tag and push, create the GitHub release, read the sha256 back from the
  PUBLISHED asset, update the cask, audit it, and push the tap.

Options:
      --go        Actually publish. Everything below is irreversible.
  -h, --help      Show this help

Environment:
  TAP_CLONE   Homebrew tap working copy. Default: \$HOME/dev/projects/homebrew-tap"
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

step() { print_colored "$COLOR_CYAN" "$1"; }
ok()   { print_colored "$COLOR_GREEN" "  $1"; }

# Retitle the notes from "# Unreleased" to "# <version>".
#
# One file is both the working notes and the published release body, so its
# heading is wrong in one of those two roles at any moment. It is archived as
# <version>.md after the release, but nothing rewrote the heading -- so the tag
# message and the GitHub release body both announced "Unreleased" unless someone
# retitled it by hand first. 1.0.2 was retitled by hand.
#
# Called only on the publish path: a dry run changes nothing.
retitle_notes() {
    local heading="# $version"
    [[ "$(head -1 "$NOTES_FILE")" == "$heading" ]] && return 0

    local rewritten
    rewritten="$(mktemp "${TMPDIR:-/tmp}/yatu-notes.XXXXXX")" || die "could not write the notes"
    { printf '%s\n' "$heading"; tail -n +2 "$NOTES_FILE"; } > "$rewritten" \
        || { rm -f "$rewritten"; die "could not retitle $NOTES_FILE"; }
    mv "$rewritten" "$NOTES_FILE" || { rm -f "$rewritten"; die "could not replace $NOTES_FILE"; }
    ok "retitled the notes '$heading'"
}

while (( $# )); do
    case "$1" in
        --go)      go=1 ;;
        -h|--help) usage; exit 0 ;;
        *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v gh >/dev/null || die "gh is required"
command -v brew >/dev/null || die "brew is required"

version="$(bin/ver short)"
tag="v$version"
dmg="$OUTPUT_DIR/$APP_NAME-$version.dmg"
app="$OUTPUT_DIR/$APP_NAME.app"

print_colored "$COLOR_BRIGHTYELLOW" "Releasing $REPO $tag$( ((go)) || printf ' — DRY RUN' )"
printf '\n'

# MARK: - The repository

step "Repository"

actual_origin="$(git remote get-url origin 2>/dev/null || true)"
[[ "$actual_origin" == "$ORIGIN_URL" ]] \
    || die "origin is '$actual_origin', expected '$ORIGIN_URL'.
  Refusing to publish from a clone that is not $REPO."
ok "origin is $REPO"

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "$RELEASE_BRANCH" ]] || die "on branch '$branch', expected '$RELEASE_BRANCH'"

[[ -z "$(git status --porcelain)" ]] || {
    git status --short >&2
    die "the tree is not clean"
}
ok "on $RELEASE_BRANCH, tree clean"

git fetch --quiet origin "$RELEASE_BRANCH" || die "could not fetch origin/$RELEASE_BRANCH"
behind="$(git rev-list --count "HEAD..origin/$RELEASE_BRANCH")"
ahead="$(git rev-list --count "origin/$RELEASE_BRANCH..HEAD")"
(( behind == 0 )) || die "HEAD is $behind commit(s) behind origin/$RELEASE_BRANCH"
(( ahead == 0 )) || die "HEAD is $ahead commit(s) ahead of origin/$RELEASE_BRANCH; push first"
ok "in sync with origin/$RELEASE_BRANCH"

if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
    die "$tag already exists locally. Bump the version with: bin/ver bump patch"
fi
if git ls-remote --exit-code --tags origin "$tag" >/dev/null 2>&1; then
    die "$tag already exists on origin"
fi
ok "$tag is free"

# MARK: - The artifact

step "Artifact"

[[ -d "$app" ]] || die "$app is missing. Run: bin/build.sh --release"
[[ -f "$dmg" ]] || die "$dmg is missing. Run: bin/package.sh"

signature="$(codesign -dvv "$app" 2>&1 || true)"
[[ "$signature" == *"TeamIdentifier=$TEAM_ID"* ]] \
    || die "$app is not signed by team $TEAM_ID"
xcrun stapler validate "$app" >/dev/null 2>&1 \
    || die "$app has no stapled ticket. Run: bin/notarize.sh"
xcrun stapler validate "$dmg" >/dev/null 2>&1 \
    || die "$dmg has no stapled ticket. Run: bin/package.sh"
ok "app and image both signed, notarized, stapled"

# Reason 1: the artifact must come from the commit being tagged.
built_from="$(/usr/libexec/PlistBuddy -c "Print :YatuBuildCommit" \
    "$app/Contents/Info.plist" 2>/dev/null || true)"
head_commit="$(git rev-parse --short HEAD)"
[[ "$built_from" == "$head_commit" ]] \
    || die "the built app is from commit '$built_from' but HEAD is '$head_commit'.
  A release artifact must be built from the commit it is tagged as. Rebuild:
    bin/build.sh --release && bin/notarize.sh && bin/package.sh"
ok "built from $head_commit, which is HEAD"

[[ -s "$NOTES_FILE" ]] \
    || die "$NOTES_FILE is missing or empty. Write the notes before releasing."
# Non-empty was never enough: the template this script writes after each release
# is itself non-empty, so an unwritten file would have been published verbatim as
# the release body. The marker is an HTML comment, invisible once rendered, so it
# cannot be mistaken for notes that someone meant to keep.
# Spelled as an `if` rather than `grep ... && die`: the && form does not trip
# set -e when grep finds nothing, but that is subtle enough to be worth not
# relying on in the script that publishes releases.
if grep -q "$NOTES_MARKER" "$NOTES_FILE"; then
    die "$NOTES_FILE has not been written -- it still carries the $NOTES_MARKER marker.
Write the notes for this release, or recover them from the commits since the last tag."
fi
notes_lines="$(wc -l < "$NOTES_FILE" | tr -d ' ')"
notes_heading="$(head -1 "$NOTES_FILE")"
# The first line becomes the tag message's subject and heads the release body,
# so it has to be a heading before either is written from it.
[[ "$notes_heading" == "# "* ]] \
    || die "$NOTES_FILE must start with a '# ...' heading; it is the release title"
if [[ "$notes_heading" == "# $version" ]]; then
    ok "release notes present ($notes_lines lines), titled '$notes_heading'"
else
    ok "release notes present ($notes_lines lines); '$notes_heading' will be retitled '# $version'"
fi

# MARK: - The tap

step "Tap"

[[ -d "$TAP_CLONE/.git" ]] || die "no tap clone at $TAP_CLONE"
[[ -f "$TAP_CLONE/$CASK_FILE" ]] || die "no $CASK_FILE in $TAP_CLONE"
[[ -z "$(git -C "$TAP_CLONE" status --porcelain)" ]] \
    || die "the tap working copy at $TAP_CLONE is not clean"
ok "tap clean at $TAP_CLONE"

if (( ! go )); then
    printf '\n'
    print_colored "$COLOR_BRIGHTYELLOW" "Dry run — everything checks out. Nothing was published."
    print_colored "$COLOR_YELLOW" "To publish: $(basename "$0") --go"
    exit 0
fi

# MARK: - Publish

printf '\n'
step "Release notes"
retitle_notes

step "Tagging"
git tag -s "$tag" -F "$NOTES_FILE" || die "could not create the tag"
git tag -v "$tag" >/dev/null 2>&1 || die "$tag does not verify; refusing to push an unsigned tag"
git push origin "$tag" || die "could not push $tag"
ok "$tag pushed and signed"

step "GitHub release"
gh release create "$tag" "$dmg" "$OUTPUT_DIR/SHA256SUMS" \
    --repo "$REPO" \
    --title "$APP_NAME $version" \
    --notes-file "$NOTES_FILE" \
    --verify-tag \
    || die "could not create the release"
ok "https://github.com/$REPO/releases/tag/$tag"

# Reason 3: the hash must describe what people actually download.
step "Reading the sha256 back from the published asset"
download_dir="$(mktemp -d "${TMPDIR:-/tmp}/yatu-release.XXXXXX")"
trap 'rm -rf "$download_dir"' EXIT
( cd "$download_dir" && gh release download "$tag" --repo "$REPO" \
    --pattern "$APP_NAME-$version.dmg" ) || die "could not download the published asset"

published="$download_dir/$APP_NAME-$version.dmg"
sha="$(shasum -a 256 "$published" | awk '{print $1}')"
local_sha="$(shasum -a 256 "$dmg" | awk '{print $1}')"
[[ "$sha" == "$local_sha" ]] \
    || die "the published asset does not match the local one:
  published: $sha
  local:     $local_sha"
spctl --assess --type open --context context:primary-signature "$published" >/dev/null 2>&1 \
    || die "the PUBLISHED image is rejected by Gatekeeper; not updating the cask"
ok "$sha — matches, and Gatekeeper accepts the download"

step "Cask"
cask_path="$TAP_CLONE/$CASK_FILE"
/usr/bin/sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" \
                   -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$cask_path" \
    || die "could not update $cask_path"
grep -q "version \"$version\"" "$cask_path" || die "the cask version did not update"
grep -q "sha256 \"$sha\"" "$cask_path" || die "the cask sha256 did not update"

# Audit before pushing: a broken cask reaching the tap is a broken install for
# everyone who runs brew update.
tap_installed="$(brew --repo inquinity/tap 2>/dev/null || true)"
if [[ -n "$tap_installed" && -d "$tap_installed" ]]; then
    cp "$cask_path" "$tap_installed/$CASK_FILE"
    brew style --cask yatu >/dev/null 2>&1 || die "brew style rejects the cask"
    brew audit --cask --online --strict yatu >/dev/null 2>&1 || die "brew audit rejects the cask"
    ok "brew style and brew audit --online both pass"
else
    print_colored "$COLOR_YELLOW" "  tap not installed locally; skipping brew audit"
fi

git -C "$TAP_CLONE" add "$CASK_FILE"
git -C "$TAP_CLONE" commit -q -m "yatu $version" || die "could not commit the cask"
git -C "$TAP_CLONE" push origin HEAD || die "could not push the tap"
ok "tap pushed"

step "Archiving the notes"
mkdir -p "$(dirname "$NOTES_FILE")"
git mv "$NOTES_FILE" "docs/release-notes/$version.md" 2>/dev/null \
    || mv "$NOTES_FILE" "docs/release-notes/$version.md"
printf '%s\n' "# Unreleased" "" \
    "<!-- $NOTES_MARKER: replace everything below the heading with the notes." \
    "     bin/release.sh refuses to publish while this comment is here." \
    "     Write notes as each change lands, not at release time -- see CLAUDE.md. -->" \
    > "$NOTES_FILE"
git add -A docs/release-notes
git commit -q -m "docs: archive the $version release notes" || true
git push origin "$RELEASE_BRANCH" || die "could not push the notes rotation"
ok "notes archived as docs/release-notes/$version.md"

printf '\n'
print_colored "$COLOR_GREEN" "Released $APP_NAME $version."
print_colored "$COLOR_YELLOW" "  https://github.com/$REPO/releases/tag/$tag
  brew update && brew upgrade --cask yatu"
