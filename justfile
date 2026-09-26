# Project tasks. The work stays in bin/*.sh -- these recipes are the one place
# those scripts are named and strung together.
#
# Requires `just` (brew install just). Every recipe also works by calling the
# underlying bin/ script directly.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# List the available tasks.
default:
    @just --list

# Build Yatu.app into dist/.
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

# Fire hostile input at an INSTALLED Yatu. Scratch only; prefs restored. See --help.
attack-matrix *args:
    bin/attack-matrix.sh {{ args }}

# Check a release without publishing: artifacts, provenance, tag, tap. Changes nothing.
release-check:
    bin/release.sh

# Publish the release. Irreversible. Build, notarize and package first.
release-go:
    bin/release.sh --go

# Test the shell in bin/. Stubs its dependencies; changes nothing on this Mac.
test-scripts:
    bin/test-scripts.sh

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
