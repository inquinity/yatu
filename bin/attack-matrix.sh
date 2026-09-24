#!/bin/bash
#
# Fire hostile input at Yatu and check that nothing executes.
#
# This automates the matrix from the dynamic security review (security-review/,
# git-excluded). The property it defends is the one finding F1 is about: Yatu
# takes paths from Finder and hands them to another application, and a path is
# attacker-controlled data — anyone who can name a file can choose part of it.
# The review found no injection path in the shipped build. That is a property to
# keep, not a one-off result, so it is re-run before every release.
#
# ## How it detects a failure
#
# Every hostile name embeds a command that creates a CANARY file. Nothing here
# inspects escaping or reasons about quoting: either a canary exists afterwards,
# in which case something interpreted a filename, or it does not. The same
# applies to the .command file, the executable script and the canary .app —
# each writes a canary if it is ever run rather than opened.
#
# ## What it touches
#
#   * a scratch directory under $TMPDIR, removed afterwards unless --keep
#   * the Yatu preference domain, backed up first and restored on exit even if
#     the script is interrupted
#
# It does not touch anything else, and it never needs sudo.
#
# ## Two modes
#
# By default it fires only the cases that must be REFUSED, so nothing launches
# and no windows open. `--live` adds the cases that legitimately launch — which
# is the half that actually proves the property, and which will open a terminal
# window per case. Use it before a release; expect the windows.
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

BUNDLE_ID="com.altmansoftwaredesign.yatu"
SCHEME="yatu"

live=0
keep=0
dry_run=0
assume_yes=0

usage() {
    print_colored "$COLOR_YELLOW" "Usage: $(basename "$0") [options]

Fire hostile filenames and malformed yatu:// URLs at Yatu, and check that
nothing was executed. Scratch only; your Yatu preference is backed up and
restored.

Options:
      --live      Also fire the cases that legitimately launch. This is the
                  half that proves the property, and it WILL open a terminal
                  window per case.
  -y, --yes       Do not ask before --live.
      --keep      Leave the scratch directory in place for inspection.
  -n, --dry-run   List what would be fired, and touch nothing.
  -h, --help      Show this help"
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

while (( $# )); do
    case "$1" in
        --live)       live=1 ;;
        -y|--yes)     assume_yes=1 ;;
        --keep)       keep=1 ;;
        -n|--dry-run) dry_run=1 ;;
        -h|--help)    usage; exit 0 ;;
        *) print_colored "$COLOR_RED" "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v open >/dev/null || die "open(1) is required"

