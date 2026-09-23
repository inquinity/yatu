#!/bin/bash
#
# Report what is installed: which build of Yatu, whether its Finder extension is
# registered and enabled, and whether any of the OpenInTerminal apps Yatu
# replaces are still present. Read-only.
#
# A bundle is identified as:
#   release   - Developer ID signed by Altman Software Design (team 45GJWJVQN2)
#   local     - built by bin/build.sh (ad-hoc signed, carries YatuBuildCommit)
#   unknown   - anything else
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

TEAM_ID="45GJWJVQN2"
APP_NAME="Yatu"
CASK_TOKEN="yatu"
EXTENSION_ID="com.altmansoftwaredesign.yatu.findersync"

# Apps Yatu replaces. Left installed they are harmless, but they put a second,
# near-identical button in the toolbar; the cask's zap does not remove them.
SUPERSEDED=("OpenInTerminal" "OpenInTerminal-Lite" "OpenInEditor-Lite")
SEARCH_DIRS=("/Applications" "$HOME/Applications")

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [-h|--help]

Show which build of Yatu is installed, whether its Finder extension is
registered and enabled, and whether any superseded OpenInTerminal app is
still present."
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

find_app() {  # $1 = app name; prints the first matching bundle path, if any
    local search_dir
    for search_dir in "${SEARCH_DIRS[@]}"; do
        [[ -d "$search_dir/$1.app" ]] && { printf '%s' "$search_dir/$1.app"; return 0; }
    done
    # Not found is an ordinary outcome, not an error: callers run under set -e
    # and assign this through a command substitution.
    return 0
}

print_bundle_source() {  # $1 = bundle path
    local bundle_path="$1"
    if [[ "$(read_team_id "$bundle_path")" == "$TEAM_ID" ]] \
        && codesign -dv "$bundle_path" 2>&1 | grep -q 'Authority=Developer ID Application'; then
        print_colored "$COLOR_GREEN" "  source:   release build, Developer ID signed"
    elif [[ -n "$(read_plist_key "$bundle_path" YatuBuildCommit)" ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "  source:   local build ($(read_plist_key "$bundle_path" YatuBuildCommit), built $(read_plist_key "$bundle_path" YatuBuildDate))"
    else
        print_colored "$COLOR_RED" "  source:   unknown (neither Developer ID signed nor stamped by bin/build.sh)"
    fi
}

report_brew_state() {  # $1 = source classification (installed / none)
    local cask_version
    command -v brew >/dev/null 2>&1 || return 0
    cask_version="$(brew list --cask --versions "$CASK_TOKEN" 2>/dev/null | awk '{print $2}' || true)"
    if [[ -z "$cask_version" ]]; then
        printf '  brew:     not installed via brew\n'
        return
    fi
    printf '  brew:     %s %s (inquinity/tap)\n' "$CASK_TOKEN" "$cask_version"
    [[ "$1" == "none" ]] && print_colored "$COLOR_RED" "  warning:  brew lists the cask as installed, but the app is missing"
    return 0
}

report_yatu() {
    local app_path
    print_colored "$COLOR_CYAN" "$APP_NAME"
    app_path="$(find_app "$APP_NAME")"
    if [[ -z "$app_path" ]]; then
        printf '  not installed\n'
        report_brew_state none
        return
    fi
    printf '  path:     %s\n' "$app_path"
    printf '  version:  %s (build %s)\n' \
        "$(read_plist_key "$app_path" CFBundleShortVersionString)" \
        "$(read_plist_key "$app_path" CFBundleVersion)"
    printf '  team:     %s\n' "$(read_team_id "$app_path")"
    print_bundle_source "$app_path"
    report_brew_state installed
}

# pluginkit marks an enabled plug-in with '+' in the first column. Registered
# but not enabled is the state that makes the button absent from Finder's
# customize palette, which is the usual reason Yatu "does not appear".
report_finder_extension() {
    local record path
    print_colored "$COLOR_CYAN" "Finder extension ($EXTENSION_ID)"
    record="$(pluginkit -mAvvv -i "$EXTENSION_ID" 2>/dev/null || true)"
    # Not "is the output empty": when nothing matches, pluginkit prints
    # "  (no matches)", which is not empty and used to be read as a plug-in
    # with no path. A record is a record only if it names one.
    path="$(printf '%s\n' "$record" | sed -n 's/^[[:space:]]*Path = //p' | head -n1)"
    if [[ -z "$path" ]]; then
        printf '  not registered\n'
        print_colored "$COLOR_YELLOW" "  Register it without launching the app:
    pluginkit -a /Applications/Yatu.app/Contents/PlugIns/YatuFinderSync.appex
  Launching Yatu also registers it, but a plain launch opens a terminal."
        return
    fi
    printf '  path:     %s\n' "$path"
    if printf '%s\n' "$record" | grep -q '^+'; then
        print_colored "$COLOR_GREEN" "  state:    enabled"
    else
        print_colored "$COLOR_BRIGHTYELLOW" "  state:    registered but NOT enabled"
        print_colored "$COLOR_YELLOW" "  Enable it in System Settings > General > Login Items & Extensions,
  then add the button with Finder's View > Customize Toolbar."
    fi
}

report_superseded() {
    local app_name app_path found=0
    print_colored "$COLOR_CYAN" "Superseded apps"
    for app_name in "${SUPERSEDED[@]}"; do
        app_path="$(find_app "$app_name")"
        [[ -n "$app_path" ]] || continue
        found=1
        printf '  %s %s\n' "$app_name" "$(read_plist_key "$app_path" CFBundleShortVersionString)"
        printf '            %s\n' "$app_path"
    done
    (( found )) || printf '  none installed\n'
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
esac

report_yatu
printf '\n'
report_finder_extension
printf '\n'
report_superseded
