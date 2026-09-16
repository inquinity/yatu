#!/bin/bash
#
# Report which build of OpenInTerminal / OpenInTerminal-Lite / OpenInEditor-Lite
# is installed: the upstream release (Homebrew / GitHub) or a local fork build
# produced by build-unsigned.sh. Read-only.
#
# A bundle is identified as:
#   fork      - Info.plist contains OITBuildSource (stamped by build-unsigned.sh)
#   upstream  - signed by the upstream Developer ID team
#   unknown   - anything else (e.g. a fork build made before stamping existed)
#
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

# app name:homebrew cask token
APPS=(
    "OpenInTerminal:openinterminal"
    "OpenInTerminal-Lite:openinterminal-lite"
    "OpenInEditor-Lite:openineditor-lite"
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

report_brew_state() {  # $1 = cask token, $2 = source classification
    local cask_token="$1" source="$2" brew_version
    if ! command -v brew >/dev/null 2>&1; then
        return
    fi
    brew_version="$(brew list --cask --versions "$cask_token" 2>/dev/null | awk '{print $2}' || true)"
    if [[ -z "$brew_version" ]]; then
        printf '  brew:     %s not installed\n' "$cask_token"
        return
    fi
    printf '  brew:     %s %s\n' "$cask_token" "$brew_version"
    if [[ "$source" == "none" ]]; then
        print_colored "$COLOR_RED" "  warning:  brew thinks $cask_token is installed, but the app is missing"
    elif [[ "$source" != "upstream" ]]; then
        print_colored "$COLOR_RED" "  warning:  brew thinks $cask_token is installed, but the app is not the upstream build;
            'brew upgrade/reinstall' will overwrite it"
    fi
}

report_app() {  # $1 = app name, $2 = cask token
    local app_name="$1" cask_token="$2" search_dir app_path found_app=0 source
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
        report_brew_state "$cask_token" "$source"
    done
    if (( ! found_app )); then
        printf '  not installed\n'
        report_brew_state "$cask_token" "none"
    fi
}

# pluginkit shows which copy of the Finder extension macOS will actually load.
report_finder_extension() {
    local extension_path
    print_colored "$COLOR_CYAN" "Finder extension ($FINDER_EXTENSION_ID)"
    while IFS= read -r extension_path; do
        [[ -n "$extension_path" ]] || continue
        printf '  path:     %s\n' "$extension_path"
        print_bundle_source "$extension_path"
    done < <(pluginkit -mAvvv -i "$FINDER_EXTENSION_ID" 2>/dev/null | sed -n 's/^[[:space:]]*Path = //p')
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
esac

for pair in "${APPS[@]}"; do
    report_app "${pair%%:*}" "${pair#*:}"
    printf '\n'
done
report_finder_extension