scratch=""
preferences_backup=""
run_marker=""""

# Restore the preference and clear up even if this is interrupted: leaving
# someone's default terminal changed by a test would be its own small bug.
cleanup() {
    if [[ -n "$preferences_backup" && -f "$preferences_backup" ]]; then
        defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
        if [[ -s "$preferences_backup" ]]; then
            defaults import "$BUNDLE_ID" "$preferences_backup" >/dev/null 2>&1 \
                || print_colored "$COLOR_RED" "warning: could not restore $BUNDLE_ID preferences from $preferences_backup"
        fi
        rm -f "$preferences_backup"
    fi
    [[ -n "$run_marker" ]] && rm -f "$run_marker"
    if [[ -n "$scratch" && -d "$scratch" ]]; then
        if (( keep )); then
            print_colored "$COLOR_YELLOW" "scratch kept: $scratch"
        else
            chmod -R u+w "$scratch" 2>/dev/null || true
            rm -rf "$scratch"
        fi
    fi
}
trap cleanup EXIT INT TERM

# MARK: - The corpus

canary_dir=""

# Names whose whole point is to be misread. Each embeds a command writing a
# canary; the marker is the canary's basename.
hostile_names() {
    printf '%s\n' \
        'plain' \
        'with space' \
        "with'single" \
        'with"double' \
        '$(touch CANARY-subst)' \
        '`touch CANARY-backtick`' \
        ';touch CANARY-semicolon' \
        '&&touch CANARY-and' \
        '|touch CANARY-pipe' \
        '$HOME' \
        '--leading-dash' \
        '..dots' \
        'tab	inside' \
        'emoji 🙂 name'
}

build_corpus() {
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/yatu-attack.XXXXXX")"
    canary_dir="$scratch/canaries"
    mkdir -p "$canary_dir"

    local name
    while IFS= read -r name; do
        mkdir -p -- "$scratch/$name" 2>/dev/null || true
    done < <(hostile_names)

    # A newline in a filename, which is its own category of misread.
    mkdir -p -- "$scratch/$(printf 'newline\nin-name')" 2>/dev/null || true

    # Things that must be OPENED, never RUN.
    printf '#!/bin/bash\ntouch "%s/CANARY-command"\n' "$canary_dir" > "$scratch/runme.command"
    chmod +x "$scratch/runme.command"
    printf '#!/bin/bash\ntouch "%s/CANARY-script"\n' "$canary_dir" > "$scratch/script.sh"
    chmod +x "$scratch/script.sh"

    # A canary .app: if a selected bundle is ever launched, this records it.
    local app="$scratch/Canary.app/Contents/MacOS"
    mkdir -p "$app"
    printf '#!/bin/bash\ntouch "%s/CANARY-app"\n' "$canary_dir" > "$app/Canary"
    chmod +x "$app/Canary"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict>' \
        '<key>CFBundleExecutable</key><string>Canary</string>' \
        '<key>CFBundleIdentifier</key><string>com.altmansoftwaredesign.yatu.canary</string>' \
        '<key>CFBundlePackageType</key><string>APPL</string>' \
        '</dict></plist>' > "$scratch/Canary.app/Contents/Info.plist"

    # A symlink to a file: rule 3 resolves it, then treats it as a file.
    printf 'contents\n' > "$scratch/target.txt"
    ln -s "$scratch/target.txt" "$scratch/link-to-file"
}

# MARK: - Firing

fired=0

# $1 = description, $2 = URL
fire() {
    local description=$1 url=$2
    fired=$((fired + 1))
    if (( dry_run )); then
        printf '  would fire  %-44s %s\n' "$description" "${url:0:90}"
        return
    fi
    open "$url" 2>/dev/null || true
    # Give the handler time to run before the next one.
    sleep 0.4
}

url_encode() {  # percent-encode a path for a query value
    local string=$1 out="" index char
    for (( index = 0; index < ${#string}; index++ )); do
        char="${string:index:1}"
        case "$char" in
            [a-zA-Z0-9.~_-]) out+="$char" ;;
            *) out+="$(printf '%%%02X' "'$char")" ;;
        esac
    done
    printf '%s' "$out"
}

fire_refusals() {
    print_colored "$COLOR_CYAN" "Malformed and out-of-contract URLs — nothing should launch"
    fire "unknown host"            "$SCHEME://execute?role=terminal&container=/tmp"
    fire "no role"                 "$SCHEME://open?container=/tmp"
    fire "unknown role"            "$SCHEME://open?role=root&container=/tmp"
    fire "nothing to open"         "$SCHEME://open?role=terminal"
    fire "app outside the catalog" "$SCHEME://open?role=terminal&app=NotAnApp&container=/tmp"
    fire "editor named as a terminal" "$SCHEME://open?role=terminal&app=Emacs&container=/tmp"
    fire "set-default outside the catalog" "$SCHEME://set-default?role=terminal&app=/bin/sh"
    fire "empty item, no container" "$SCHEME://open?role=terminal&item="

    # Over the cap: refused rather than truncated.
    local many=""
    local index
    for (( index = 0; index < 200; index++ )); do many+="&item=/tmp/$index"; done
    fire "200 items (cap is 64)" "$SCHEME://open?role=terminal$many"
}

fire_hostile_paths() {
    print_colored "$COLOR_CYAN" "Hostile paths, live — a terminal should open at each, running nothing"
    local name encoded
    while IFS= read -r name; do
        encoded="$(url_encode "$scratch/$name")"
        fire "folder: $name" "$SCHEME://open?role=terminal&container=$encoded"
    done < <(hostile_names)

    print_colored "$COLOR_CYAN" "Things that must be opened, never run"
    local item
    for item in runme.command script.sh Canary.app link-to-file target.txt; do
        encoded="$(url_encode "$scratch/$item")"
        fire "selected: $item" "$SCHEME://open?role=terminal&item=$encoded&container=$(url_encode "$scratch")"
    done
}

# MARK: - The verdict

report() {
    local failures=0

    print_colored "$COLOR_CYAN" "Canaries"
    local canaries=()
    while IFS= read -r -d '' found; do canaries+=("$found"); done \
        < <(find "$canary_dir" "$scratch" "$HOME" -maxdepth 2 -name 'CANARY-*' -print0 2>/dev/null)
    if (( ${#canaries[@]} )); then
        print_colored "$COLOR_RED" "  FAILED — something interpreted a filename or ran a file:"
        printf '    %s\n' "${canaries[@]}"
        failures=$((failures + 1))
    else
        print_colored "$COLOR_GREEN" "  none — no command substitution ran, and nothing selected was executed"
    fi

    print_colored "$COLOR_CYAN" "Rule 6: no file logging"
    # Dated against a marker taken before the first case. A file that was
    # already there was written by something else -- upstream's Lite build
    # still logs to ~/Library/Logs/logfile-N.log, which is finding L2 and is
    # not ours to fail on. Only a file this run produced is a failure.
    local fresh=() stale=()
    while IFS= read -r -d '' found; do fresh+=("$found"); done \
        < <(find "$HOME/Library/Logs" -maxdepth 1 \( -iname '*yatu*' -o -iname 'logfile*' \) \
                 -newer "$run_marker" -print0 2>/dev/null)
    while IFS= read -r -d '' found; do stale+=("$found"); done \
        < <(find "$HOME/Library/Logs" -maxdepth 1 \( -iname '*yatu*' -o -iname 'logfile*' \) \
                 ! -newer "$run_marker" -print0 2>/dev/null)

    if (( ${#fresh[@]} )); then
        print_colored "$COLOR_RED" "  FAILED — this run wrote a log file:"
        printf '    %s\n' "${fresh[@]}"
        failures=$((failures + 1))
    else
        print_colored "$COLOR_GREEN" "  none written by this run"
    fi
    if (( ${#stale[@]} )); then
        print_colored "$COLOR_YELLOW" "  pre-existing, not written by this run:"
        local file
        for file in "${stale[@]}"; do
            case "$(basename "$file")" in
                logfile-*.log) printf '    %s  (upstream OpenInTerminal, finding L2)\n' "$file" ;;
                *)             printf '    %s\n' "$file" ;;
            esac
        done
    fi

    print_colored "$COLOR_CYAN" "Rule 6: no paths in the unified log"
    local leaked
    leaked="$(log show --predicate "subsystem == \"$BUNDLE_ID\"" --last 5m --style compact 2>/dev/null \
        | grep -c "$scratch" || true)"
    if [[ "${leaked:-0}" -gt 0 ]]; then
        print_colored "$COLOR_RED" "  FAILED — $leaked entries contain a real path; paths must be .private"
        failures=$((failures + 1))
    else
        print_colored "$COLOR_GREEN" "  none"
    fi

    printf '\n'
    if (( failures )); then
        print_colored "$COLOR_RED" "$failures check(s) FAILED after $fired case(s) — do not release"
        return 1
    fi
    print_colored "$COLOR_GREEN" "All checks passed after $fired case(s)"
    return 0
}

# MARK: - Main

if (( dry_run )); then
    scratch="<scratch>"
    canary_dir="<scratch>/canaries"
    print_colored "$COLOR_BRIGHTYELLOW" "Dry run — nothing is created, fired or changed"
    fire_refusals
    (( live )) && fire_hostile_paths
    printf '\n%s\n' "$fired case(s) would be fired"
    exit 0
fi

if (( live )) && (( ! assume_yes )); then
    print_colored "$COLOR_BRIGHTYELLOW" "--live opens a terminal window per case (about 20)."
    printf 'Continue? [y/N] '
    read -r answer
    [[ "$answer" == [yY]* ]] || { print_colored "$COLOR_YELLOW" "Nothing done."; exit 0; }
fi

[[ -d /Applications/Yatu.app ]] || die "/Applications/Yatu.app is not installed; nothing would handle $SCHEME://"

preferences_backup="$(mktemp "${TMPDIR:-/tmp}/yatu-prefs.XXXXXX.plist")"
defaults export "$BUNDLE_ID" "$preferences_backup" >/dev/null 2>&1 || : > "$preferences_backup"

build_corpus
# Everything after this point is dated against the marker.
run_marker="$(mktemp "${TMPDIR:-/tmp}/yatu-run-marker.XXXXXX")"
print_colored "$COLOR_YELLOW" "scratch: $scratch"
printf '\n'

fire_refusals
printf '\n'
if (( live )); then
    fire_hostile_paths
    printf '\n'
else
    print_colored "$COLOR_YELLOW" "Skipping the launching cases; pass --live to include them."
    printf '\n'
fi

# The handler is asynchronous; let the last case finish before judging.
sleep 2
report
