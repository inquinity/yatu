#!/bin/bash
#
# Report which build of OpenInTerminal / OpenInTerminal-Lite / OpenInEditor-Lite
# (and, once it ships, Yatu)
# is installed: the upstream release (Homebrew / GitHub) or a local fork build
# produced by build-unsigned.sh. Read-only.
#
# A bundle is identified as:
#   fork      - Info.plist contains OITBuildSource (stamped by build-unsigned.sh)
#   upstream  - signed by the upstream Developer ID team
#   unknown   - anything else (e.g. a fork build made before stamping existed)
#
# The full colour palette is declared in every fork-owned script by convention, so
# the set is identical everywhere; not every script uses every colour.
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

UPSTREAM_TEAM_ID="C8VX3ZLX5U"
FINDER_EXTENSION_ID="wang.jianing.app.OpenInTerminal.OpenInTerminalFinderExtension"

# app name:official cask token:fork (inquinity/tap) cask token
APPS=(
    "OpenInTerminal:openinterminal:"
    "OpenInTerminal-Lite:openinterminal-lite:openinterminal-lite-inquinity"
    "OpenInEditor-Lite:openineditor-lite:"
)
SEARCH_DIRS=("/Applications" "$HOME/Applications")

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [-h|--help]

Show whether the installed OpenInTerminal apps are upstream releases or
local fork builds, along with version, signing team, Homebrew state, and the
registered Finder extension."
}

# Print a key from a bundle's Info.plist, or an empty string if absent.
read_plist_key() {  # $1 = bundle path, $2 = key
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

read_team_id() {  # $1 = bundle path
    local team_id
    team_id="$(codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    printf '%s' "${team_id:-none}"
}

# Echo fork / upstream / unknown for a bundle.
classify_bundle() {  # $1 = bundle path
    local bundle_path="$1"
    if [[ -n "$(read_plist_key "$bundle_path" OITBuildSource)" ]]; then
        printf 'fork'
    elif [[ "$(read_team_id "$bundle_path")" == "$UPSTREAM_TEAM_ID" ]]; then
        printf 'upstream'
    else
        printf 'unknown'
    fi
}

print_bundle_source() {  # $1 = bundle path
    local bundle_path="$1" source
    source="$(classify_bundle "$bundle_path")"
    case "$source" in
        fork)
            print_colored "$COLOR_BRIGHTYELLOW" "  source:   FORK ($(read_plist_key "$bundle_path" OITBuildSource)@$(read_plist_key "$bundle_path" OITBuildCommit), built $(read_plist_key "$bundle_path" OITBuildDate))" ;;
        upstream)
            print_colored "$COLOR_GREEN" "  source:   upstream release" ;;
        *)
            print_colored "$COLOR_RED" "  source:   unknown (not upstream-signed, no fork stamp; likely an older local build)" ;;
    esac
}

cask_version() {  # $1 = cask token; prints the installed version, or nothing
    [[ -n "$1" ]] || return 0
    brew list --cask --versions "$1" 2>/dev/null | awk '{print $2}' || true
}

# $1 = official cask token, $2 = fork cask token (may be empty),
# $3 = source classification (fork / upstream / unknown / none)
report_brew_state() {
    local official_token="$1" fork_token="$2" source="$3" official_version fork_version
    if ! command -v brew >/dev/null 2>&1; then
        return
    fi
    official_version="$(cask_version "$official_token")"
    fork_version="$(cask_version "$fork_token")"
    if [[ -z "$official_version" && -z "$fork_version" ]]; then
        printf '  brew:     not installed via brew\n'
        return
    fi
    if [[ -n "$fork_version" ]]; then
        printf '  brew:     %s %s (inquinity/tap)\n' "$fork_token" "$fork_version"
    fi
    if [[ -n "$official_version" ]]; then
        printf '  brew:     %s %s\n' "$official_token" "$official_version"
    fi
    if [[ "$source" == "none" ]]; then
        print_colored "$COLOR_RED" "  warning:  brew lists this app as installed, but the app is missing"
    elif [[ -n "$official_version" && "$source" != "upstream" ]]; then
        print_colored "$COLOR_RED" "  warning:  brew thinks $official_token is installed, but the app is not the upstream build;
            'brew upgrade/reinstall' will overwrite it"
    elif [[ -n "$fork_version" && "$source" != "fork" ]]; then
        print_colored "$COLOR_RED" "  warning:  brew thinks $fork_token is installed, but the app is not a fork build"
    fi
}

report_app() {  # $1 = app name, $2 = official cask token, $3 = fork cask token
    local app_name="$1" official_token="$2" fork_token="$3" search_dir app_path found_app=0 source
    print_colored "$COLOR_CYAN" "$app_name"
    for search_dir in "${SEARCH_DIRS[@]}"; do
        app_path="$search_dir/$app_name.app"
        [[ -d "$app_path" ]] || continue
        found_app=1
        source="$(classify_bundle "$app_path")"
        printf '  path:     %s\n' "$app_path"
        printf '  version:  %s (%s)\n' "$(read_plist_key "$app_path" CFBundleShortVersionString)" "$(read_plist_key "$app_path" CFBundleVersion)"
        printf '  team:     %s\n' "$(read_team_id "$app_path")"
        print_bundle_source "$app_path"
        report_brew_state "$official_token" "$fork_token" "$source"
    done
    if (( ! found_app )); then
        printf '  not installed\n'
        report_brew_state "$official_token" "$fork_token" "none"
    fi
}

# pluginkit shows which copy of the Finder extension macOS will actually load.
report_finder_extension() {
    local extension_path found_extension=0
    print_colored "$COLOR_CYAN" "Finder extension ($FINDER_EXTENSION_ID)"
    while IFS= read -r extension_path; do
        [[ -n "$extension_path" ]] || continue
        found_extension=1
        printf '  path:     %s\n' "$extension_path"
        print_bundle_source "$extension_path"
    done < <(pluginkit -mAvvv -i "$FINDER_EXTENSION_ID" 2>/dev/null | sed -n 's/^[[:space:]]*Path = //p')
    if (( ! found_extension )); then
        printf '  not registered\n'
    fi
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
esac

for pair in "${APPS[@]}"; do
    IFS=: read -r app_name official_token fork_token <<< "$pair"
    report_app "$app_name" "$official_token" "$fork_token"
    printf '\n'
done
report_finder_extension
