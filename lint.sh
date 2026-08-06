#!/bin/bash

# Copyright © Michal Čihař <michal@weblate.org>
#
# SPDX-License-Identifier: CC0-1.0

set -u -e

export ROOT="$PWD"

# shellcheck disable=SC1091
. "$ROOT/repo-common.sh"

lint_status=0

warning() {
    echo "WARNING: $1"
    lint_status=1
}

uses_pre_commit_dependency_group() {
    awk '
        /^\[dependency-groups\]$/ {
            dependency_groups = 1
            next
        }
        /^\[/ {
            dependency_groups = 0
        }
        dependency_groups && /^pre-commit[[:space:]]*=/ {
            found = 1
        }
        END {
            exit !found
        }
    ' pyproject.toml
}

for repo in $REPOS; do
    prepare_repository "$repo" > /dev/null
    cd "$ROOT/repos/$repo"

    echo "== $repo =="

    if ! grep -q Logo-Darktext-borders.png README.* 2> /dev/null; then
        warning "README does not contain logo."
    fi

    if [ -f pyproject.toml ] && ! uses_pre_commit_dependency_group; then
        warning "pyproject.toml does not use pre-commit dependency group."
    fi

    echo
done

exit "$lint_status"
