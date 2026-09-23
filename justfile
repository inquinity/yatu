# Project tasks. The work stays in bin/*.sh -- these recipes are the one place
# those scripts are named and strung together.
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

# Re-render the icon concept board for review. Changes nothing the app uses.
icon-concepts:
    docs/icon-concepts/make-concepts.swift docs/icon-concepts

# Report what is installed, whether the Finder extension is enabled, and what brew thinks.
which:
    bin/which-yatu.sh

# Read-only: has OpenInTerminal's app catalog moved since we vendored it?
check-upstream *args:
    bin/check-upstream.sh {{ args }}

# Shell-check every script (requires shellcheck).
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
