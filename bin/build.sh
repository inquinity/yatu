#!/bin/bash
#
# Build Yatu's app bundles from the Swift package.
#
# There is no Xcode project: SwiftPM produces the executables and this script
# assembles them into .app bundles, substituting Resources/Info.plist.in and
# ad-hoc signing the result so it launches locally.
#
# This script never signs with a real identity. Developer ID signing and
# notarization arrive here in M4; see docs/BUILDING.md.
#
# Output: dist/<App>.app
#
# Deliberately NOT inside .build. That directory is SwiftPM's derived-data
# cache: `swift package clean` empties it, and the CACHEDIR.TAG it contains
# tells backup tools the whole tree is regenerable. Both are true of object
# files and false of a signed, notarized bundle, so the deliverable lives in
# its own directory.
#
# The full colour palette is declared in every script by convention, so
# the set is identical everywhere; not every script uses every colour.
# shellcheck disable=SC2034
set -euo pipefail

# Always operate on the repo, not on the caller's directory: every path below
# is repo-relative, including the output directory this script removes.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

OUTPUT_DIR="dist"
PLIST_TEMPLATE="Resources/Info.plist.in"
ENTITLEMENTS="Resources/Yatu.entitlements"
EXTENSION_PLIST_TEMPLATE="Resources/Extension-Info.plist.in"
EXTENSION_ENTITLEMENTS="Resources/YatuFinderSync.entitlements"
EXTENSION_ASSETS="Resources/YatuFinderSync.xcassets"
# The deployment target lives in Package.swift and is read from there by
# both the Info.plist and actool, so the two can never disagree.
MINIMUM_MACOS="$(sed -n 's/.*\.macOS(\.v\([0-9]*\)).*/\1/p' Package.swift | head -1).0"
EXTENSION_EXECUTABLE="YatuFinderSync"
ICON_FILE="Resources/AppIcon.icns"
LICENSE_FILE="LICENSE"
COPYRIGHT="© 2026 Altman Software Design, LLC — portions © 2019 Jianing Wang (MIT)"

# The OpenInTerminal-Lite version this build is based on, for the settings
# window footer and the release notes.
UPSTREAM_VERSION="1.2.8"

BUILD_CONFIGURATION="release"
# Ad-hoc by default; --release signs with the Developer ID for this team.
RELEASE=false
SIGNING_IDENTITY=""
TEAM_ID="45GJWJVQN2"
# What `codesign -dr -` must amount to for a release build.
#
# This is the requirement codesign itself derives from a Developer ID
# signature, and it is stronger than the obvious hand-written version: besides
# the team's OU it pins the intermediate to Apple's Developer ID CA
# (1.2.840.113635.100.6.2.6) and the leaf to a Developer ID Application
# certificate (1.2.840.113635.100.6.1.13). An earlier draft of this script
# pinned only identifier + anchor + OU, and the assertion below rejected the
# real signature for being MORE specific -- which is the good direction for an
# assertion to fail in.
#
# Pinning the OU rather than a certificate hash means a renewed certificate
# still matches, while another developer's Developer ID does not.
DESIGNATED_REQUIREMENT='identifier "com.altmansoftwaredesign.yatu" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "45GJWJVQN2"' 
UNIVERSAL=true
DRY_RUN=false
OPEN_AFTER_BUILD=false
requested_roles=()

# role:executable:app name:usage description
#
# One row, since 2026-09-23. There used to be a second app, "Yatu Edit", for the
# editor role. It was retired when the Finder extension took over (plan M6a):
# the extension's menu carries Send to editor, so the role is reached without a
# second bundle to sign, notarize, icon and explain. The ROLE concept is alive
# and well in YatuKit -- this table is only about how many *apps* we build.
ROLE_DEFINITIONS=(
    "terminal:YatuTerminal:Yatu:Yatu asks Finder which folder you are looking at, so it can open your chosen terminal there."
)

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [role ...] [options]

