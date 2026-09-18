#!/bin/bash
#
# Build Yatu's app bundles from the Swift package.
#
# There is no Xcode project: SwiftPM produces the executables and this script
# assembles them into .app bundles, substituting Resources/Info.plist.in and
# ad-hoc signing the result so it launches locally.
#
# Developer ID signing, notarization and the release checks live in
# bin/build-signed.sh (M4). This script never signs with a real identity.
#
# Output: .build/app/<App>.app
#
# The full colour palette is declared in every fork-owned script by convention, so
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

OUTPUT_DIR=".build/app"
PLIST_TEMPLATE="Resources/Info.plist.in"
ENTITLEMENTS="Resources/Yatu.entitlements"
ICON_FILE="Resources/AppIcon.icns"
LICENSE_FILE="LICENSE"
COPYRIGHT="© 2026 Altman Software Design, LLC — portions © 2019 Jianing Wang (MIT)"

# The OpenInTerminal-Lite version this build is based on, for the settings
# window footer and the release notes.
UPSTREAM_VERSION="1.2.8"

BUILD_CONFIGURATION="release"
UNIVERSAL=true
DRY_RUN=false
OPEN_AFTER_BUILD=false
requested_roles=()

# role:executable:app name:usage description
ROLE_DEFINITIONS=(
    "terminal:YatuTerminal:Yatu:Yatu asks Finder which folder you are looking at, so it can open your chosen terminal there."
    "editor:YatuEditor:Yatu Edit:Yatu Edit asks Finder which items you have selected, so it can open them in your chosen editor."
)

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [role ...] [options]

Roles:
  terminal          Yatu.app (ships in 1.0)
  editor            Yatu Edit.app (built and tested, not shipped in 1.0)
  (none)            Build both

Options:
  -d, --debug       Build the debug configuration instead of release
      --native      Build for this Mac only, skipping the universal binary
  -o, --open        Reveal the output directory in Finder when done
  -n, --dry-run     Show what would be built without building it
  -h, --help        Show this help

The bundles are ad-hoc signed and are not distributable; bin/build-signed.sh
does Developer ID signing and notarization."
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
    [[ -f "$LICENSE_FILE" ]] || die "missing $LICENSE_FILE (the MIT licence must ship in the bundle)"

    if [[ ! -f "$ICON_FILE" ]]; then
        print_colored "$COLOR_YELLOW" "note: $ICON_FILE is missing; generating a placeholder"
        [[ "$DRY_RUN" == true ]] || bin/make-icon.swift "$ICON_FILE"
    fi
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
    local version build_number minimum_macos build_commit build_date

    version="$(bin/ver short)"
    build_number="$(bin/ver build)"
    minimum_macos="$(sed -n 's/.*\.macOS(\.v\([0-9]*\)).*/\1/p' Package.swift | head -1).0"
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
    MIN_MACOS="$minimum_macos" \
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
' "$PLIST_TEMPLATE" "$destination"

    plutil -lint "$destination" >/dev/null || die "generated $destination is not a valid plist"
}

assemble_bundle() {
    local role=$1
    local executable app_name bundle_id usage_description bundle_path binary_path

    executable="$(role_field "$role" 2)"
    app_name="$(role_field "$role" 3)"
    usage_description="$(role_field "$role" 4)"
    case "$role" in
        terminal) bundle_id="com.altmansoftwaredesign.yatu" ;;
        editor)   bundle_id="com.altmansoftwaredesign.yatu.editor" ;;
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
    # shipped bundle. The dSYM stays out of the bundle, in .build.
    strip -x "$bundle_path/Contents/MacOS/$executable"

    install -m 644 "$ICON_FILE" "$bundle_path/Contents/Resources/AppIcon.icns"
    # The MIT licence requires the notice to travel with the binary.
    install -m 644 "$LICENSE_FILE" "$bundle_path/Contents/Resources/LICENSE"
    printf 'APPL????' > "$bundle_path/Contents/PkgInfo"

    write_info_plist "$bundle_path/Contents/Info.plist" \
        "$executable" "$app_name" "$bundle_id" "$usage_description"

    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$bundle_path" 2>/dev/null \
        || die "ad-hoc signing failed for $bundle_path"
    codesign --verify --strict "$bundle_path" || die "$bundle_path failed verification"

    print_colored "$COLOR_GREEN" "  $bundle_path"
    print_colored "$COLOR_YELLOW" "    $bundle_id — $(bin/ver)"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -d|--debug)   BUILD_CONFIGURATION="debug"; shift ;;
        --native)     UNIVERSAL=false; shift ;;
        -o|--open)    OPEN_AFTER_BUILD=true; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -*)           die "unknown option: $1 (try --help)" ;;
        terminal|editor) requested_roles+=("$1"); shift ;;
        *)            die "unknown role '$1' (expected terminal or editor)" ;;
    esac
done

# No roles named means both.
if [[ ${#requested_roles[@]} -eq 0 ]]; then
    requested_roles=(terminal editor)
fi

validate_environment
build_executables

[[ "$DRY_RUN" == true ]] || rm -rf "$OUTPUT_DIR"
[[ "$DRY_RUN" == true ]] || mkdir -p "$OUTPUT_DIR"

print_colored "$COLOR_CYAN" "Assembling"
for role in "${requested_roles[@]}"; do
    assemble_bundle "$role"
done

if [[ "$DRY_RUN" == false ]]; then
    print_colored "$COLOR_GREEN" "
Done. These bundles are ad-hoc signed: they run on this Mac only."
    [[ "$OPEN_AFTER_BUILD" == false ]] || open "$OUTPUT_DIR"
fi
