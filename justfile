# Fork-owned tasks. Upstream has no justfile, so this file is unambiguously
# ours and never conflicts on merge. The work stays in bin/*.sh -- these
# recipes are the one place those scripts are named and strung together.
#
# Requires `just` (brew install just). Every recipe also works by calling the
# underlying bin/ script directly.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# List the available tasks.
default:
    @just --list

# Build Yatu's app bundles into .build/app. Pass `terminal` or `editor` for one role.
build *args:
    bin/build.sh {{ args }}

# Run the unit tests.
test *args:
    swift test {{ args }}

# Read or bump the version in VERSION. See `bin/ver --help`.
ver *args:
    bin/ver {{ args }}

# Regenerate Resources/AppIcon.icns (currently a placeholder; see the plan, 8.6).
icon:
    bin/make-icon.swift Resources/AppIcon.icns

# Local ad-hoc build of the UPSTREAM apps into ./export (no Developer ID needed).
# Yatu is built by `just build`; this is here to keep upstream's tree buildable.
build-upstream *args:
    bin/build-unsigned.sh {{ args }}

# Developer ID signed + notarized build. Pass a scheme, e.g. `just build-signed OpenInTerminal-Lite`.
build-signed *args:
    NOTARY_PROFILE="${NOTARY_PROFILE:-altman-notary}" bin/build-signed.sh {{ args }}

# Report which build is installed (fork, upstream, or unknown) and what brew thinks.
which:
    bin/which-yatu.sh

# Read-only: has upstream moved ahead of this fork?
check-upstream *args:
    bin/check-upstream.sh {{ args }}

# What this fork changes on top of upstream. Pass --stat, --files or --commits.
private-changes *args:
    bin/show-private-changes.sh {{ args }}

# Shell-check every fork-owned script (requires shellcheck).
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "shellcheck not installed (brew install shellcheck); running bash -n only" >&2
    fi
    for script in bin/*.sh bin/ver; do
        bash -n "$script"
        if command -v shellcheck >/dev/null 2>&1; then
            shellcheck -S warning "$script"
        fi
    done
    echo "scripts OK"