Roles:
  terminal          Yatu.app -- the only app, and the default

Options:
  -d, --debug       Build the debug configuration instead of release
      --release     Sign with the Developer ID for team 45GJWJVQN2 and assert
                    the result. Refuses a dirty or untracked tree.
      --native      Build for this Mac only, skipping the universal binary
  -o, --open        Reveal the output directory in Finder when done
  -n, --dry-run     Show what would be built without building it
  -h, --help        Show this help

The bundles are ad-hoc signed and run on this Mac only. Producing a
distributable build needs an Apple Developer account; see docs/BUILDING.md."
}

die() {
    print_colored "$COLOR_RED" "error: $1"
    exit 1
}

# Fail early and specifically rather than part-way through an assembly.
validate_environment() {
    command -v swift >/dev/null || die "swift not found; install the Xcode command line tools"
    command -v codesign >/dev/null || die "codesign not found"

    [[ -f "$PLIST_TEMPLATE" ]] || die "missing $PLIST_TEMPLATE"
    [[ -f "$ENTITLEMENTS" ]] || die "missing $ENTITLEMENTS"
    [[ -f "$EXTENSION_PLIST_TEMPLATE" ]] || die "missing $EXTENSION_PLIST_TEMPLATE"
    [[ -f "$EXTENSION_ENTITLEMENTS" ]] || die "missing $EXTENSION_ENTITLEMENTS"
    [[ -d "$EXTENSION_ASSETS" ]] || die "missing $EXTENSION_ASSETS"
    command -v xcrun >/dev/null || die "xcrun not found; install Xcode"
    xcrun --find actool >/dev/null 2>&1 || die "actool not found; Xcode is required to compile the toolbar symbol"
    [[ -f "$LICENSE_FILE" ]] || die "missing $LICENSE_FILE (the MIT licence must ship in the bundle)"

    if [[ ! -f "$ICON_FILE" ]]; then
        print_colored "$COLOR_YELLOW" "note: $ICON_FILE is missing; generating a placeholder"
        [[ "$DRY_RUN" == true ]] || bin/make-icon.swift "$ICON_FILE"
    fi
}

# The Developer ID to sign with, chosen BY TEAM.
#
# Never "the first identity found" (finding S3). This Mac carries three signing
# identities, and picking by position would sign Yatu with an iPhone Developer
# certificate the day the keychain order changes. Exactly one match is required:
# two would mean the choice is ambiguous, and guessing is how the wrong one
# ships.
signing_identity() {
    local matches
    matches="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | grep "($TEAM_ID)")"
    [[ -n "$matches" ]] \
        || die "no Developer ID Application identity for team $TEAM_ID in the keychain"
    [[ "$(printf '%s\n' "$matches" | wc -l | tr -d ' ')" == "1" ]] \
        || die "more than one Developer ID Application identity for team $TEAM_ID; refusing to guess"
    printf '%s' "$matches" | sed 's/.*"\(.*\)"/\1/'
}

# Sign one bundle, ad-hoc or for release.
sign_bundle() {  # $1 = path, $2 = entitlements
    local path=$1 entitlements=$2
    if [[ "$RELEASE" == true ]]; then
        # --options runtime is the hardened runtime, which notarization
        # requires. --timestamp means the signature outlives the certificate.
        codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$entitlements" \
                 --options runtime --timestamp "$path" \
            || die "signing failed for $path"
    else
        codesign --force --sign - --entitlements "$entitlements" "$path" 2>/dev/null \
            || die "ad-hoc signing failed for $path"
    fi
}

# Everything a release signature has to be, asserted rather than hoped for.
# Each of these was a gap in the build this replaces (finding S3).
assert_release_signature() {  # $1 = bundle path
    local path=$1 requirement runtime

    codesign --verify --strict --deep "$path" \
        || die "$path failed strict deep verification"

    # Compared with codesign's `/* exists */` comments and repeated spaces
    # removed, so the check is about the requirement and not its formatting.
    normalise_requirement() {
        sed -e 's|/\*[^*]*\*/||g' -e 's/  */ /g' -e 's/ $//'
    }
    requirement="$(codesign -d -r- "$path" 2>&1 | sed -n 's/^designated => //p' | normalise_requirement)"
    expected="$(printf '%s' "$DESIGNATED_REQUIREMENT" | normalise_requirement)"
    [[ "$requirement" == "$expected" ]] \
        || die "designated requirement is not what we pin:
  expected: $expected
  got:      $requirement"

    runtime="$(codesign -d -v "$path" 2>&1 | sed -n 's/^CodeDirectory.*flags=\([^ ]*\).*/\1/p')"
    [[ "$runtime" == *"runtime"* ]] \
        || die "hardened runtime is not enabled on $path (flags: $runtime)"

    # A debuggable build must never reach anyone: get-task-allow lets any
    # process attach to it.
    if codesign -d --entitlements :- "$path" 2>/dev/null | grep -q "get-task-allow"; then
        die "$path carries get-task-allow"
    fi

    print_colored "$COLOR_GREEN" "    signature verified: strict, deep, hardened, team $TEAM_ID"
}

# Look up one field of a role definition: role_field <role> <1-based index>
role_field() {
    local wanted_role=$1 field_index=$2 definition
    for definition in "${ROLE_DEFINITIONS[@]}"; do
        if [[ "${definition%%:*}" == "$wanted_role" ]]; then
            printf '%s\n' "$definition" | cut -d: -f"$field_index"
            return 0
        fi
    done
    die "unknown role '$wanted_role' (expected terminal or editor)"
}

build_executables() {
    local -a swift_arguments=(build -c "$BUILD_CONFIGURATION")
    if [[ "$UNIVERSAL" == true ]]; then
        swift_arguments+=(--arch arm64 --arch x86_64)
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "would run: swift ${swift_arguments[*]}"
        return
    fi

    print_colored "$COLOR_CYAN" "Building (${BUILD_CONFIGURATION}$([[ "$UNIVERSAL" == true ]] && printf ', universal'))"
    swift "${swift_arguments[@]}"
}

# Where SwiftPM put the products; --arch changes the layout, so ask rather than guess.
binary_directory() {
    local -a swift_arguments=(build -c "$BUILD_CONFIGURATION" --show-bin-path)
    if [[ "$UNIVERSAL" == true ]]; then
        swift_arguments+=(--arch arm64 --arch x86_64)
    fi
    swift "${swift_arguments[@]}"
}

# Substitute every @TOKEN@ in the plist template. Values are passed through a
# temporary file rather than sed expressions so that punctuation in the
# copyright and usage strings needs no escaping.
write_info_plist() {
    local destination=$1 executable=$2 app_name=$3 bundle_id=$4 usage_description=$5
    local template=${6:-$PLIST_TEMPLATE}
    local version build_number build_commit build_date

    version="$(bin/ver short)"
    build_number="$(bin/ver build)"
    build_commit="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
    # Build date comes from the commit, not the clock, so a rebuild of the same
    # commit produces the same plist (S-series finding in the build review).
    build_date="$(git show -s --format=%cI HEAD 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

    if git rev-parse --git-dir >/dev/null 2>&1 && ! git diff --quiet HEAD 2>/dev/null; then
        build_commit="$build_commit-dirty"
    fi

    APP_NAME="$app_name" \
    EXECUTABLE="$executable" \
    BUNDLE_ID="$bundle_id" \
    VERSION="$version" \
    BUILD="$build_number" \
    MIN_MACOS="$MINIMUM_MACOS" \
    COPYRIGHT="$COPYRIGHT" \
    USAGE_DESCRIPTION="$usage_description" \
    BUILD_COMMIT="$build_commit" \
    BUILD_DATE="$build_date" \
    UPSTREAM_VERSION="$UPSTREAM_VERSION" \
    python3 -c '
import os, re, sys
template = open(sys.argv[1], encoding="utf-8").read()
def replace(match):
    name = match.group(1)
    if name not in os.environ:
        sys.exit("unsubstituted token in template: @%s@" % name)
    return (os.environ[name]
            .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
open(sys.argv[2], "w", encoding="utf-8").write(re.sub(r"@([A-Z_]+)@", replace, template))
' "$template" "$destination"

    plutil -lint "$destination" >/dev/null || die "generated $destination is not a valid plist"
}

# Build the .appex inside an already-assembled .app. The extension is
# sandboxed while the app is not — the pair BetterZip ships, and what keeps the
# extension able to report and hand off but nothing else.
assemble_extension() {
    local bundle_path=$1 app_bundle_id=$2 app_name=$3
    local extension_path="$bundle_path/Contents/PlugIns/$EXTENSION_EXECUTABLE.appex"
    local binary_path
    binary_path="$(binary_directory)/$EXTENSION_EXECUTABLE"

    [[ -f "$binary_path" ]] || die "built extension not found: $binary_path"

    mkdir -p "$extension_path/Contents/MacOS"
    install -m 755 "$binary_path" "$extension_path/Contents/MacOS/$EXTENSION_EXECUTABLE"
    strip -x "$extension_path/Contents/MacOS/$EXTENSION_EXECUTABLE"

    write_info_plist "$extension_path/Contents/Info.plist" \
        "$EXTENSION_EXECUTABLE" "$app_name" "$app_bundle_id.findersync" "" \
        "$EXTENSION_PLIST_TEMPLATE"

    # The toolbar symbol is a custom SF Symbol, and a sandboxed extension can
    # only read its own bundle -- so the catalog is compiled into the .appex,
    # not into the app. This must happen BEFORE the signature below: the
    # extension is sealed leaf-first, and anything added afterwards invalidates
    # it. `codesign --verify --strict` on the app would catch that, but only
    # after a wasted cycle.
    mkdir -p "$extension_path/Contents/Resources"
    if ! xcrun actool "$EXTENSION_ASSETS" \
            --compile "$extension_path/Contents/Resources" \
            --platform macosx \
            --minimum-deployment-target "$MINIMUM_MACOS" \
            --output-partial-info-plist "$(mktemp -t yatu-actool)" > /dev/null 2>&1; then
        die "actool failed to compile $EXTENSION_ASSETS"
    fi
    [[ -f "$extension_path/Contents/Resources/Assets.car" ]] \
        || die "actool produced no Assets.car"

    sign_bundle "$extension_path" "$EXTENSION_ENTITLEMENTS"

    # The property that matters, asserted rather than assumed: the extension is
    # sandboxed. If this ever stops being true the extension has become able to
    # do things this design says it cannot.
    codesign -d --entitlements :- "$extension_path" 2>/dev/null | grep -q 'app-sandbox' \
        || die "extension is not sandboxed — refusing to ship it"

    print_colored "$COLOR_YELLOW" "    + $EXTENSION_EXECUTABLE.appex (sandboxed)"
}

assemble_bundle() {
    local role=$1
    local executable app_name bundle_id usage_description bundle_path binary_path

    executable="$(role_field "$role" 2)"
    app_name="$(role_field "$role" 3)"
    usage_description="$(role_field "$role" 4)"
    case "$role" in
        terminal) bundle_id="com.altmansoftwaredesign.yatu" ;;
        *)        die "no bundle id for role '$role'" ;;
    esac

    bundle_path="$OUTPUT_DIR/$app_name.app"

    if [[ "$DRY_RUN" == true ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "would assemble $bundle_path ($bundle_id)"
        return
    fi

    binary_path="$(binary_directory)/$executable"
    [[ -f "$binary_path" ]] || die "built executable not found: $binary_path"

    rm -rf "$bundle_path"
    mkdir -p "$bundle_path/Contents/MacOS" "$bundle_path/Contents/Resources"

    install -m 755 "$binary_path" "$bundle_path/Contents/MacOS/$executable"
    # Finding L4: an unstripped binary carries local build paths into the
    # shipped bundle. The dSYM stays out of the bundle, in SwiftPM's .build.
    strip -x "$bundle_path/Contents/MacOS/$executable"

    install -m 644 "$ICON_FILE" "$bundle_path/Contents/Resources/AppIcon.icns"
    # The MIT licence requires the notice to travel with the binary.
    install -m 644 "$LICENSE_FILE" "$bundle_path/Contents/Resources/LICENSE"
    printf 'APPL????' > "$bundle_path/Contents/PkgInfo"

    write_info_plist "$bundle_path/Contents/Info.plist" \
        "$executable" "$app_name" "$bundle_id" "$usage_description"

    # The Finder toolbar button. Both roles are reached through it: a click
    # opens the terminal, and its menu carries Send to editor.
    assemble_extension "$bundle_path" "$bundle_id" "$app_name"

    # Leaf first: the extension is sealed before the bundle that contains it,
    # or the app's signature covers code that changes afterwards.
    sign_bundle "$bundle_path" "$ENTITLEMENTS"
    codesign --verify --strict "$bundle_path" || die "$bundle_path failed verification"
    [[ "$RELEASE" != true ]] || assert_release_signature "$bundle_path"

    print_colored "$COLOR_GREEN" "  $bundle_path"
    print_colored "$COLOR_YELLOW" "    $bundle_id — $(bin/ver)"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -d|--debug)   BUILD_CONFIGURATION="debug"; shift ;;
        --release)    RELEASE=true; shift ;;
        --native)     UNIVERSAL=false; shift ;;
        -o|--open)    OPEN_AFTER_BUILD=true; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -*)           die "unknown option: $1 (try --help)" ;;
        terminal)     requested_roles+=("$1"); shift ;;
        *)            die "unknown role '$1' (expected terminal)" ;;
    esac
done

# No role named means all of them, which is currently one.
if [[ ${#requested_roles[@]} -eq 0 ]]; then
    requested_roles=(terminal)
fi

# A release must be reproducible from what is committed. Signing a tree with
# uncommitted or untracked files produces a binary nobody can rebuild, and the
# build this replaces did exactly that (finding S3).
if [[ "$RELEASE" == true ]]; then
    [[ "$BUILD_CONFIGURATION" == "release" ]] \
        || die "--release and --debug are contradictory"
    git rev-parse --git-dir >/dev/null 2>&1 || die "--release needs a git repository"
    if [[ -n "$(git status --porcelain)" ]]; then
        print_colored "$COLOR_RED" "The tree is not clean:"
        git status --short >&2
        die "--release refuses a dirty or untracked tree"
    fi
    SIGNING_IDENTITY="$(signing_identity)"
    print_colored "$COLOR_BRIGHTYELLOW" "Release build — signing as: $SIGNING_IDENTITY"
fi

validate_environment
build_executables

# This deletes a directory, so it checks rather than trusts. The script has
# already cd'd to the repository root, and OUTPUT_DIR is relative to it -- an
# absolute or climbing path here would delete something outside the repo.
[[ -n "$OUTPUT_DIR" ]] || die "OUTPUT_DIR is empty"
case "$OUTPUT_DIR" in
    /*|*..*) die "OUTPUT_DIR must be a path inside the repository, got '$OUTPUT_DIR'" ;;
esac

if [[ "$DRY_RUN" != true ]]; then
    rm -rf "${PWD:?}/$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

print_colored "$COLOR_CYAN" "Assembling"
for role in "${requested_roles[@]}"; do
    assemble_bundle "$role"
done

if [[ "$DRY_RUN" == false ]]; then
    print_colored "$COLOR_GREEN" "
Done. These bundles are ad-hoc signed: they run on this Mac only."
    [[ "$OPEN_AFTER_BUILD" == false ]] || open "$OUTPUT_DIR"
fi
